use chrono::{Local, TimeZone, Utc};
use humansize::{BINARY, format_size};

pub const LIST_SEPARATOR: char = ',';

pub fn format_timestamp(timestamp: u64) -> String {
    let dt = Utc.timestamp_opt(timestamp as i64, 0).single().unwrap_or_default().with_timezone(&Local);
    dt.format("%Y-%m-%d %H:%M:%S").to_string()
}

pub fn format_bytes(size: u64) -> String {
    format_size(size, BINARY)
}

/// Splits a length in half so it can be stored in an i64 sort key without losing order.
pub fn to_sort_key(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

pub fn parse_kib_to_bytes(value: &str) -> u64 {
    let parsed: u64 = value.trim().parse().unwrap_or(0);
    parsed.saturating_mul(1024)
}

/// Turns a comma/semicolon/newline separated list into trimmed, non-empty parts.
pub fn split_list(text: &str) -> Vec<String> {
    text.split([LIST_SEPARATOR, ';', '\n'])
        .map(|item| item.trim().trim_matches('"').trim_matches('\'').to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitting_list_removes_separators_and_quotes() {
        let items = split_list(" jpg, png ;\n\"gif\"  , ,txt,");
        assert_eq!(items, vec!["jpg".to_string(), "png".to_string(), "gif".to_string(), "txt".to_string()]);
    }

    #[test]
    fn kib_gets_converted_to_bytes() {
        assert_eq!(parse_kib_to_bytes("2"), 2048);
        assert_eq!(parse_kib_to_bytes(" bad "), 0);
    }

    #[test]
    fn oversized_sizes_still_produce_a_stable_sort_key() {
        assert_eq!(to_sort_key(u64::from(u32::MAX)), 4_294_967_295);
        assert_eq!(to_sort_key(u64::MAX), i64::MAX);
    }

    #[test]
    fn bytes_are_formatted_with_binary_units() {
        assert_eq!(format_bytes(2048), "2 KiB");
    }
}
