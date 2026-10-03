import 'dart:io';

import 'package:flutter/material.dart';

import 'engine/kisaki_engine.dart';
import 'engine/seed_engine.dart';
import 'state/board_controller.dart';
import 'ui/board.dart';
import 'util/rust_lib.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KisakiApp(engine: await _resolveEngine()));
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
  Widget build(BuildContext context) => KisakiBoardApp(controller: BoardController(engine: engine));
}
