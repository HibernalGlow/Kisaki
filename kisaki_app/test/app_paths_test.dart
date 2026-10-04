import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/util/app_paths.dart';

/// Each platform has its own convention, and the one thing that must never happen is guessing a
/// directory the user did not give us: a settings file in the wrong place is invisible, not shared.
void main() {
  test('macOS uses the application support folder under the home', () {
    expect(
      AppPaths.settingsDirectory(
        operatingSystem: 'macos',
        home: '/Users/glowski',
      ),
      '/Users/glowski/Library/Application Support/Kisaki',
    );
  });

  test('Linux honours XDG_CONFIG_HOME before falling back to ~/.config', () {
    expect(
      AppPaths.settingsDirectory(
        operatingSystem: 'linux',
        environment: const <String, String>{'XDG_CONFIG_HOME': '/cfg'},
        home: '/home/glowski',
      ),
      '/cfg/Kisaki',
    );
    expect(
      AppPaths.settingsDirectory(
        operatingSystem: 'linux',
        home: '/home/glowski',
      ),
      '/home/glowski/.config/Kisaki',
    );
  });

  test('Windows uses APPDATA and only reaches for USERPROFILE without it', () {
    expect(
      AppPaths.settingsDirectory(
        operatingSystem: 'windows',
        environment: const <String, String>{'APPDATA': r'C:\Users\g\AppData\Roaming'},
      ),
      r'C:\Users\g\AppData\Roaming/Kisaki',
    );
    expect(
      AppPaths.settingsDirectory(
        operatingSystem: 'windows',
        environment: const <String, String>{'USERPROFILE': r'C:\Users\g'},
      ),
      r'C:\Users\g/AppData/Roaming/Kisaki',
    );
  });

  test('no home and no environment variable means no persistence, not a guess', () {
    expect(
      AppPaths.settingsDirectory(operatingSystem: 'macos', home: ''),
      isNull,
      reason: 'an empty home would produce a relative path inside the current directory',
    );
    expect(
      AppPaths.settingsDirectory(operatingSystem: 'haiku'),
      isNull,
      reason: 'an unknown platform must not invent a location',
    );
  });
}
