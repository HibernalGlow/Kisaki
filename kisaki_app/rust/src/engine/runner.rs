use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

use crossbeam_channel::Sender;
use czkawka_core::common::consts::DEFAULT_THREAD_SIZE;
use czkawka_core::common::progress_data::ProgressData;
use futures::channel::oneshot;

use crate::api::types::{ScanEvent, ScanOutcome, ScanRequest};
use crate::engine::{EngineOutcome, convert, dispatch, progress};
use crate::frb_generated::StreamSink;

/// Only one scan may own the engine at a time; the stop flag is shared with the worker.
fn stop_flag() -> &'static Arc<AtomicBool> {
    static FLAG: OnceLock<Arc<AtomicBool>> = OnceLock::new();
    FLAG.get_or_init(|| Arc::new(AtomicBool::new(false)))
}

/// The stop flag of the file operation running on a `blocking` worker, if any.
fn operations() -> &'static Mutex<Option<Arc<AtomicBool>>> {
    static SLOT: OnceLock<Mutex<Option<Arc<AtomicBool>>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// The flag a verb polls between items. Called outside a worker - in tests, or for a verb driven
/// directly - it hands back a fresh idle flag, so a stale signal can never stop an unrelated run.
pub(crate) fn operation_stop() -> Arc<AtomicBool> {
    operations()
        .lock()
        .expect("operation slot was poisoned")
        .clone()
        .unwrap_or_else(|| Arc::new(AtomicBool::new(false)))
}

static RUNNING: AtomicBool = AtomicBool::new(false);

pub fn is_running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

/// Asks whatever is in flight - a scan or one file operation - to stop at its next checkpoint.
pub fn request_stop() -> bool {
    let slot = operations().lock().expect("operation slot was poisoned");
    if !is_running() && slot.is_none() {
        return false;
    }
    stop_flag().store(true, Ordering::Relaxed);
    if let Some(stop) = slot.as_ref() {
        stop.store(true, Ordering::Relaxed);
    }
    true
}

/// Runs the scan on a dedicated stack-sized thread, forwarding engine progress to Dart as it
/// happens. The stream stays open until the worker reports, so the caller awaits rather than
/// returning early - returning would close the sink and drop the final event.
pub async fn spawn(request: ScanRequest, sink: StreamSink<ScanEvent>) -> Result<(), String> {
    if RUNNING.swap(true, Ordering::SeqCst) {
        return Err("A scan is already running".to_string());
    }
    stop_flag().store(false, Ordering::Relaxed);

    let tool = request.tool.clone();
    let (progress_tx, progress_rx) = crossbeam_channel::unbounded::<ProgressData>();
    let (done_tx, done_rx) = oneshot::channel::<Result<EngineOutcome, String>>();
    let stop = Arc::clone(stop_flag());

    // The forwarder ends when the scan thread drops its sender, which happens exactly when the
    // engine finishes reporting, so no separate shutdown signal is needed.
    let progress_sink = sink.clone();
    if let Err(error) = thread::Builder::new().name("kisaki-progress".to_string()).spawn(move || {
        while let Ok(data) = progress_rx.recv() {
            if progress_sink.add(ScanEvent::Progress(progress::humanize(&data))).is_err() {
                break;
            }
        }
    }) {
        RUNNING.store(false, Ordering::SeqCst);
        return Err(format!("Failed to start progress forwarder: {error}"));
    }

    let scan_result = thread::Builder::new().name("kisaki-scan".to_string()).stack_size(DEFAULT_THREAD_SIZE).spawn(move || {
        let outcome = dispatch::run(&request, progress_tx.clone(), Arc::clone(&stop));
        drop(progress_tx);
        let _ = done_tx.send(outcome);
    });

    let _scan_thread = match scan_result {
        Ok(handle) => handle,
        Err(error) => {
            RUNNING.store(false, Ordering::SeqCst);
            return Err(format!("Failed to start scanning thread: {error}"));
        }
    };

    let outcome = done_rx.await.map_err(|_| "Scanning thread panicked".to_string());
    RUNNING.store(false, Ordering::SeqCst);

    // Failures travel as events, not as a rejected future, so the Dart listener sees one shape.
    let outcome = match outcome {
        Ok(Ok(outcome)) => outcome,
        Ok(Err(error)) => {
            let _ = sink.add(ScanEvent::Failed(error));
            return Ok(());
        }
        Err(error) => {
            let _ = sink.add(ScanEvent::Failed(error));
            return Ok(());
        }
    };

    let outcome: ScanOutcome = convert::outcome(tool, outcome);
    sink.add(ScanEvent::Completed(outcome)).map_err(|_| "Scan stream was closed by Dart".to_string())
}

