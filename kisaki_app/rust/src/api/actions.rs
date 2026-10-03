use flutter_rust_bridge::frb;

use crate::api::types::{
    DeleteOutcome, DeleteRequest, ExifOutcome, ExifRequest, ExportRequest, MoveOutcome, MoveRequest, RenameOutcome, RenameRequest, SimiuApplyOutcome, SimiuApplyRequest,
    SimiuUndoOutcome, SimiuUndoRequest,
};
use crate::engine::{exif, fix, ops, relocate, runner, simiu};

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

/// Strips EXIF tags from the selected photos through the engine's own remover. The original file is
/// left alone by default and the cleaned copy is written beside it; `override_file` replaces it.
#[frb]
pub async fn clean_exif(request: ExifRequest) -> Result<ExifOutcome, String> {
    runner::blocking(move || exif::strip(&request)).await
}

/// Sorts files into the set folders the board chose for a similar-images result. Nothing is ever
/// written over an existing file, and each scanned root gets an undo journal that `undo_simiu_set`
/// can replay. A dry run reports the plan and writes no journal.
#[frb]
pub async fn apply_simiu_set(request: SimiuApplyRequest) -> Result<SimiuApplyOutcome, String> {
    runner::blocking(move || simiu::apply(&request)).await
}

/// Reverses one Simiu undo journal, newest operation first. Copy and link results are removed again;
/// a move goes back to its recorded source unless something else took that name.
#[frb]
pub async fn undo_simiu_set(request: SimiuUndoRequest) -> Result<SimiuUndoOutcome, String> {
    runner::blocking(move || simiu::undo(&request)).await
}
