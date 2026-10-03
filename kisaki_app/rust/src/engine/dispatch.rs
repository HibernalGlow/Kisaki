use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use crate::api::types::ScanRequest;
use crate::engine::EngineOutcome;
use crate::engine::runner::ProgressSender;
use crate::engine::{flat, grouped, registry};

/// Runs one scan to completion on the calling thread, pushing engine progress into `sender` and
/// honouring `stop`. Grouped and flat scanners share this entry point so the request shape stays
/// identical for Dart.
pub fn run(request: &ScanRequest, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    let spec = registry::spec(&request.tool).ok_or_else(|| format!("Unknown scanner '{}'", request.tool))?;
    let store = crate::engine::options::store(request);

    if request.included.is_empty() && request.reference.is_empty() {
        return Err("No included or reference paths".to_string());
    }

    if spec.grouped { grouped::run(&spec, request, &store, sender, stop) } else { flat::run(&spec, request, &store, sender, stop) }
}
