use std::cmp::Ordering;
use std::rc::Rc;

use czkawka_core::common::path_utils::split_path_compare;
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};

use crate::common::format_bytes;
use crate::state::{AppStore, RowData};
use crate::{AppState, MainWindow, Metrics, ResultRow};

/// Index of the name column in the sort request, which has no `ColumnDef` of its own.
pub const SORT_BY_NAME: i32 = -2;
pub const SORT_NONE: i32 = -1;

pub fn to_result_row(index: usize, row: &RowData) -> ResultRow {
    let cells: Vec<SharedString> = row.cells.iter().map(|cell| cell.as_str().into()).collect();
    ResultRow {
        checked: row.checked,
        is_group_start: row.is_group_start,
        group_index: row.group_index,
        group_size: row.group_size,
        is_reference: row.is_reference,
        store_index: index as i32,
        glyph: RowData::glyph_for(row).into(),
        name: row.name.as_str().into(),
        path: row.directory.as_str().into(),
        cells: ModelRc::from(cells.as_slice()),
    }
}

fn matches(row: &RowData, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }
    let mut haystack = row.name.to_lowercase();
    haystack.push(' ');
    haystack.push_str(&row.directory.to_lowercase());
    if row.cells.iter().any(|cell| haystack.contains(needle) || cell.to_lowercase().contains(needle)) {
        return true;
    }
    row.path.to_string_lossy().to_lowercase().contains(needle)
}

/// Rows visible after filtering. A group is shown completely when any member matches.
pub fn filter_rows(rows: &[RowData], filter: &str) -> Vec<usize> {
    let needle = filter.trim().to_lowercase();
    let kept_groups: Vec<i32> = if needle.is_empty() {
        Vec::new()
    } else {
        rows.iter()
            .filter(|row| matches(row, &needle))
            .map(|row| row.group_index)
            .filter(|group| *group >= 0)
            .collect()
    };

    rows.iter()
        .enumerate()
        .filter(|(_, row)| matches(row, &needle) || (row.group_index >= 0 && kept_groups.contains(&row.group_index)))
        .map(|(index, _)| index)
        .collect()
}

fn compare_text(a: &str, b: &str) -> Ordering {
    a.to_lowercase().cmp(&b.to_lowercase())
}

fn compare_rows(rows: &[RowData], a: usize, b: usize, column: i32, ascending: bool) -> Ordering {
    let (left, right) = (&rows[a], &rows[b]);
    let ordering = if column == SORT_BY_NAME {
        split_path_compare(&left.path, &right.path)
    } else {
        let index = usize::try_from(column).unwrap_or(usize::MAX);
        match (left.sort_keys.get(index), right.sort_keys.get(index)) {
            (Some(a_key), Some(b_key)) => a_key.cmp(b_key),
            _ => match (left.cells.get(index), right.cells.get(index)) {
                (Some(a_cell), Some(b_cell)) => compare_text(a_cell, b_cell),
                _ => left.path.cmp(&right.path),
            },
        }
    };
    let ordering = ordering
        .then_with(|| left.mtime.cmp(&right.mtime))
        .then_with(|| split_path_compare(&left.path, &right.path));
    if ascending { ordering } else { ordering.reverse() }
}

pub fn sort_rows(rows: &[RowData], mut indices: Vec<usize>, column: i32, ascending: bool) -> Vec<usize> {
    if column == SORT_NONE || column < SORT_BY_NAME {
        return indices;
    }
    indices.sort_by(|a, b| compare_rows(rows, *a, *b, column, ascending));
    indices
}

/// Flat results are fully reclaimable; grouped ones keep the largest member of each group.
pub fn reclaimable_bytes(rows: &[&RowData], grouped: bool, has_references: bool) -> u64 {
    if has_references {
        return rows.iter().filter(|row| !row.is_reference).map(|row| row.size_bytes).sum();
    }
    if !grouped {
        return rows.iter().map(|row| row.size_bytes).sum();
    }
    let mut per_group: Vec<(i32, u64)> = Vec::new();
    for row in rows {
        match per_group.iter_mut().find(|(group, _)| *group == row.group_index) {
            Some((_, max)) => *max = (*max).max(row.size_bytes),
            None => per_group.push((row.group_index, row.size_bytes)),
        }
    }
    rows.iter()
        .map(|row| row.size_bytes)
        .sum::<u64>()
        .saturating_sub(per_group.iter().map(|(_, max)| *max).sum())
}

pub fn compute_metrics(rows: &[RowData], indices: &[usize], grouped: bool, has_references: bool) -> Metrics {
    let visible: Vec<&RowData> = indices.iter().map(|index| &rows[*index]).collect();

    let files = visible.len();
    let groups = if grouped { visible.iter().filter(|row| row.is_group_start).count() } else { files };
    let total = visible.iter().map(|row| row.size_bytes).sum::<u64>();
    let reclaimable = reclaimable_bytes(&visible, grouped, has_references);
    let checked: Vec<&RowData> = visible.iter().filter(|row| row.checked).copied().collect();
    let selected_size = checked.iter().map(|row| row.size_bytes).sum::<u64>();

    Metrics {
        files: files as i32,
        groups: groups as i32,
        total_size: format_bytes(total).into(),
        reclaimable: format_bytes(reclaimable).into(),
        selected: checked.len() as i32,
        selected_size: format_bytes(selected_size).into(),
        has_results: !visible.is_empty(),
    }
}

