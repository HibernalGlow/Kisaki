use crate::state::{AppStore, RowData};

/// Bulk selection, so a user never has to click every row before deleting.
///
/// The header checkbox already covers select-all and clear (`AppStore::toggle_visible`), so only
/// the rules it cannot express live here. The modes mirror the reference frontend: `Invert` and
/// `InvertInGroup` act on the rows the table shows, while `Pick` and `Spare` walk each result group
/// and pick or keep exactly one member by a measured property. Like the reference, the group rules
/// replace the whole selection instead of adding to it.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Mode {
    Invert,
    InvertInGroup,
    Pick(Criterion, Extreme),
    Spare(Criterion, Extreme),
}

/// A number every row already carries, so no rule needs to know a column position.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Criterion {
    Size,
    Date,
    PathLength,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Extreme {
    Largest,
    Smallest,
}

/// Contiguous runs sharing one `group_index`, as positions in `visible`. Rows without a group
/// (`-1`, the flat tools) are not part of any run.
fn groups(rows: &[RowData], visible: &[usize]) -> Vec<(usize, usize)> {
    let mut runs = Vec::new();
    let mut start: Option<usize> = None;
    let mut current = -1;
    for (position, index) in visible.iter().enumerate() {
        let group = rows.get(*index).map_or(-1, |row| row.group_index);
        if group < 0 {
            if let Some(open) = start.take() {
                runs.push((open, position));
            }
            continue;
        }
        match start {
            Some(open) if group != current => {
                runs.push((open, position));
                start = Some(position);
            }
            Some(_) => {}
            None => start = Some(position),
        }
        current = group;
    }
    if let Some(open) = start {
        runs.push((open, visible.len()));
    }
    runs
}

fn measure(row: &RowData, criterion: Criterion) -> u64 {
    match criterion {
        Criterion::Size => row.size_bytes,
        Criterion::Date => row.mtime,
        // Directory length dominates, the file name only breaks a tie - the same packing the
        // reference uses for its shortest/longest path rules.
        Criterion::PathLength => ((row.directory.len() as u64) << 32) | row.name.len() as u64,
    }
}

/// The one row in `range` that is the given extreme. Ties keep the first row, so the rule is
/// repeatable: running it twice cannot select a different file.
fn extreme_row(rows: &[RowData], visible: &[usize], range: (usize, usize), criterion: Criterion, extreme: Extreme) -> usize {
    let mut best = range.0;
    let mut best_value = measure(&rows[visible[range.0]], criterion);
    for position in range.0 + 1..range.1 {
        let value = measure(&rows[visible[position]], criterion);
        let better = match extreme {
            Extreme::Largest => value > best_value,
            Extreme::Smallest => value < best_value,
        };
        if better {
            best = position;
            best_value = value;
        }
    }
    best
}

/// Marks rows according to `mode`, touching only the visible ones. Returns the number of rows that
/// changed, which is what the status line reports.
pub fn apply(rows: &mut [RowData], visible: &[usize], mode: Mode) -> usize {
    if visible.is_empty() {
        return 0;
    }
    let mut changed = 0;
    match mode {
        Mode::Invert => {
            for position in visible {
                let row = &mut rows[*position];
                row.checked = !row.checked;
                changed += 1;
            }
        }
        Mode::InvertInGroup => {
            // A group with nothing selected stays untouched, so the rule cannot silently fill a
            // group the user never opened.
            for (start, end) in groups(rows, visible) {
                if !(start..end).any(|position| rows[visible[position]].checked) {
                    continue;
                }
                for position in start..end {
                    let row = &mut rows[visible[position]];
                    row.checked = !row.checked;
                    changed += 1;
                }
            }
        }
        Mode::Pick(criterion, extreme) | Mode::Spare(criterion, extreme) => {
            for index in visible {
                rows[*index].checked = false;
            }
            for (start, end) in groups(rows, visible) {
                let chosen = extreme_row(rows, visible, (start, end), criterion, extreme);
                for position in start..end {
                    let selected = match mode {
                        Mode::Pick(..) => position == chosen,
                        _ => position != chosen,
                    };
                    rows[visible[position]].checked = selected;
                    if selected {
                        changed += 1;
                    }
                }
            }
        }
    }
    changed
}

