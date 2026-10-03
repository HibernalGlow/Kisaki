use flutter_rust_bridge::frb;

use crate::api::types::{DeleteOutcome, DeleteRequest, ExportRequest, MoveOutcome, MoveRequest, RenameOutcome, RenameRequest};
use crate::engine::{fix, ops, relocate, runner};

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

/// Moves or copies the selection into a destination folder. czkawka_core has no move API, so this is
/// the one action the frontend owns outright. A dry run plans it, and a name already in the
/// destination is skipped unless the request asks for something else.
#[frb]
pub async fn move_files(request: MoveRequest) -> Result<MoveOutcome, String> {
    runner::blocking(move || relocate::apply(&request)).await
}
