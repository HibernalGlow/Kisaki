use flutter_rust_bridge::frb;

use crate::api::types::{ScanEvent, ScanRequest};
use crate::engine::runner;
use crate::frb_generated::StreamSink;

/// Starts a scan and streams every engine progress tick, ending with exactly one terminal event.
#[frb]
pub async fn start_scan(request: ScanRequest, sink: StreamSink<ScanEvent>) -> Result<(), String> {
    runner::spawn(request, sink).await
}

/// Asks whatever is in flight to stop at its next checkpoint: a scan keeps its partial result, and a
/// file operation reports the rows it never attempted as stopped. Returns false when nothing runs.
#[frb(sync)]
pub fn request_stop() -> bool {
    runner::request_stop()
}

/// Whether a scan is running. File operations are not scans: they are serialized on their own stop
/// flag, so a second one is refused rather than started.
#[frb(sync)]
pub fn is_scanning() -> bool {
    runner::is_running()
}
