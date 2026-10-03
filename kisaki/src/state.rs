use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use czkawka_core::common::traits::PrintResults;
use czkawka_core::tools::bad_extensions::BadExtensions;
use czkawka_core::tools::bad_names::BadNames;
use czkawka_core::tools::big_file::BigFile;
use czkawka_core::tools::broken_files::BrokenFiles;
use czkawka_core::tools::duplicate::DuplicateFinder;
use czkawka_core::tools::empty_files::EmptyFiles;
use czkawka_core::tools::empty_folder::EmptyFolder;
use czkawka_core::tools::exif_remover::ExifRemover;
use czkawka_core::tools::invalid_symlinks::InvalidSymlinks;
use czkawka_core::tools::same_music::SameMusic;
use czkawka_core::tools::similar_images::SimilarImages;
use czkawka_core::tools::similar_videos::SimilarVideos;
use czkawka_core::tools::temporary::Temporary;
use czkawka_core::tools::video_optimizer::VideoOptimizer;

use crate::ToolId;
use crate::fields::FieldStore;
use crate::settings::KisakiSettings;

pub struct SharedModels {
    pub duplicate_files: Option<DuplicateFinder>,
    pub empty_folders: Option<EmptyFolder>,
    pub big_files: Option<BigFile>,
    pub empty_files: Option<EmptyFiles>,
    pub temporary_files: Option<Temporary>,
    pub similar_images: Option<SimilarImages>,
    pub similar_videos: Option<SimilarVideos>,
    pub same_music: Option<SameMusic>,
    pub invalid_symlinks: Option<InvalidSymlinks>,
    pub broken_files: Option<BrokenFiles>,
    pub bad_extensions: Option<BadExtensions>,
    pub bad_names: Option<BadNames>,
    pub exif_remover: Option<ExifRemover>,
    pub video_optimizer: Option<VideoOptimizer>,
}

impl SharedModels {
    fn new() -> Self {
        Self {
            duplicate_files: None,
            empty_folders: None,
            big_files: None,
            empty_files: None,
            temporary_files: None,
            similar_images: None,
            similar_videos: None,
            same_music: None,
            invalid_symlinks: None,
            broken_files: None,
            bad_extensions: None,
            bad_names: None,
            exif_remover: None,
            video_optimizer: None,
        }
    }

    pub(crate) fn clear_results_for(&mut self, tool: ToolId) {
        match tool {
            ToolId::DuplicateFiles => self.duplicate_files = None,
            ToolId::EmptyFolders => self.empty_folders = None,
            ToolId::BigFiles => self.big_files = None,
            ToolId::EmptyFiles => self.empty_files = None,
            ToolId::TemporaryFiles => self.temporary_files = None,
            ToolId::SimilarImages => self.similar_images = None,
            ToolId::SimilarVideos => self.similar_videos = None,
            ToolId::DuplicateMusic => self.same_music = None,
            ToolId::InvalidSymlinks => self.invalid_symlinks = None,
            ToolId::BrokenFiles => self.broken_files = None,
            ToolId::BadExtensions => self.bad_extensions = None,
            ToolId::BadNames => self.bad_names = None,
            ToolId::ExifRemover => self.exif_remover = None,
            ToolId::VideoOptimizer => self.video_optimizer = None,
        }
    }
}

/// A row in a thread-safe shape: no Slint types, so it can cross thread bounds.
pub struct RowData {
    pub path: PathBuf,
    pub name: String,
    pub directory: String,
    pub cells: Vec<String>,
    pub sort_keys: Vec<i64>,
    pub size_bytes: u64,
    pub mtime: u64,
    pub group_index: i32,
    pub group_size: i32,
    pub is_group_start: bool,
    pub is_reference: bool,
    pub checked: bool,
}

impl RowData {
    pub fn new(path: PathBuf, name: String, directory: String, cells: Vec<String>, sort_keys: Vec<i64>, size_bytes: u64, mtime: u64) -> Self {
        Self {
            path,
            name,
            directory,
            cells,
            sort_keys,
            size_bytes,
            mtime,
            group_index: -1,
            group_size: 1,
            is_group_start: false,
            is_reference: false,
            checked: false,
        }
    }

    /// Printed marker for the name cell. Reference rows get one so their meaning never
    /// relies on the muted colour alone.
    pub fn glyph_for(row: &Self) -> String {
        if row.is_reference { "*".to_string() } else { String::new() }
    }
}

pub(crate) fn save_results(models: &SharedModels, tool: ToolId, folder: &str) -> Result<(), String> {
    let result = match tool {
        ToolId::DuplicateFiles => models.duplicate_files.as_ref().map(|tool| tool.save_all_in_one(folder, "results_duplicate_files")),
        ToolId::EmptyFolders => models.empty_folders.as_ref().map(|tool| tool.save_all_in_one(folder, "results_empty_folders")),
        ToolId::BigFiles => models.big_files.as_ref().map(|tool| tool.save_all_in_one(folder, "results_big_files")),
        ToolId::EmptyFiles => models.empty_files.as_ref().map(|tool| tool.save_all_in_one(folder, "results_empty_files")),
        ToolId::TemporaryFiles => models.temporary_files.as_ref().map(|tool| tool.save_all_in_one(folder, "results_temporary_files")),
        ToolId::SimilarImages => models.similar_images.as_ref().map(|tool| tool.save_all_in_one(folder, "results_similar_images")),
        ToolId::SimilarVideos => models.similar_videos.as_ref().map(|tool| tool.save_all_in_one(folder, "results_similar_videos")),
        ToolId::DuplicateMusic => models.same_music.as_ref().map(|tool| tool.save_all_in_one(folder, "results_same_music")),
        ToolId::InvalidSymlinks => models.invalid_symlinks.as_ref().map(|tool| tool.save_all_in_one(folder, "results_invalid_symlinks")),
        ToolId::BrokenFiles => models.broken_files.as_ref().map(|tool| tool.save_all_in_one(folder, "results_broken_files")),
        ToolId::BadExtensions => models.bad_extensions.as_ref().map(|tool| tool.save_all_in_one(folder, "results_bad_extensions")),
        ToolId::BadNames => models.bad_names.as_ref().map(|tool| tool.save_all_in_one(folder, "results_bad_names")),
        ToolId::ExifRemover => models.exif_remover.as_ref().map(|tool| tool.save_all_in_one(folder, "results_exif_remover")),
        ToolId::VideoOptimizer => models.video_optimizer.as_ref().map(|tool| tool.save_all_in_one(folder, "results_video_optimizer")),
    };
    match result {
        Some(Ok(())) => Ok(()),
        Some(Err(error)) => Err(format!("{folder}: {error}")),
        None => Err("No stored scan result to export".to_string()),
    }
}

