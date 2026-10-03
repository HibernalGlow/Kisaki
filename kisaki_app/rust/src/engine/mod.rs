pub mod config;
pub mod convert;
pub mod dispatch;
pub mod exif;
pub mod fix;
pub mod flat;
pub mod grouped;
pub mod ops;
pub mod options;
pub mod progress;
pub mod registry;
pub mod relocate;
pub mod runner;

use std::path::PathBuf;

use crate::api::types::{FieldPayload, FieldValue, ScanRow};

/// One result row in engine-internal form: paths stay `PathBuf` until the FFI boundary.
pub struct EngineRow {
    pub path: PathBuf,
    pub name: String,
    pub directory: String,
    pub cells: Vec<String>,
    pub sort_keys: Vec<i64>,
    pub size_bytes: u64,
    pub modified_ts: u64,
    pub group_index: i32,
    pub group_size: i32,
    pub is_group_start: bool,
    pub is_reference: bool,
}

pub struct EngineOutcome {
    pub rows: Vec<EngineRow>,
    pub grouped: bool,
    pub stopped: bool,
    /// Text produced by the engine's message list, untranslated and shown verbatim in the log panel.
    pub messages: String,
    pub critical: Option<String>,
}

impl EngineRow {
    /// Splits a full path into the name and directory the results table shows.
    pub fn new(path: PathBuf, cells: Vec<String>, sort_keys: Vec<i64>, size_bytes: u64, modified_ts: u64) -> EngineRow {
        let (directory, name) = czkawka_core::common::split_path(path.as_path());
        EngineRow {
            path,
            name,
            directory,
            cells,
            sort_keys,
            size_bytes,
            modified_ts,
            group_index: -1,
            group_size: 0,
            is_group_start: false,
            is_reference: false,
        }
    }
}

impl From<EngineRow> for ScanRow {
    fn from(row: EngineRow) -> ScanRow {
        ScanRow {
            path: row.path.to_string_lossy().into_owned(),
            name: row.name,
            directory: row.directory,
            cells: row.cells,
            size_bytes: row.size_bytes as i64,
            modified_ts: row.modified_ts as i64,
            group_index: row.group_index,
            group_size: row.group_size,
            is_group_start: row.is_group_start,
            is_reference: row.is_reference,
            sort_keys: row.sort_keys,
        }
    }
}

/// A tool's option values, keyed by field id.
///
/// These accessors are deliberately default-free: each scanner module wraps them with the
/// defaults it owns, so a missing option is decided by the code that consumes it.
pub struct FieldStore {
    values: Vec<FieldValue>,
}

impl FieldStore {
    pub fn new(values: Vec<FieldValue>) -> FieldStore {
        FieldStore { values }
    }

    pub fn flag(&self, id: &str) -> bool {
        self.payload(id).and_then(FieldPayload::as_flag).unwrap_or(false)
    }

    pub fn choice(&self, id: &str) -> String {
        self.payload(id).and_then(FieldPayload::as_choice).unwrap_or_default()
    }

    pub fn integer(&self, id: &str) -> i64 {
        self.payload(id).and_then(FieldPayload::as_integer).unwrap_or(0)
    }

    /// Raw access, so callers can accept either a token list or one separated string.
    pub fn payload(&self, id: &str) -> Option<&FieldPayload> {
        self.values.iter().find(|value| value.id == id).map(|value| &value.value)
    }
}

impl FieldPayload {
    pub fn as_flag(&self) -> Option<bool> {
        if let FieldPayload::Flag(value) = self { Some(*value) } else { None }
    }

    pub fn as_choice(&self) -> Option<String> {
        if let FieldPayload::Choice(value) = self { Some(value.clone()) } else { None }
    }

    pub fn as_integer(&self) -> Option<i64> {
        if let FieldPayload::Integer(value) = self { Some(*value) } else { None }
    }

    pub fn as_text(&self) -> Option<String> {
        if let FieldPayload::Text(value) = self { Some(value.clone()) } else { None }
    }

    pub fn as_tokens(&self) -> Option<Vec<String>> {
        if let FieldPayload::Tokens(value) = self { Some(value.clone()) } else { None }
    }
}
