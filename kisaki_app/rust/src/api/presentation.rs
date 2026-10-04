/// Toolkit numbers for the results table, kept away from `engine::registry` so a different UI can
/// lay the same columns out its own way. Keys match `ColumnKey::key`.
const LAYOUTS: &[(&str, f64, f64, bool)] = &[
    ("artist", 1.0, 100.0, false),
    ("bitrate", 0.6, 76.0, true),
    ("codec", 0.7, 70.0, false),
    ("current_extension", 0.7, 70.0, false),
    ("destination", 1.4, 140.0, false),
    ("difference", 0.7, 90.0, false),
    ("duration", 0.6, 70.0, false),
    ("errors", 1.6, 160.0, false),
    ("genre", 0.8, 70.0, false),
    ("info", 1.2, 120.0, false),
    ("length", 0.5, 60.0, true),
    ("modified", 1.0, 140.0, false),
    ("new_name", 1.4, 150.0, false),
    ("proper_extension", 0.8, 80.0, false),
    ("proper_group", 0.8, 80.0, false),
    ("resolution", 0.7, 90.0, false),
    ("size", 0.5, 84.0, true),
    ("tags", 1.8, 180.0, false),
    ("title", 1.2, 120.0, false),
    ("year", 0.4, 50.0, false),
];

/// Flex, minimum width and right alignment for one column key, or the neutral defaults when a new
/// column has not been given a layout yet.
pub fn layout(key: &str) -> (f64, f64, bool) {
    LAYOUTS
        .iter()
        .find(|(name, ..)| *name == key)
        .map_or((1.0, 84.0, false), |(_, flex, min_width, align_right)| (*flex, *min_width, *align_right))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::registry;

    #[test]
    fn every_registered_column_has_a_positive_layout() {
        let mut keys = Vec::new();
        for tool in registry::views() {
            for column in tool.columns {
                assert!(LAYOUTS.iter().any(|(name, ..)| *name == column.key), "{} has no layout entry", column.key);
                let (flex, min_width, _) = layout(&column.key);
                assert!(flex > 0.0 && min_width > 0.0, "{} has a non-positive layout", column.key);
                if !keys.contains(&column.key) {
                    keys.push(column.key);
                }
            }
        }
        let laid_out: std::collections::HashSet<&str> = LAYOUTS.iter().map(|(name, ..)| *name).collect();
        assert_eq!(laid_out.len(), LAYOUTS.len(), "a column key is laid out twice");
        assert_eq!(keys.len(), laid_out.len(), "the layout table and the engine columns no longer match");
    }
}
