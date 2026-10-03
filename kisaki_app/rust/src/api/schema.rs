use flutter_rust_bridge::frb;

use crate::api::types::{FieldDef, FieldValue, ToolSpec};
use crate::engine::registry;

/// All scanners, in the order the tool menu and results table expect.
#[frb(sync)]
pub fn list_tools() -> Vec<ToolSpec> {
    registry::tools()
}

#[frb(sync)]
pub fn field_defs(tool: String) -> Vec<FieldDef> {
    registry::fields(&tool)
}

#[frb(sync)]
pub fn default_fields(tool: String) -> Vec<FieldValue> {
    registry::defaults(&tool)
}
