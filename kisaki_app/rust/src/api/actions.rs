use flutter_rust_bridge::frb;

use crate::api::types::{DeleteOutcome, DeleteRequest, ExportRequest, RenameOutcome, RenameRequest};
use crate::engine::{fix, ops, runner};

/// Deletes or trashes the selected rows through the engine's own file operations, so trash
/// behaviour matches every other frontend. Dry run plans without touching the filesystem.
#[frb]
pub async fn delete_files(request: DeleteRequest) -> Result<DeleteOutcome, String> {
    runner::blocking(move || ops::delete(request)).await
}

/// Writes the current result set to disk as JSON or CSV.
#[frb]
pub async fn export_results(request: ExportRequest) -> Result<String, String> {
    runner::blocking(move || ops::export(request)).await
}

/// Renames the selected files to the names the engine considers correct, for the two tools whose
/// result is a name: bad names and bad extensions. A dry run reports the plan without touching disk.
#[frb]
pub async fn rename_files(request: RenameRequest) -> Result<RenameOutcome, String> {
    runner::blocking(move || fix::rename(&request)).await
}
