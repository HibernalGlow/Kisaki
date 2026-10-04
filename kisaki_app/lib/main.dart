import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'engine/kisaki_engine.dart';
import 'engine/seed_engine.dart';
import 'state/board_controller.dart';
import 'ui/board.dart';
import 'theme/board_theme.dart';
import 'util/rust_lib.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();
  runApp(KisakiApp(engine: await _resolveEngine()));
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

class KisakiApp extends StatelessWidget {
  const KisakiApp({required this.engine, super.key});

  final KisakiEngine engine;

  @override
  Widget build(BuildContext context) =>
      KisakiBoardApp(controller: BoardController(engine: engine));
}
