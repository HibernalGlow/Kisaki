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

#[derive(Debug, Clone, PartialEq)]
pub struct EngineInfo {
    pub core_version: String,
    pub api_version: i32,
    pub os: String,
    pub thread_limit: i32,
}
