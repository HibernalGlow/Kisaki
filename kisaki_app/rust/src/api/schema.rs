use flutter_rust_bridge::frb;

use crate::api::presentation;
use crate::api::types::{ColumnDef, FieldDef, FieldValue, ToolSpec};
use crate::engine::registry;

/// Turns one engine column into the table description Dart renders, adding the toolkit numbers the
/// engine deliberately does not know about.
fn to_def(column: registry::ColumnKey) -> ColumnDef {
    let (flex, min_width, align_right) = presentation::layout(&column.key);
    ColumnDef {
        key: column.key,
        label_key: column.label_key,
        flex,
        min_width,
        align_right,
    }
}

fn to_spec(view: registry::ToolView) -> ToolSpec {
    ToolSpec {
        id: view.id,
        glyph: view.glyph,
        label_key: view.label_key,
        grouped: view.grouped,
        supports_reference: view.supports_reference,
        columns: view.columns.into_iter().map(to_def).collect(),
        field_ids: view.field_ids,
    }
}

/// All scanners, in the order the tool menu and results table expect.
#[frb(sync)]
pub fn list_tools() -> Vec<ToolSpec> {
    registry::views().into_iter().map(to_spec).collect()
}

#[frb(sync)]
pub fn field_defs(tool: String) -> Vec<FieldDef> {
    registry::fields(&tool)
}

#[frb(sync)]
pub fn default_fields(tool: String) -> Vec<FieldValue> {
    registry::defaults(&tool)
}
