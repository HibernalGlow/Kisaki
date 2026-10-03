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

/// The bridge is authoritative; if the dylib is missing the board still opens on seeded data so
/// the UI can be reviewed without a Rust build.
Future<KisakiEngine> _resolveEngine() async {
  try {
    return await KisakiRustLib.init();
  } on Object {
    return SeedEngine();
  }
}

class KisakiApp extends StatelessWidget {
  const KisakiApp({required this.engine, super.key});

  final KisakiEngine engine;

  @override
  Widget build(BuildContext context) => KisakiBoardApp(controller: BoardController(engine: engine));
}