pub struct PathEntry {
    pub path: PathBuf,
    pub is_reference: bool,
    pub checked: bool,
}

impl PathEntry {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            is_reference: false,
            checked: false,
        }
    }
}

/// Conditions collected from the UI right before a scan starts.
pub struct Conditions {
    pub included: Vec<PathBuf>,
    pub excluded: Vec<PathBuf>,
    pub reference: Vec<PathBuf>,
    pub recursive: bool,
    pub use_cache: bool,
    pub minimal_bytes: u64,
    pub maximal_bytes: u64,
    pub excluded_items: Vec<String>,
    pub allowed_extensions: Vec<String>,
    pub excluded_extensions: Vec<String>,
    pub dry_run: bool,
    pub move_to_trash: bool,
}

pub struct AppStore {
    pub models: SharedModels,
    pub rows: Vec<RowData>,
    /// Indices into `rows` in the order the table currently shows them, so a row
    /// index coming back from the UI can be mapped to its canonical row.
    pub visible: Vec<usize>,
    pub selection: HashSet<PathBuf>,
    pub included: Vec<PathEntry>,
    pub excluded: Vec<PathEntry>,
    pub fields: FieldStore,
    pub tool: ToolId,
    pub sort_column: i32,
    pub sort_ascending: bool,
    pub filter: String,
}

pub type SharedState = Arc<Mutex<AppStore>>;

impl AppStore {
    pub fn new(fields: FieldStore, settings: &KisakiSettings) -> Self {
        let included = settings
            .included_paths
            .iter()
            .map(|entry| {
                let mut item = PathEntry::new(PathBuf::from(&entry.path));
                item.is_reference = entry.is_reference;
                item
            })
            .collect();
        let excluded = settings.excluded_paths.iter().map(|path| PathEntry::new(PathBuf::from(path))).collect();

        // A persisted index that no longer maps to a tool falls back to duplicates rather than
        // panicking on a stale settings file.
        let tool = match crate::tools::spec_by_index(settings.active_tool) {
            Some(spec) => spec.id,
            None => crate::ToolId::DuplicateFiles,
        };

        Self {
            models: SharedModels::new(),
            rows: Vec::new(),
            visible: Vec::new(),
            selection: HashSet::new(),
            included,
            excluded,
            fields,
            tool,
            sort_column: crate::results::SORT_NONE,
            sort_ascending: true,
            filter: String::new(),
        }
    }

    pub fn new_shared(fields: FieldStore, settings: &KisakiSettings) -> SharedState {
        Arc::new(Mutex::new(Self::new(fields, settings)))
    }

    pub fn clear_rows(&mut self) {
        self.rows.clear();
        self.selection.clear();
    }

    pub fn set_rows(&mut self, rows: Vec<RowData>) {
        self.rows = rows;
        self.refresh_selection();
    }

    pub fn refresh_selection(&mut self) {
        self.selection = self.rows.iter().filter(|row| row.checked).map(|row| row.path.clone()).collect();
    }

    pub fn checked_paths(&self) -> Vec<PathBuf> {
        self.selection.iter().cloned().collect()
    }

    pub fn drop_paths(&mut self, paths: &HashSet<PathBuf>) {
        self.rows.retain(|row| !paths.contains(&row.path));
        self.selection.retain(|path| !paths.contains(path));
    }

    pub fn toggle_row(&mut self, index: usize) {
        if let Some(row) = self.rows.get_mut(index) {
            row.checked = !row.checked;
        }
    }

    pub fn toggle_group(&mut self, index: usize) {
        let Some(group) = self.rows.get(index).map(|row| row.group_index) else {
            return;
        };
        if group < 0 {
            self.toggle_row(index);
            return;
        }
        let target = !self.rows.iter().filter(|row| row.group_index == group).any(|row| !row.checked);
        for row in &mut self.rows {
            if row.group_index == group {
                row.checked = target;
            }
        }
    }

    /// Toggles every row the table currently shows. Rows hidden by the filter keep their state.
    pub fn toggle_visible(&mut self) {
        let all_checked = !self.visible.is_empty() && self.visible.iter().all(|index| self.rows.get(*index).is_some_and(|row| row.checked));
        for index in &self.visible {
            if let Some(row) = self.rows.get_mut(*index) {
                row.checked = !all_checked;
            }
        }
    }

    pub fn reference_paths(&self) -> Vec<PathBuf> {
        self.included.iter().filter(|entry| entry.is_reference).map(|entry| entry.path.clone()).collect()
    }
}
