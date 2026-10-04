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
import 'package:kisaki_app/ui/row_menu.dart';

import 'support/stub_engine.dart';

/// Open, reveal and copy-file leave the board entirely, so the two things worth proving are that the
/// menu lists them but keeps the ones this host cannot do disabled, and that a host failure is
/// reported with the row it failed on.
void main() {
  late StubEngine engine;

  ScanRow one() =>
      StubEngine.row('/data/one.jpg', size: 100, group: 0, start: true);

  FileHost hostThatOpens({
    List<String>? opened,
    List<String>? revealed,
    List<List<String>>? copiedFiles,
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
    copyFiles: (List<String> paths) async {
      if (failure != null) {
        throw failure;
      }
      copiedFiles?.add(paths);
    },
  );

  group('what the host can do', () {
    test('a host with no capabilities claims nothing happened', () async {
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: FileHost.unsupported,
      )..addIncluded(<String>['/data']);

      expect(controller.canOpenFiles, isFalse);
      expect(controller.canRevealFiles, isFalse);
      expect(controller.canCopyFiles, isFalse);

      final String before = controller.statusText;
      await controller.openPath('/data/one.jpg');
      await controller.revealPath('/data/one.jpg');
      await controller.copyFilesToClipboard(<String>['/data/one.jpg']);

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
      expect(controller.canCopyFiles, isFalse);
    });

    test('a successful action names the path it handed over', () async {
      final List<String> opened = <String>[];
      final List<String> revealed = <String>[];
      final List<List<String>> copiedFiles = <List<String>>[];
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: hostThatOpens(
          opened: opened,
          revealed: revealed,
          copiedFiles: copiedFiles,
        ),
      );

      await controller.openPath('/data/one.jpg');
      expect(opened, <String>['/data/one.jpg']);
      expect(controller.statusText, 'Opening /data/one.jpg');

      await controller.revealPath('/data/two.png');
      expect(revealed, <String>['/data/two.png']);
      expect(controller.statusText, 'Revealing /data/two.png');

      await controller.copyFilesToClipboard(<String>['/data/two.png']);
      expect(copiedFiles, <List<String>>[
        <String>['/data/two.png'],
      ]);
      expect(
        controller.statusText,
        'Copied /data/two.png to the clipboard for pasting.',
      );
    });

    test('a whole selection is handed over as one batch', () async {
      final List<List<String>> copiedFiles = <List<String>>[];
      final BoardController controller = BoardController(
        engine: StubEngine(),
        fileHost: hostThatOpens(copiedFiles: copiedFiles),
      );

      await controller.copyFilesToClipboard(<String>['/a.png', '/b.png']);
      expect(copiedFiles, <List<String>>[
        <String>['/a.png', '/b.png'],
      ]);
      expect(
        controller.statusText,
        'Copied 2 files to the clipboard for pasting.',
        reason: 'the count travels with the batch so the line stays readable',
      );
    });

    test(
      'a failing host is reported with its path and written to the log',
      () async {
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
          'Cannot open /data/one.jpg: No application knows how to open it',
        );
        expect(
          controller.activityLog.last.level,
          ActivityLevel.error,
          reason: 'the log is where a reader goes back to read the failure',
        );
        expect(controller.activityLog.last.message, contains('/data/one.jpg'));

        await controller.copyFilesToClipboard(<String>['/data/one.jpg']);
        expect(
          controller.statusText,
          'Could not copy /data/one.jpg: No application knows how to open it',
        );
      },
    );

    test('the desktop build picks itself without launching anything', () {
      final FileHost host = desktopFileHost();
      expect(
        host.canOpen,
        isTrue,
        reason: 'this app only ships for desktop targets',
      );
      if (Platform.isMacOS || Platform.isWindows) {
        expect(host.canReveal, isTrue);
      }
      expect(
        host.canCopyFiles,
        Platform.isMacOS,
        reason:
            'only the macOS build has a file manager that owns the clipboard',
      );
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

    bool itemEnabled(WidgetTester tester, RowAction action) => tester
        .widget<PopupMenuItem<RowAction>>(
          find.byKey(Key('row-menu-${action.name}')),
        )
        .enabled;

    testWidgets('a host that answers lights up all three actions', (
      WidgetTester tester,
    ) async {
      final List<String> revealed = <String>[];
      final List<List<String>> copiedFiles = <List<String>>[];
      await pumpBoard(
        tester,
        hostThatOpens(revealed: revealed, copiedFiles: copiedFiles),
      );
      await rightClick(tester);

      expect(find.text(Labels.of('row-menu-open')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-reveal')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-copy-files')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-copy-path')), findsOneWidget);
      expect(itemEnabled(tester, RowAction.open), isTrue);
      expect(itemEnabled(tester, RowAction.reveal), isTrue);
      expect(itemEnabled(tester, RowAction.copyFiles), isTrue);

      await tester.tap(find.byKey(const Key('row-menu-reveal')));
      await tester.pumpAndSettle();
      expect(revealed, <String>['/data/one.jpg']);

      await rightClick(tester);
      await tester.tap(find.byKey(const Key('row-menu-copyFiles')));
      await tester.pumpAndSettle();
      expect(copiedFiles, <List<String>>[
        <String>['/data/one.jpg'],
      ], reason: 'the reference copies the row under the pointer, one path');
    });

    testWidgets('a host with nothing to offer still lists every action', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester, FileHost.unsupported);
      await rightClick(tester);

      expect(find.text(Labels.of('row-menu-open')), findsOneWidget);
      expect(find.text(Labels.of('row-menu-reveal')), findsOneWidget);
      expect(
        find.text(Labels.of('row-menu-copy-files')),
        findsOneWidget,
        reason: 'the reader learns the action exists and is unavailable',
      );
      expect(find.text(Labels.of('row-menu-copy-path')), findsOneWidget);
      expect(itemEnabled(tester, RowAction.open), isFalse);
      expect(itemEnabled(tester, RowAction.reveal), isFalse);
      expect(itemEnabled(tester, RowAction.copyFiles), isFalse);

      final PopupMenuItem<RowAction> deadItem = tester.widget(
        find.byKey(const Key('row-menu-copyFiles')),
      );
      expect(
        find.descendant(
          of: find.byWidget(deadItem),
          matching: find.byType(Tooltip),
        ),
        findsOneWidget,
        reason: 'a disabled item says why, the way the reference tooltip does',
      );
    });
  });
}
