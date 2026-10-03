use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;

use crate::api::types::{ScanEvent, ScanRequest};
use crate::engine::runner;

/// Starts a scan and streams every engine progress tick, ending with exactly one terminal event.
#[frb]
pub async fn start_scan(request: ScanRequest, sink: StreamSink<ScanEvent>) -> Result<(), String> {
    runner::spawn(request, sink).await
}

/// Asks the running scan to stop at the next checkpoint; the partial result is still delivered.
#[frb(sync)]
pub fn request_stop() -> bool {
    runner::request_stop()
}

#[frb(sync)]
pub fn is_scanning() -> bool {
    runner::is_running()
}