/// Applies the mode to the store and reports whether anything moved, so the caller can refresh and
/// say so.
pub fn run(store: &mut AppStore, mode: Mode) -> usize {
    let visible = store.visible.clone();
    apply(&mut store.rows, &visible, mode)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn row(name: &str, directory: &str, size_bytes: u64, mtime: u64, group: i32, checked: bool) -> RowData {
        RowData {
            path: PathBuf::from(directory).join(name),
            name: name.to_string(),
            directory: directory.to_string(),
            cells: Vec::new(),
            sort_keys: Vec::new(),
            size_bytes,
            mtime,
            group_index: group,
            group_size: 2,
            is_group_start: true,
            is_reference: false,
            checked,
        }
    }

    fn two_groups() -> Vec<RowData> {
        vec![
            row("a.jpg", "/one", 100, 10, 0, false),
            row("bb.jpg", "/one", 300, 30, 0, false),
            row("c.jpg", "/one", 200, 20, 0, false),
            row("d.jpg", "/two", 900, 5, 1, false),
            row("e.jpg", "/two/a/very/long/place", 50, 50, 1, false),
        ]
    }

    fn flags(rows: &[RowData]) -> Vec<bool> {
        rows.iter().map(|row| row.checked).collect()
    }

    #[test]
    fn invert_flips_exactly_the_visible_rows() {
        let mut rows = two_groups();
        rows[1].checked = true;
        rows[4].checked = true;
        // The tail of group 1 is filtered out of the view: it must keep its state.
        let visible = vec![0usize, 1, 2];

        assert_eq!(apply(&mut rows, &visible, Mode::Invert), 3);
        assert_eq!(flags(&rows), vec![true, false, false, false, true], "only the three shown rows flip");

        assert_eq!(apply(&mut rows, &[], Mode::Invert), 0, "nothing visible means nothing to flip");
    }

    #[test]
    fn picking_the_largest_by_size_selects_one_per_group_and_clears_the_rest() {
        let mut rows = two_groups();
        rows[0].checked = true;

        apply(&mut rows, &[0, 1, 2, 3, 4], Mode::Pick(Criterion::Size, Extreme::Largest));

        assert_eq!(flags(&rows), vec![false, false, false, true, false], "300 and 900 are the group maxima");
    }

    #[test]
    fn sparing_the_smallest_by_date_selects_everything_but_the_oldest_member() {
        let mut rows = two_groups();

        apply(&mut rows, &[0, 1, 2, 3, 4], Mode::Spare(Criterion::Date, Extreme::Smallest));

        // Group 0 is oldest at 10, group 1 at 5.
        assert_eq!(flags(&rows), vec![false, true, true, false, true]);
    }

    #[test]
    fn path_length_puts_the_directory_before_the_name() {
        let mut rows = vec![row("same.jpg", "/short", 1, 1, 0, false), row("same.jpg", "/longer/dir", 1, 1, 0, false)];

        apply(&mut rows, &[0, 1], Mode::Spare(Criterion::PathLength, Extreme::Largest));

        assert_eq!(flags(&rows), vec![true, false], "the deeper directory is the longest path");
    }

    #[test]
    fn ties_keep_the_first_row_so_the_rule_repeats() {
        let mut rows = vec![row("x.jpg", "/one", 7, 7, 0, false), row("y.jpg", "/one", 7, 7, 0, false)];

        apply(&mut rows, &[0, 1], Mode::Pick(Criterion::Size, Extreme::Largest));
        assert_eq!(flags(&rows), vec![true, false]);

        apply(&mut rows, &[0, 1], Mode::Pick(Criterion::Size, Extreme::Largest));
        assert_eq!(flags(&rows), vec![true, false], "a second run must not move the choice");
    }

    #[test]
    fn invert_in_group_only_touches_groups_that_already_have_a_selection() {
        let mut rows = two_groups();
        rows[1].checked = true;

        let changed = apply(&mut rows, &[0, 1, 2, 3, 4], Mode::InvertInGroup);

        assert_eq!(flags(&rows), vec![true, false, true, true, true], "group 0 inverts, the untouched group 1 fills");
        assert_eq!(changed, 4, "one row flips off, four flip on");
    }

    #[test]
    fn flat_results_have_no_groups_for_the_group_rules() {
        let rows = vec![row("a", "/one", 1, 1, -1, false), row("b", "/two", 2, 2, -1, false)];
        assert_eq!(groups(&rows, &[0, 1]), vec![]);

        assert_eq!(groups(&two_groups(), &[0, 1, 2, 3, 4]), vec![(0, 3), (3, 5)]);
    }

    #[test]
    fn a_hidden_group_member_is_never_selected_by_a_group_rule() {
        let mut rows = two_groups();
        // Only the first group and one member of the second are visible.
        apply(&mut rows, &[0, 1, 2, 3], Mode::Pick(Criterion::Size, Extreme::Largest));

        assert_eq!(flags(&rows), vec![false, false, false, true, false]);
        assert!(!rows[4].checked, "row 5 is not in the view, so the rule cannot reach it");
    }

    #[test]
    fn sparing_an_extreme_in_a_one_member_group_selects_nothing() {
        let mut rows = vec![row("only.jpg", "/one", 10, 10, 0, false), row("a.jpg", "/two", 1, 1, 1, false), row("b.jpg", "/two", 2, 2, 1, false)];

        let changed = apply(&mut rows, &[0, 1, 2], Mode::Spare(Criterion::Size, Extreme::Smallest));

        assert_eq!(flags(&rows), vec![false, false, true], "the lone row has no leftover to select");
        assert_eq!(changed, 1);
    }
}
