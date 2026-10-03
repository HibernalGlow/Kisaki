use i18n_embed::fluent::{FluentLanguageLoader, fluent_language_loader};
use i18n_embed::{DefaultLocalizer, LanguageLoader, Localizer};
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "i18n/"]
struct Localizations;

pub static LANGUAGE_LOADER_KISAKI: std::sync::LazyLock<FluentLanguageLoader> = std::sync::LazyLock::new(|| {
    let loader: FluentLanguageLoader = fluent_language_loader!();

    loader.load_fallback_language(&Localizations).expect("Error while loading fallback language");

    loader
});

#[macro_export]
macro_rules! fli {
    ( $($tt:tt)* ) => {{
        i18n_embed_fl::fl!($crate::localizer_kisaki::LANGUAGE_LOADER_KISAKI, $($tt)*)
    }};
}

// Get the `Localizer` to be used for localizing this application.
pub(crate) fn localizer_kisaki() -> Box<dyn Localizer> {
    Box::from(DefaultLocalizer::new(&*LANGUAGE_LOADER_KISAKI, &Localizations))
}

/// Translates a key that is only known at run time.
///
/// `fli!` expands to a macro that needs a literal, but the tool and column
/// registries are tables of keys, so they resolve through the loaded bundles
/// instead. Returns the key itself when no message matches, which keeps a
/// missing translation visible rather than blank.
pub fn translate_key(key: &str) -> String {
    let resolved = std::sync::Mutex::new(String::new());

    LANGUAGE_LOADER_KISAKI.with_bundles_mut(|bundle| {
        // One shared reborrow: the message and the pattern both borrow the bundle.
        let bundle = &*bundle;
        let mut taken = resolved.lock().expect("Translation lookup mutex poisoned");
        if !taken.is_empty() {
            return;
        }
        let Some(pattern) = bundle.get_message(key).and_then(|message| message.value()) else {
            return;
        };
        let mut errors = Vec::new();
        *taken = bundle.format_pattern(pattern, None, &mut errors).to_string();
    });

    let text = resolved.lock().expect("Translation lookup mutex poisoned").clone();
    if text.is_empty() { key.to_string() } else { text }
}
