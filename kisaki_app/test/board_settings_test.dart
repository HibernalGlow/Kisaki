import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/seed_engine.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/board_settings.dart';
import 'package:kisaki_app/state/card_layout.dart';

/// A reader arranges the board once and expects it back. The failure mode this guards against is the
/// one the Slint frontend shipped with: a file written as `2880.0` read by an integer field, which
/// threw and reset the whole arrangement.
void main() {
  BoardController controllerWithArrangement() {
    final BoardController controller = BoardController(engine: SeedEngine());
    controller.setSourceWidth(340);
    controller.setResultsWidth(500);
    controller.toggleLane('results');
    controller.toggleSoloLane('analysis');
    controller.setCardVisible(CardId.logs, false);
    return controller;
  }

  test('the arrangement survives a JSON round trip', () {
    final BoardSettings saved = BoardSettings.capture(controllerWithArrangement());
    final BoardSettings back = BoardSettings.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(saved.toJson())) as Map,
      ),
    );

    expect(back.dark, saved.dark);
    expect(back.lanes.sourceWidth, 340);
    expect(back.lanes.resultsWidth, 500);
    expect(back.lanes.resultsCollapsed, isTrue);
    expect(back.lanes.soloLane, 'analysis');
    expect(back.lanes.order, saved.lanes.order);
    expect(back.cards[CardId.logs]?.visible, isFalse);
  });

  test('applying a snapshot puts the board back the way it was', () {
    final BoardSettings saved = BoardSettings.capture(controllerWithArrangement());
    final BoardController fresh = BoardController(engine: SeedEngine());
    saved.applyTo(fresh);

    expect(fresh.layout.sourceWidth, 340);
    expect(fresh.layout.resultsCollapsed, isTrue);
    expect(fresh.layout.soloLane, 'analysis');
    expect(fresh.cardLayout.configOf(CardId.logs).visible, isFalse);
  });

  test('one bad value costs that field only, not the whole board', () {
    final BoardSettings back = BoardSettings.fromJson(<String, Object?>{
      'version': BoardSettings.schemaVersion,
      'dark': false,
      'lanes': <String, Object?>{'sourceWidth': 'wide', 'resultsWidth': 500.5},
      'cards': <String, Object?>{
        'logs': <String, Object?>{'visible': false},
        'aCardFromANewerBuild': <String, Object?>{'visible': true},
      },
    });

    expect(back.dark, isFalse);
    expect(
      back.lanes.sourceWidth,
      LaneLayout.sourceDefault,
      reason: 'a string where a width belongs must fall back, not abort the parse',
    );
    expect(back.lanes.resultsWidth, 500.5, reason: 'a double width is a legal width');
    expect(back.cards.containsKey(CardId.logs), isTrue);
    expect(
      back.cards.length,
      1,
      reason: 'a card this build does not have is dropped, not guessed at',
    );
  });

  test('a future schema version starts fresh instead of half-applying', () {
    final BoardSettings back = BoardSettings.fromJson(<String, Object?>{
      'version': BoardSettings.schemaVersion + 1,
      'dark': false,
    });
    expect(back.dark, isTrue);
    expect(back.lanes.sourceWidth, LaneLayout.sourceDefault);
  });

  test('the store writes where the platform pointed and reads it back', () async {
    final Directory temp = await Directory.systemTemp.createTemp('kisaki-settings');
    addTearDown(() => temp.delete(recursive: true));
    const BoardSettingsStore store = BoardSettingsStore(directory: '');

    final BoardSettingsStore bound = BoardSettingsStore(directory: temp.path);
    await bound.write(BoardSettings.capture(controllerWithArrangement()));
    final File file = File('${temp.path}/board.json');
    expect(file.existsSync(), isTrue, reason: 'the file has to be where the reader looks');

    final BoardSettings read = await bound.read();
    expect(read.lanes.sourceWidth, 340);
    expect(store.directory, isEmpty, reason: 'the const default is only a placeholder');
  });

  test('an unreadable file reads as defaults rather than throwing', () async {
    final Directory temp = await Directory.systemTemp.createTemp('kisaki-settings-bad');
    addTearDown(() => temp.delete(recursive: true));
    await File('${temp.path}/board.json').writeAsString('{ not json');

    final BoardSettings read = await BoardSettingsStore(
      directory: temp.path,
    ).read();
    expect(read.lanes.sourceWidth, LaneLayout.sourceDefault);
    expect(read.dark, isTrue);
  });
}