fn select_state(rows: &[RowData], indices: &[usize]) -> i32 {
    if indices.is_empty() {
        return 0;
    }
    let checked = indices.iter().filter(|index| rows[**index].checked).count();
    match checked {
        0 => 0,
        count if count == indices.len() => 2,
        _ => 1,
    }
}

pub fn build_model(rows: &[RowData], indices: &[usize]) -> ModelRc<ResultRow> {
    let built: Vec<ResultRow> = indices.iter().map(|index| to_result_row(*index, &rows[*index])).collect();
    Rc::new(VecModel::from(built)).into()
}

/// Recomputes the visible slice, the metrics and the header check state.
pub fn refresh(app: &MainWindow, store: &mut AppStore) {
    let indices = filter_rows(&store.rows, &store.filter);
    let indices = sort_rows(&store.rows, indices, store.sort_column, store.sort_ascending);

    let spec = crate::tools::spec(store.tool);
    let grouped = spec.is_some_and(|tool| tool.grouped);
    let has_references = store.rows.iter().any(|row| row.is_reference);

    let metrics = compute_metrics(&store.rows, &indices, grouped, has_references);
    let state = app.global::<AppState>();
    state.set_results(build_model(&store.rows, &indices));
    state.set_visible_count(metrics.files);
    state.set_select_state(select_state(&store.rows, &indices));
    state.set_metrics(metrics);
    // Row flags are the truth, the path keyed selection is derived from them so deletion
    // and export can never act on a selection that predates the last toggle.
    store.refresh_selection();
    store.visible = indices;
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn row(name: &str, path: &str, size: u64, group: i32, checked: bool) -> RowData {
        let mut data = RowData::new(
            PathBuf::from(path),
            name.to_string(),
            "/dir".to_string(),
            vec![format!("{size}")],
            vec![size as i64],
            size,
            0,
        );
        data.group_index = group;
        data.group_size = if group < 0 { 1 } else { 2 };
        data.is_group_start = group >= 0 && checked;
        data.checked = checked;
        data
    }

    #[test]
    fn empty_filter_keeps_every_row() {
        let rows = vec![row("a", "/x/a", 1, -1, false), row("b", "/x/b", 2, -1, false)];
        assert_eq!(filter_rows(&rows, ""), vec![0, 1]);
    }

    #[test]
    fn filter_matches_case_insensitively_and_expands_a_group() {
        let rows = vec![
            row("Alpha", "/x/alpha", 10, 0, false),
            row("Beta", "/x/beta", 20, 0, false),
            row("Gamma", "/x/gamma", 30, 1, false),
        ];
        let indices = filter_rows(&rows, "alp");
        assert_eq!(indices, vec![0, 1]);
    }

    #[test]
    fn sort_by_numeric_key_honours_direction() {
        let rows = vec![row("a", "/x/a", 30, -1, false), row("b", "/x/b", 10, -1, false), row("c", "/x/c", 20, -1, false)];
        let ascending = sort_rows(&rows, vec![0, 1, 2], 0, true);
        assert_eq!(ascending, vec![1, 2, 0]);
        let descending = sort_rows(&rows, vec![0, 1, 2], 0, false);
        assert_eq!(descending, vec![0, 2, 1]);
    }

    #[test]
    fn reclaimable_keeps_one_member_per_group() {
        let rows = [row("a", "/x/a", 10, 0, false), row("b", "/x/b", 25, 0, false)];
        let refs: Vec<&RowData> = rows.iter().collect();
        assert_eq!(reclaimable_bytes(&refs, true, false), 10);
    }

    #[test]
    fn reclaimable_counts_only_non_referenced_files() {
        let mut first = row("a", "/x/a", 10, 0, false);
        first.is_reference = true;
        let second = row("b", "/x/b", 25, 0, false);
        let refs: Vec<&RowData> = vec![&first, &second];
        assert_eq!(reclaimable_bytes(&refs, true, true), 25);
    }

    #[test]
    fn flat_results_are_fully_reclaimable() {
        let rows = [row("a", "/x/a", 10, -1, false), row("b", "/x/b", 25, -1, false)];
        let refs: Vec<&RowData> = rows.iter().collect();
        assert_eq!(reclaimable_bytes(&refs, false, false), 35);
    }

    #[test]
    fn metrics_report_selected_count_and_size() {
        let rows = vec![row("a", "/x/a", 10, 0, true), row("b", "/x/b", 20, 0, false)];
        let metrics = compute_metrics(&rows, &[0, 1], true, false);
        assert_eq!(metrics.files, 2);
        assert_eq!(metrics.groups, 1);
        assert_eq!(metrics.selected, 1);
        assert!(metrics.has_results);
        // selected_size covers only checked rows, so it follows the selection (the 10 B
        // row is checked here), not the group total.
        assert_eq!(metrics.selected_size.as_str(), "10 B");
        assert_eq!(metrics.total_size.as_str(), "30 B");
        // Grouped without references keeps the largest copy: 30 - 20.
        assert_eq!(metrics.reclaimable.as_str(), "10 B");
    }

    #[test]
    fn select_state_is_tri_state() {
        let rows = vec![row("a", "/x/a", 1, 0, true), row("b", "/x/b", 2, 0, false)];
        assert_eq!(select_state(&rows, &[0, 1]), 1);
        assert_eq!(select_state(&rows, &[0]), 2);
        assert_eq!(select_state(&rows, &[1]), 0);
        assert_eq!(select_state(&rows, &[]), 0);
    }
}
