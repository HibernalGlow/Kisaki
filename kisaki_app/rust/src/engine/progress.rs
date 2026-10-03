use czkawka_core::common::progress_data::{ProgressData, ToolStage};

use crate::api::types::ProgressUpdate;

/// Turns one engine progress message into the flat form Dart renders.
///
/// `stage_label_key` carries the stage identity, derived mechanically from the `ToolStage` path so
/// a new core stage needs no edit here - `Duplicate(FullHashing)` becomes
/// `stage_duplicate_full_hashing`. The wording is left to the core's own display helper, which is
/// the only place that knows how each stage reads and which counts belong in it.
pub fn humanize(data: &ProgressData) -> ProgressUpdate {
    let display = data.to_display();
    ProgressUpdate {
        stage_label_key: stage_key(&data.stage),
        current: data.entries_checked as i64,
        total: data.entries_to_check as i64,
        // `None` marks an indeterminate stage: there is no total for it to be a share of.
        percent: display.current_progress.unwrap_or(0).clamp(0, 100) as i64,
        detail: display.label,
    }
}

/// `SameMusic(AudioTags, ReadingTags)` becomes `stage_same_music_audio_tags_reading_tags`.
fn stage_key(stage: &ToolStage) -> String {
    let mut key = String::from("stage");
    let mut previous_was_lower = false;
    // The prefix already ends in the separator the first word needs.
    let mut pending_separator = true;

    for character in format!("{stage:?}").chars() {
        if !character.is_ascii_alphanumeric() {
            pending_separator = true;
            previous_was_lower = false;
            continue;
        }
        // A camel hump only starts a new word when the letter before it was lowercase.
        if character.is_ascii_uppercase() && previous_was_lower {
            pending_separator = true;
        }
        if pending_separator {
            key.push('_');
            pending_separator = false;
        }
        key.push(character.to_ascii_lowercase());
        previous_was_lower = character.is_ascii_lowercase();
    }
    key
}

#[cfg(test)]
mod tests {
    use czkawka_core::common::model::CheckingMethod;
    use czkawka_core::common::progress_data::{
        DuplicateStage, SameMusicMode, SameMusicStage, SimilarVideosMode, SimilarVideosStage, VideoOptimizerStage,
    };

    use super::*;

    fn data(stage: ToolStage, entries_checked: usize, entries_to_check: usize) -> ProgressData {
        let mut data = ProgressData::new(stage, entries_to_check, 0);
        data.entries_checked = entries_checked;
        data
    }

    #[test]
    fn stage_keys_are_machine_identifiers() {
        assert_eq!(stage_key(&ToolStage::Duplicate(DuplicateStage::FullHashing)), "stage_duplicate_full_hashing");
        assert_eq!(stage_key(&ToolStage::CollectingFiles(CheckingMethod::Size)), "stage_collecting_files_size");
        assert_eq!(
            stage_key(&ToolStage::SameMusic(SameMusicMode::AudioTags, SameMusicStage::ReadingTags)),
            "stage_same_music_audio_tags_reading_tags"
        );
        assert_eq!(
            stage_key(&ToolStage::SimilarVideos(SimilarVideosMode::VisualHash, SimilarVideosStage::CalculatingHashes)),
            "stage_similar_videos_visual_hash_calculating_hashes"
        );
        assert_eq!(stage_key(&ToolStage::BrokenFilesChecking), "stage_broken_files_checking");
        assert_eq!(
            stage_key(&ToolStage::VideoOptimizer(VideoOptimizerStage::CreatingThumbnails)),
            "stage_video_optimizer_creating_thumbnails"
        );
    }

    #[test]
    fn determinate_stage_reports_counts_and_percent() {
        let update = humanize(&data(ToolStage::Duplicate(DuplicateStage::FullHashing), 50, 100));

        assert_eq!(update.stage_label_key, "stage_duplicate_full_hashing");
        assert_eq!(update.current, 50);
        assert_eq!(update.total, 100);
        assert_eq!(update.percent, 50);
        assert!(update.detail.contains("50/100"), "the core label keeps the live counts: {}", update.detail);
    }

    #[test]
    fn indeterminate_stage_has_no_percent() {
        let update = humanize(&data(ToolStage::CollectingFiles(CheckingMethod::None), 7, 0));

        assert_eq!(update.stage_label_key, "stage_collecting_files_none");
        assert_eq!(update.current, 7);
        assert_eq!(update.total, 0);
        assert_eq!(update.percent, 0);
        assert!(!update.detail.is_empty());
    }
}
