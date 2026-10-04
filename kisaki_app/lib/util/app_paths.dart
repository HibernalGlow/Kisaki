import 'dart:io';

/// Where the board keeps its own settings, decided the way each platform expects.
///
/// Split out from `dart:io` on purpose: the three rules below are the whole reason a Linux user with
/// `XDG_CONFIG_HOME` set gets a different directory than a macOS user, and that is testable without a
/// platform.
class AppPaths {
  const AppPaths._();

  /// The application support directory for this product, or null when the platform gives us no home
  /// to hang one on. Callers must then run without persistence rather than guess a writable path.
  static String? settingsDirectory({
    Map<String, String> environment = const <String, String>{},
    String? operatingSystem,
    String? home,
  }) {
    final String os = operatingSystem ?? Platform.operatingSystem;
    final String? base = switch (os) {
      'windows' => _firstNonEmpty(<String>[
        environment['APPDATA'] ?? '',
        _windowsFallback(environment['USERPROFILE'], home),
      ]),
      'linux' => _firstNonEmpty(<String>[
        environment['XDG_CONFIG_HOME'] ?? '',
        _under(home, '.config'),
      ]),
      'macos' => _firstNonEmpty(<String>[
        _under(home, 'Library/Application Support'),
      ]),
      _ => null,
    };
    if (base == null || base.isEmpty) {
      return null;
    }
    return _join(base, productName);
  }

  /// One name everywhere the board writes: the product, not the engine it wraps.
  static const String productName = 'Kisaki';

  /// A path under a base that may be absent. Returning the tail alone would quietly create a relative
  /// directory under whatever the process happens to have as its working directory.
  static String _under(String? base, String tail) =>
      (base == null || base.isEmpty) ? '' : _join(base, tail);

  static String _join(String head, String tail) => '$head/$tail';

  static String _windowsFallback(String? userProfile, String? home) {
    final String root = (userProfile?.isNotEmpty ?? false)
        ? userProfile!
        : (home ?? '');
    return root.isEmpty ? '' : _join(root, 'AppData/Roaming');
  }

  static String? _firstNonEmpty(List<String> candidates) {
    for (final String candidate in candidates) {
      if (candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }
}
