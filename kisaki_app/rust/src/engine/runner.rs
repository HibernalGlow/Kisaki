use std::sync::Arc;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

use crossbeam_channel::Sender;
use czkawka_core::common::consts::DEFAULT_THREAD_SIZE;
use czkawka_core::common::progress_data::ProgressData;
use crate::frb_generated::StreamSink;
use futures::channel::oneshot;

use crate::api::types::{ScanEvent, ScanOutcome, ScanRequest};
use crate::engine::{EngineOutcome, convert, dispatch, progress};

/// Only one scan may own the engine at a time; the stop flag is shared with the worker.
fn stop_flag() -> &'static Arc<AtomicBool> {
    static FLAG: OnceLock<Arc<AtomicBool>> = OnceLock::new();
    FLAG.get_or_init(|| Arc::new(AtomicBool::new(false)))
}

static RUNNING: AtomicBool = AtomicBool::new(false);

pub fn is_running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

pub fn request_stop() -> bool {
    if !is_running() {
        return false;
    }
    stop_flag().store(true, Ordering::Relaxed);
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

    let scan_result = thread::Builder::new()
        .name("kisaki-scan".to_string())
        .stack_size(DEFAULT_THREAD_SIZE)
        .spawn(move || {
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

/// Runs a blocking engine call off the FRB executor, used by delete and export.
pub async fn blocking<F, T>(work: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String> + Send + 'static,
    T: Send + 'static,
{
    let (tx, rx) = oneshot::channel();
    thread::Builder::new()
        .stack_size(DEFAULT_THREAD_SIZE)
        .spawn(move || {
            let _ = tx.send(work());
        })
        .map_err(|error| format!("Failed to start worker thread: {error}"))?;
    rx.await.map_err(|_| "Worker thread panicked".to_string())?
}

/// Shared progress sender type, kept here so dispatch cannot invent its own.
pub type ProgressSender = Sender<ProgressData>;
