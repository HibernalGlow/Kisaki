import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/activity_log.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/file_host.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// Open and reveal leave the board entirely, so the two things worth proving are that the menu only
/// offers what the host can actually do, and that a host failure is reported with the row it failed on.
void main() {
  late StubEngine engine;

  ScanRow one() =>
      StubEngine.row('/data/one.jpg', size: 100, group: 0, start: true);

  FileHost hostThatOpens({
    List<String>? opened,
    List<String>? revealed,
    FileHostException? failure,
  }) => FileHost(
    open: (String path) async {
      if (failure != null) {
        throw failure;
      }
      opened?.add(path);
    },
    reveal: (String path) async {
      if (failure != null) {
        throw failure;
      }
      revealed?.add(path);
    },
  );

  group('what the host can do', () {
    test('a host that cannot do either leaves both out', () async {
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: FileHost.unsupported,
      )..addIncluded(<String>['/data']);

      expect(controller.canOpenFiles, isFalse);
      expect(controller.canRevealFiles, isFalse);

      final String before = controller.statusText;
      await controller.openPath('/data/one.jpg');
      await controller.revealPath('/data/one.jpg');

      expect(
        controller.statusText,
        before,
        reason: 'a missing capability is not a failure, so nothing is claimed',
      );
    });

    test('a host that opens without revealing is reported that way', () {
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: FileHost(open: (String path) async {}),
      );
      expect(controller.canOpenFiles, isTrue);
      expect(controller.canRevealFiles, isFalse);
    });

    test('a successful action names the path it handed over', () async {
      final List<String> opened = <String>[];
      final List<String> revealed = <String>[];
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: hostThatOpens(opened: opened, revealed: revealed),
      );

      await controller.openPath('/data/one.jpg');
      expect(opened, <String>['/data/one.jpg']);
      expect(controller.statusText, 'Opening /data/one.jpg');

      await controller.revealPath('/data/two.png');
      expect(revealed, <String>['/data/two.png']);
      expect(controller.statusText, 'Revealing /data/two.png');
    });

    test('a failing host is reported with its path and written to the log', () async {
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: hostThatOpens(
          failure: const FileHostException(
            executable: 'open',
            path: '/data/one.jpg',
            message: 'No application knows how to open it',
          ),
        ),
      );

      await controller.openPath('/data/one.jpg');

      expect(
        controller.statusText,
        'Could not open /data/one.jpg: No application knows how to open it',
      );
      expect(
        controller.activityLog.last.level,
        ActivityLevel.error,
        reason: 'the log is where a reader goes back to read the failure',
      );
      expect(controller.activityLog.last.message, contains('/data/one.jpg'));
    });

    test('the desktop build picks itself without launching anything', () {
      final FileHost host = desktopFileHost();
      expect(host.canOpen, isTrue, reason: 'this app only ships for desktop targets');
      if (Platform.isMacOS || Platform.isWindows) {
        expect(host.canReveal, isTrue);
      }
    });
  });

  group('the row menu with and without a host', () {
    Future<void> pumpBoard(WidgetTester tester, FileHost host) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      engine = StubEngine();
      final BoardController controller = BoardController(
        engine: engine,
        fileHost: host,
      );
      controller.addIncluded(<String>['/data']);
      controller.selectTool('duplicate_files');
      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('duplicate_files', <ScanRow>[one()]),
        ),
      );
      await tester.pumpWidget(KisakiBoardApp(controller: controller));
      await tester.pumpAndSettle();
    }

    Future<void> rightClick(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('result-row-/data/one.jpg')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a host that can do both grows the menu by two items', (
      WidgetTester tester,
    ) async {
      final List<String> revealed = <String>[];
      await pumpBoard(tester, hostThatOpens(revealed: revealed));
      await rightClick(tester);

      expect(find.text(Labels.of('row-menu-open')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-reveal')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-copy-path')), findsOneWidget);

      await tester.tap(find.byKey(const Key('row-menu-reveal')));
      await tester.pumpAndSettle();
      expect(revealed, <String>['/data/one.jpg']);
    });

    testWidgets('a host with no file manager route keeps the menu as it was', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester, FileHost.unsupported);
      await rightClick(tester);

      expect(find.text(Labels.of('row-menu-open')), findsNothing);
      expect(find.text(Labels.of('row-menu-reveal')), findsNothing);
      expect(find.text(Labels.of('row-menu-copy-path')), findsOneWidget);
    });
  });
}
