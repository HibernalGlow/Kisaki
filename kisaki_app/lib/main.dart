import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'engine/kisaki_engine.dart';
import 'engine/seed_engine.dart';
import 'state/board_controller.dart';
import 'ui/board.dart';
import 'state/board_settings.dart';
import 'theme/board_theme.dart';
import 'util/app_paths.dart';
import 'util/rust_lib.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();
  final BoardController controller = BoardController(
    engine: await _resolveEngine(),
  );
  final String? directory = AppPaths.settingsDirectory();
  if (directory != null) {
    final BoardSettingsStore store = BoardSettingsStore(directory: directory);
    (await store.read()).applyTo(controller);
    // Write once on the way in: the first run then leaves a real file a reader can open and check,
    // rather than one that only ever appears after a change they may not make in this session.
    await store.write(BoardSettings.capture(controller));
  }
  runApp(KisakiApp(controller: controller, store: directory == null ? null : BoardSettingsStore(directory: directory)));
}

/// One starting geometry on every desktop.
///
/// The board degrades its lanes when the window gets narrow, but that contract is only reachable if
/// the platform cannot shrink the window past it, so the minimum comes from the same tokens the layout
/// uses. The preferred size matches the 1280 x 800 the board was laid out against.
Future<void> _configureWindow() async {
  if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(
    const Size(BoardTokens.minWindowWidth, BoardTokens.minWindowHeight),
  );
  await windowManager.setSize(const Size(1280, 800));
  await windowManager.center();
  await windowManager.setTitle('Kisaki');
}

/// The Rust engine is the only acceptable data source, because the board deletes files. Seeded
/// data exists for UI review and must be asked for explicitly, never silently substituted.
Future<KisakiEngine> _resolveEngine() async {
  if (Platform.environment['KISAKI_SEED'] == '1') {
    debugPrint('Kisaki: KISAKI_SEED=1, running on seeded demo data');
    return SeedEngine();
  }
  return KisakiRustLib.init();
}

/// Hosts the board and writes the arrangement back when the app leaves the foreground.
///
/// Saving on every notification would rewrite the file on each progress tick, so the write happens on
/// the lifecycle points where a reader would expect their layout to be durable.
class KisakiApp extends StatefulWidget {
  const KisakiApp({required this.controller, this.store, super.key});

  final BoardController controller;
  final BoardSettingsStore? store;

  @override
  State<KisakiApp> createState() => _KisakiAppState();
}

class _KisakiAppState extends State<KisakiApp> with WidgetsBindingObserver {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_scheduleSave);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The board notifies per progress tick, so a write is scheduled rather than performed and a burst
  /// of notifications collapses into one file.
  void _scheduleSave() {
    final BoardSettingsStore? store = widget.store;
    if (store == null) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => store.write(BoardSettings.capture(widget.controller)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _debounce?.cancel();
      widget.store?.write(BoardSettings.capture(widget.controller));
    }
  }

  @override
  Widget build(BuildContext context) =>
      KisakiBoardApp(controller: widget.controller);
}
