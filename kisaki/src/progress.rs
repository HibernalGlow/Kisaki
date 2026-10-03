use crossbeam_channel::Receiver;
use czkawka_core::common::progress_data::ProgressData;
use log::warn;
use slint::{ComponentHandle, EventLoopError};

use crate::{AppState, MainWindow};

pub fn connect_progress(app: &MainWindow, receiver: Receiver<ProgressData>) {
    let weak = app.as_weak();
    std::thread::spawn(move || {
        while let Ok(progress) = receiver.recv() {
            let display = progress.to_display();
            let result = weak.upgrade_in_event_loop(move |app| {
                let globals = app.global::<AppState>();
                globals.set_progress_all(display.all_progress);
                globals.set_progress_current(display.current_progress.unwrap_or(-1));
                globals.set_progress_label(display.label.as_str().into());
                globals.set_status_text(display.label.as_str().into());
            });
            if matches!(result, Err(EventLoopError::EventLoopTerminated)) {
                return;
            }
            if result.is_err() {
                warn!("Progress update could not be delivered to the event loop");
            }
        }
    });
}
