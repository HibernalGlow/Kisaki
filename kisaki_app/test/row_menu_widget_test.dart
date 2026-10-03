import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/row_menu.dart';

import 'support/stub_engine.dart';

/// The row context menu is the mouse route to the group selection and the copy actions, so it has to
/// open on the right button and act on the row under the pointer.
void main() {
  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'duplicate_files',
      glyph: 'D',
      labelKey: 'tool_duplicate_files',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpGroupedBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/a.png', size: 100, group: 0, start: true),
          StubEngine.row('/data/b.png', size: 100, group: 0),
          StubEngine.row('/data/other/x.png', size: 200, group: 1),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, String path) async {
    await tester.tap(
      find.byKey(Key('result-row-$path')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the right button opens the menu and selects the whole group', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await rightClick(tester, '/data/a.png');

    expect(find.text(Labels.of('row-menu-select-group')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-menu-selectGroup')));
    await tester.pumpAndSettle();

    expect(controller.selectedCount, 2);
    expect(
      controller.isSelected(controller.rows.last),
      isFalse,
      reason: 'only the group under the pointer is selected',
    );
  });

  testWidgets('a whole group offers the clear instead of the select', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    controller.setGroupSelected(0, true);
    await tester.pumpAndSettle();
    await rightClick(tester, '/data/b.png');

    final PopupMenuItem<RowAction> selectItem = tester
        .widget<PopupMenuItem<RowAction>>(
          find.byKey(const Key('row-menu-selectGroup')),
        );
    expect(selectItem.enabled, isFalse);
    expect(find.text(Labels.of('row-menu-clear-group')), findsOneWidget);

    await tester.tap(find.byKey(const Key('row-menu-clearGroup')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 0);
  });

  testWidgets(
    'copying the path or the name writes the clipboard and reports it',
    (WidgetTester tester) async {
      final List<String> copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpGroupedBoard(tester);
      await rightClick(tester, '/data/other/x.png');
      await tester.tap(find.byKey(const Key('row-menu-copyPath')));
      await tester.pumpAndSettle();
      expect(copied, <String>['/data/other/x.png']);
      expect(
        find.text(
          Labels.of(
            'status_copied',
            args: const <String, Object>{'path': '/data/other/x.png'},
          ),
        ),
        findsWidgets,
      );

      await rightClick(tester, '/data/other/x.png');
      await tester.tap(find.byKey(const Key('row-menu-copyName')));
      await tester.pumpAndSettle();
      expect(copied, <String>['/data/other/x.png', 'x.png']);
    },
  );

  testWidgets('a flat row keeps the copy entries', (WidgetTester tester) async {
    await pumpGroupedBoard(tester);
    await rightClick(tester, '/data/a.png');
    expect(find.text(Labels.of('row-menu-copy-path')), findsOneWidget);
    expect(find.text(Labels.of('row-menu-copy-name')), findsOneWidget);
  });
}
