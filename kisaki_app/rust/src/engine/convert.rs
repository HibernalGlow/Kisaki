use crate::api::types::{ScanOutcome, ScanRow};
use crate::engine::EngineOutcome;

/// Turns engine rows into the FFI outcome, computing the group economics the analysis lane shows.
///
/// Reclaimable mirrors what a default selection would delete: in a plain group the largest member
/// is spared, while a group holding a reference row can lose every ordinary copy.
pub fn outcome(tool: String, engine: EngineOutcome) -> ScanOutcome {
    let rows: Vec<ScanRow> = engine.rows.into_iter().map(ScanRow::from).collect();
    let grouped = engine.grouped;

    let file_count = rows.len() as i32;
    let group_count = if grouped {
        rows.iter().filter(|row| row.is_group_start).count() as i32
    } else {
        file_count
    };
    let total_bytes: i64 = rows.iter().map(|row| row.size_bytes).sum();
    let reclaimable_bytes = reclaimable_bytes(&rows, grouped);

    ScanOutcome {
        tool,
        rows,
        stopped: engine.stopped,
        grouped,
        file_count,
        group_count,
        total_bytes,
        reclaimable_bytes,
        messages: engine.messages,
        critical: engine.critical,
    }
}

fn reclaimable_bytes(rows: &[ScanRow], grouped: bool) -> i64 {
    if !grouped {
        return rows.iter().map(|row| row.size_bytes).sum();
    }

    let mut total = 0_i64;
    for group in rows.iter().filter(|row| row.is_group_start).map(|row| row.group_index) {
        let members: Vec<&ScanRow> = rows.iter().filter(|row| row.group_index == group).collect();
        let has_reference = members.iter().any(|row| row.is_reference);
        if has_reference {
            total += members.iter().filter(|row| !row.is_reference).map(|row| row.size_bytes).sum::<i64>();
        } else {
            let largest = members.iter().map(|row| row.size_bytes).max().unwrap_or(0);
            total += members.iter().map(|row| row.size_bytes).sum::<i64>() - largest;
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(size: i64, group: i32, start: bool, reference: bool) -> ScanRow {
        ScanRow {
            path: format!("/x/{group}-{size}"),
            name: "n".to_string(),
            directory: "/x".to_string(),
            cells: vec![],
            size_bytes: size,
            modified_ts: 0,
            group_index: group,
            group_size: 2,
            is_group_start: start,
            is_reference: reference,
            sort_keys: vec![],
        }
    }

    #[test]
    fn plain_group_spares_its_largest_member() {
        let rows = vec![row(100, 0, true, false), row(300, 0, false, false)];
        assert_eq!(reclaimable_bytes(&rows, true), 100);
    }

    #[test]
    fn reference_group_loses_every_ordinary_copy() {
        let rows = vec![row(500, 0, true, false), row(200, 0, false, false), row(10, 0, false, true)];
        assert_eq!(reclaimable_bytes(&rows, true), 700);
    }

    #[test]
    fn flat_results_count_every_byte() {
        let rows = vec![row(7, -1, true, false), row(3, -1, true, false)];
        assert_eq!(reclaimable_bytes(&rows, false), 10);
    }
}