/// Runs a blocking engine call off the FRB executor. One file operation at a time: the stop flag
/// belongs to whichever operation holds the slot, so a request cannot interrupt the wrong batch.
pub async fn blocking<F, T>(work: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String> + Send + 'static,
    T: Send + 'static,
{
    let (tx, rx) = oneshot::channel();
    {
        let mut slot = operations().lock().expect("operation slot was poisoned");
        if slot.is_some() {
            return Err("Another file operation is already running".to_string());
        }
        *slot = Some(Arc::new(AtomicBool::new(false)));
    }

    let worker = thread::Builder::new()
        .stack_size(DEFAULT_THREAD_SIZE)
        .spawn(move || {
            let _ = tx.send(work());
        })
        .map_err(|error| format!("Failed to start worker thread: {error}"));
    let worker = match worker {
        Ok(worker) => worker,
        Err(error) => {
            *operations().lock().expect("operation slot was poisoned") = None;
            return Err(error);
        }
    };
    let received = rx.await;
    *operations().lock().expect("operation slot was poisoned") = None;
    let _ = worker.join();
    received.map_err(|_| "Worker thread panicked".to_string())?
}

/// Shared progress sender type, kept here so dispatch cannot invent its own.
pub type ProgressSender = Sender<ProgressData>;

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    /// The operation slot is process-wide, so these tests must not run against each other.
    static SERIAL: Mutex<()> = Mutex::new(());

    #[test]
    fn a_stop_request_reaches_the_operation_in_flight() {
        let _guard = SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        assert!(!request_stop(), "nothing is in flight, so there is nothing to stop");

        let observed = futures::executor::block_on(blocking(|| Ok(operation_stop().load(Ordering::Relaxed)))).expect("worker ran");
        assert!(!observed, "a new operation starts un-stopped");
        assert!(!request_stop(), "a finished operation must not stay registered");

        // Held open by a gate, so the checks below race nothing: the worker signals that it is running
        // and only continues once the test has looked at the flag.
        let (probe_tx, probe_rx) = crossbeam_channel::unbounded::<bool>();
        let (gate_tx, gate_rx) = crossbeam_channel::unbounded::<()>();
        let worker = thread::spawn(move || {
            futures::executor::block_on(blocking(move || {
                probe_tx.send(request_stop()).expect("send the probe result");
                gate_rx.recv().expect("hold the operation open");
                Ok(())
            }))
        });

        assert!(
            probe_rx.recv_timeout(Duration::from_secs(10)).expect("operation started"),
            "a stop request must reach the running operation"
        );
        assert!(operation_stop().load(Ordering::Relaxed), "the flag the operation holds is the one a request signals");
        gate_tx.send(()).expect("release the worker");
        worker.join().expect("worker finishes").expect("operation completes");
        assert!(!request_stop(), "the slot is free again once the operation ends");
    }

    #[test]
    fn two_operations_do_not_run_at_once() {
        let _guard = SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let (start_tx, start_rx) = crossbeam_channel::unbounded::<()>();
        let (release_tx, release_rx) = crossbeam_channel::unbounded::<()>();
        let first = thread::spawn(move || {
            futures::executor::block_on(blocking(move || {
                start_tx.send(()).expect("signal the first operation");
                release_rx.recv().expect("wait for the test");
                Ok(())
            }))
        });

        start_rx.recv_timeout(Duration::from_secs(10)).expect("first operation running");
        let refusal = futures::executor::block_on(blocking(|| Ok("second")));
        match refusal {
            Ok(_) => panic!("the second call must be refused while the first still holds the slot"),
            Err(message) => assert_eq!(message, "Another file operation is already running"),
        }

        release_tx.send(()).expect("release the first operation");
        first.join().expect("first worker finishes").expect("first operation completes");
    }
}
