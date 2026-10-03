/// One user-facing scanner, described so Dart can render it without hardcoding a table per tool.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolSpec {
    pub id: String,
    pub glyph: String,
    pub label_key: String,
    pub grouped: bool,
    pub supports_reference: bool,
    pub columns: Vec<ColumnDef>,
    pub field_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ColumnDef {
    pub key: String,
    pub label_key: String,
    pub flex: f64,
    pub min_width: f64,
    pub align_right: bool,
}

/// How Dart should render one option of the algorithm tab.
#[derive(Debug, Clone, PartialEq)]
pub enum FieldKind {
    Flag,
    Choice,
    Integer,
    Text,
    TokenList,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FieldDef {
    pub id: String,
    pub label_key: String,
    pub kind: FieldKind,
    pub options: Vec<String>,
    pub min: i64,
    pub max: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FieldValue {
    pub id: String,
    pub value: FieldPayload,
}

/// Payload of one option. Only the variant matching the field's `FieldKind` is ever sent.
#[derive(Debug, Clone, PartialEq)]
pub enum FieldPayload {
    Flag(bool),
    Choice(String),
    Integer(i64),
    Text(String),
    Tokens(Vec<String>),
}

/// Everything a single scan needs: the shared path/filter block plus the per-tool options.
#[derive(Debug, Clone, PartialEq)]
pub struct ScanRequest {
    pub tool: String,
    pub included: Vec<String>,
    pub reference: Vec<String>,
    pub excluded_paths: Vec<String>,
    pub excluded_items: Vec<String>,
    pub allowed_extensions: Vec<String>,
    pub excluded_extensions: Vec<String>,
    pub recursive: bool,
    pub use_cache: bool,
    pub min_size_kib: String,
    pub max_size_kib: String,
    pub fields: Vec<FieldValue>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProgressUpdate {
    pub stage_label_key: String,
    pub current: i64,
    pub total: i64,
    pub percent: i64,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScanRow {
    pub path: String,
    pub name: String,
    pub directory: String,
    /// Extra cells aligned with `ToolSpec.columns`, already formatted for display.
    pub cells: Vec<String>,
    pub size_bytes: i64,
    pub modified_ts: i64,
    pub group_index: i32,
    pub group_size: i32,
    pub is_group_start: bool,
    pub is_reference: bool,
    /// Numeric sort keys aligned with `cells`, so Dart sorts without parsing display text.
    pub sort_keys: Vec<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScanOutcome {
    pub tool: String,
    pub rows: Vec<ScanRow>,
    pub stopped: bool,
    pub grouped: bool,
    pub file_count: i32,
    pub group_count: i32,
    pub total_bytes: i64,
    pub reclaimable_bytes: i64,
    pub messages: String,
    pub critical: Option<String>,
}

/// The scan topic carries terminal events too, so Dart needs one stream rather than two.
#[derive(Debug, Clone, PartialEq)]
pub enum ScanEvent {
    Progress(ProgressUpdate),
    Completed(ScanOutcome),
    Failed(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeleteRequest {
    pub tool: String,
    pub rows: Vec<ScanRow>,
    pub delete_to_trash: bool,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeleteOutcome {
    pub affected: i32,
    pub errors: i32,
    pub reclaimed_bytes: i64,
    pub messages: String,
    pub log: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExportRequest {
    pub tool: String,
    pub rows: Vec<ScanRow>,
    pub path: String,
    pub format: String,
    pub grouped: bool,
}

/// A rename run. The engine decides the new name, so the request carries the option block of the
/// scan that produced the rows plus the selection to act on. Dry run decides without touching disk.
#[derive(Debug, Clone, PartialEq)]
pub struct RenameRequest {
    pub tool: String,
    pub scan: ScanRequest,
    pub paths: Vec<String>,
    pub dry_run: bool,
}

/// What happened to one selected file.
#[derive(Debug, Clone, PartialEq)]
pub enum RenameStatus {
    /// A rename the run performed.
    Renamed,
    /// A rename a dry run would have performed.
    Planned,
    /// Blocked: the name was already taken or the filesystem refused.
    Failed,
    /// The engine found nothing to change.
    Skipped,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RenameItem {
    pub from: String,
    pub to: String,
    pub status: RenameStatus,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RenameOutcome {
    pub renamed: i32,
    pub planned: i32,
    pub failed: i32,
    pub skipped: i32,
    /// One entry per selected path, in request order.
    pub items: Vec<RenameItem>,
    pub messages: String,
}

/// Whether the original stays where it is.
#[derive(Debug, Clone, PartialEq)]
pub enum MoveAction {
    Move,
    Copy,
}

/// What to do when the destination already holds the requested name. `Skip` is the default because
/// a GUI action must never destroy a file the user did not choose to replace.
#[derive(Debug, Clone, PartialEq)]
pub enum ConflictPolicy {
    Skip,
    Overwrite,
    /// Takes `name (1).ext`, `name (2).ext`, ... until a slot is free.
    Rename,
    Error,
}

/// Moves or copies the selection into one destination folder.
#[derive(Debug, Clone, PartialEq)]
pub struct MoveRequest {
    pub paths: Vec<String>,
    pub destination: String,
    pub action: MoveAction,
    pub conflict: ConflictPolicy,
    /// Mirrors each file's folder trail under the filesystem root instead of dropping everything
    /// into the destination flat.
    pub preserve_structure: bool,
    pub dry_run: bool,
}

/// What happened to one selected file.
#[derive(Debug, Clone, PartialEq)]
pub enum MoveStatus {
    Moved,
    Copied,
    Planned,
    Skipped,
    Failed,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MoveItem {
    pub from: String,
    pub to: String,
    pub status: MoveStatus,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MoveOutcome {
    pub moved: i32,
    pub copied: i32,
    pub planned: i32,
    pub skipped: i32,
    pub failed: i32,
    /// One entry per selected path, in request order.
    pub items: Vec<MoveItem>,
    pub messages: String,
}

/// Strips EXIF tags from the selection. `override_file` writes back over the original; the default
/// leaves it untouched and writes a side file, because discarding metadata is not reversible.
#[derive(Debug, Clone, PartialEq)]
pub struct ExifRequest {
    /// The scan block that produced the rows, so the engine sees the same options and folders.
    pub scan: ScanRequest,
    pub paths: Vec<String>,
    pub override_file: bool,
    pub dry_run: bool,
}

/// What happened to one selected file.
#[derive(Debug, Clone, PartialEq)]
pub enum ExifStatus {
    /// Written over the original.
    Stripped,
    /// Original untouched, cleaned copy written next to it.
    Candidate,
    Planned,
    /// Nothing to remove, or the engine did not report the file.
    Skipped,
    Failed,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExifItem {
    pub path: String,
    /// Where the result was written; empty while a file is skipped.
    pub target: String,
    pub tags_removed: i32,
    pub status: ExifStatus,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExifOutcome {
    pub stripped: i32,
    pub candidates: i32,
    pub planned: i32,
    pub skipped: i32,
    pub failed: i32,
    /// One entry per selected path, in request order.
    pub items: Vec<ExifItem>,
    pub messages: String,
}

/// How a file reaches its set folder: relocated, duplicated, or a second name for the same bytes.
#[derive(Debug, Clone, PartialEq)]
pub enum SimiuMode {
    Move,
    Copy,
    Link,
}

/// One "put this file in that set folder" decision. Which images belong to which set is a judgement
/// about the scan result, so the board makes it and the bridge only performs it and journals it.
#[derive(Debug, Clone, PartialEq)]
pub struct SimiuOperation {
    /// The scanned root the set folder lives under; one undo journal is written per root.
    pub root: String,
    pub source: String,
    pub target: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimiuApplyRequest {
    pub mode: SimiuMode,
    pub operations: Vec<SimiuOperation>,
    pub dry_run: bool,
}

/// What happened to one file, for both the apply and the undo direction.
#[derive(Debug, Clone, PartialEq)]
pub enum SimiuStatus {
    Planned,
    Moved,
    Copied,
    Linked,
    /// Restored to its original place by an undo.
    Restored,
    /// A copied or linked result that an undo removed again.
    Removed,
    Failed,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimiuItem {
    pub from: String,
    pub to: String,
    pub status: SimiuStatus,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimiuApplyOutcome {
    pub done: i32,
    pub planned: i32,
    pub failed: i32,
    pub items: Vec<SimiuItem>,
    /// The undo journals written, newest last. Empty for a dry run.
    pub journals: Vec<String>,
    pub messages: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimiuUndoRequest {
    pub journal: String,
    /// Removes the set folders an apply created, as long as they are empty by then.
    pub clean_empty_directories: bool,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimiuUndoOutcome {
    pub done: i32,
    pub planned: i32,
    pub failed: i32,
    pub items: Vec<SimiuItem>,
    pub messages: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct EngineInfo {
    pub core_version: String,
    pub api_version: i32,
    pub os: String,
    pub thread_limit: i32,
}
