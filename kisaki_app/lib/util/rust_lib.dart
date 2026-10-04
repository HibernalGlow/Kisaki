import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../engine/frb_engine.dart';
import '../engine/kisaki_engine.dart';
import '../src/rust/frb_generated.dart';

/// Loads `libkisaki_bridge` and returns the engine the board runs on.
///
/// Desktop has no native-assets wiring yet, so the library is located by candidate path instead
/// of being injected by the toolchain. `KISAKI_RUST_LIB` overrides it for packaged runs.
class KisakiRustLib {
  const KisakiRustLib._();

  static Future<KisakiEngine> init() async {
    await RustLib.init(externalLibrary: _open());
    return const FrbEngine();
  }

  static ExternalLibrary _open() {
    final found = _candidates()
        .where((path) => File(path).existsSync())
        .toList();
    if (found.isEmpty) {
      throw StateError(
        'Kisaki could not find the Rust library. Build it with `cargo build -p kisaki_bridge` '
        'and rerun, or set KISAKI_RUST_LIB.\nSearched:\n  ${_candidates().join('\n  ')}',
      );
    }
    // Two `target/` directories can hold copies with different codegen hashes, so the newest
    // file wins rather than the first path that happens to exist.
    found.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    return ExternalLibrary.open(found.first);
  }

  /// The runner's own directory comes first: a packaged build must never fall back to a stale
  /// `target/` artifact with a different ABI.
  static List<String> _candidates() {
    final override = Platform.environment['KISAKI_RUST_LIB'];
    if (override != null && override.isNotEmpty) return [override];

    final name = switch (Platform.operatingSystem) {
      'macos' => 'libkisaki_bridge.dylib',
      'linux' => 'libkisaki_bridge.so',
      'windows' => 'kisaki_bridge.dll',
      _ => throw StateError(
        'Unsupported platform: ${Platform.operatingSystem}',
      ),
    };
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    return [
      '$executableDirectory/$name',
      // A packaged .app carries the bridge in Contents/Frameworks, copied there by the
      // packaging script; dev runs fall through to the cargo target dirs below.
      '$executableDirectory/../Frameworks/$name',
      // The bridge is a Cargo workspace member, so the shared target dir is the repo root's.
      '../target/debug/$name',
      '../target/release/$name',
      'rust/target/debug/$name',
      'rust/target/release/$name',
    ];
  }
}
