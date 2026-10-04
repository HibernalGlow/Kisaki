import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/floating_panel.dart';

/// The float has to stay reachable whatever the reader drags it to, so these tests pin the reference's
/// margins, size band and edge anchoring - each one checked with a value that would break it.
void main() {
  const FloatingViewport viewport = FloatingViewport(width: 1200, height: 800);
  const FloatingRect base = FloatingRect(
    x: 200,
    y: 100,
    width: 380,
    height: 560,
  );

  group('measuring the board', () {
    test(
      'a board that has not been measured falls back to a desktop window',
      () {
        final FloatingViewport fallback = FloatingViewport.of(0, 0);
        expect(fallback.width, 1200);
        expect(fallback.height, 760);
      },
    );

    test(
      'a board too small to hold a panel is floored, not shrunk to nothing',
      () {
        final FloatingViewport floored = FloatingViewport.of(100, 100);
        expect(floored.width, 320);
        expect(floored.height, 240);
      },
    );

    test('a measured board is taken as it is', () {
      final FloatingViewport measured = FloatingViewport.of(1584, 1136);
      expect(measured.width, 1584);
      expect(measured.height, 1136);
    });
  });

  group('the first panel', () {
    test('it opens closed and sits in the top right', () {
      final FloatingPanelState state = createDefaultFloatingPanel(viewport);
      expect(state.open, isFalse);
      expect(state.rect.width, kFloatingDefaultWidth);
      expect(state.rect.height, kFloatingDefaultHeight);
      expect(state.rect.x, 1200 - 380 - 24);
      expect(state.rect.y, 64);
    });

    test('a board smaller than the default gives up its margin instead of overflowing', () {
      final FloatingRect rect = createDefaultFloatingPanel(
        const FloatingViewport(width: 400, height: 300),
      ).rect;
      expect(
        rect.width,
        380,
        reason: '384 fits inside 400 minus the margin, so the default width survives',
      );
      expect(rect.height, 284);
      expect(rect.x, 8, reason: 'the requested x would sit off the left edge');
      expect(rect.y, 8);
    });
  });

  group('clamping', () {
    test('a panel bigger than the band is taken back to the maximum', () {
      final FloatingRect rect = clampFloatingRect(
        const FloatingRect(x: 0, y: 0, width: 5000, height: 5000),
        const FloatingViewport(width: 2000, height: 2000),
      );
      expect(rect.width, kFloatingMaxWidth);
      expect(rect.height, kFloatingMaxHeight);
      expect(rect.x, kFloatingMargin);
      expect(rect.y, kFloatingMargin);
    });

    test(
      'a board shorter than the maximum caps the panel, not the constant',
      () {
        final FloatingRect rect = clampFloatingRect(
          const FloatingRect(x: 0, y: 0, width: 5000, height: 5000),
          viewport,
        );
        expect(rect.width, kFloatingMaxWidth);
        expect(rect.height, 800 - kFloatingMargin * 2);
      },
    );

    test('a panel smaller than the band is grown to the minimum', () {
      final FloatingRect rect = clampFloatingRect(
        const FloatingRect(x: 40, y: 40, width: 100, height: 50),
        viewport,
      );
      expect(rect.width, kFloatingMinWidth);
      expect(rect.height, kFloatingMinHeight);
    });

    test(
      'a panel pushed off the right or bottom is pulled back by the margin',
      () {
        final FloatingRect rect = clampFloatingRect(
          const FloatingRect(x: 5000, y: 5000, width: 380, height: 560),
          viewport,
        );
        expect(rect.x, 1200 - 380 - 8);
        expect(rect.y, 800 - 560 - 8);
      },
    );

    test('a size that is not a number cannot make the panel disappear', () {
      final FloatingRect rect = clampFloatingRect(
        const FloatingRect(
          x: 200,
          y: 100,
          width: double.nan,
          height: double.infinity,
        ),
        viewport,
      );
      expect(rect.width, kFloatingMinWidth);
      expect(rect.height, kFloatingMinHeight);
    });
  });

  group('dragging', () {
    test('a move inside the board lands where the pointer went', () {
      final FloatingRect rect = moveFloatingRect(base, -120, 80, viewport);
      expect(rect.x, 80);
      expect(rect.y, 180);
      expect(rect.width, 380);
    });

    test('a move past the edge sticks there at the margin', () {
      final FloatingRect rect = moveFloatingRect(base, 5000, 0, viewport);
      expect(rect.x, 1200 - 380 - 8);
    });

    test('a stuck panel drags back rather than staying glued', () {
      final FloatingRect stuck = moveFloatingRect(base, 5000, 0, viewport);
      expect(moveFloatingRect(stuck, -200, 0, viewport).x, stuck.x - 200);
    });

    test('a move that is not a number leaves the panel where it was', () {
      final FloatingRect rect = moveFloatingRect(
        base,
        double.infinity,
        double.nan,
        viewport,
      );
      expect(rect.x, kFloatingMargin);
      expect(rect.y, kFloatingMargin);
    });
  });

  group('resizing', () {
    test('the east edge follows the pointer and the origin stays', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.east,
        100,
        0,
        viewport,
      );
      expect(rect.width, 480);
      expect(rect.x, 200);
    });

    test('the south edge grows and the west edge never moves', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.west,
        -40,
        0,
        viewport,
      );
      expect(rect.width, 420);
      expect(rect.x, 160, reason: 'the right edge has to stay at 580');
    });

    test('a west drag under the minimum stops there with the right edge still anchored', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.west,
        200,
        0,
        viewport,
      );
      expect(rect.width, kFloatingMinWidth);
      expect(rect.x + rect.width, base.x + base.width);
    });

    test('a north drag keeps the bottom edge and clamps the height', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.north,
        0,
        100,
        viewport,
      );
      expect(rect.height, 460);
      expect(rect.y, 200);
      expect(rect.y + rect.height, base.y + base.height);
    });

    test('the corners pull both edges', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.southEast,
        30,
        -20,
        viewport,
      );
      expect(rect.width, 410);
      expect(rect.height, 540);
      expect(rect.x, 200);
      expect(rect.y, 100);
    });

    test('a north west corner cannot be dragged past the opposite corner', () {
      final FloatingRect rect = resizeFloatingRect(
        base,
        ResizeEdge.northWest,
        900,
        900,
        viewport,
      );
      expect(rect.width, kFloatingMinWidth);
      expect(rect.height, kFloatingMinHeight);
      expect(rect.x, 200 + 380 - kFloatingMinWidth);
      expect(rect.y, 100 + 560 - kFloatingMinHeight);
    });

    test('the edges are grouped by the side they pull', () {
      expect(ResizeEdge.northWest.dragsNorth, isTrue);
      expect(ResizeEdge.northWest.dragsWest, isTrue);
      expect(ResizeEdge.northWest.dragsEast, isFalse);
      expect(ResizeEdge.south.dragsSouth, isTrue);
      expect(ResizeEdge.south.dragsWest, isFalse);
      expect(ResizeEdge.east.dragsNorth, isFalse);
    });
  });

  group('normalizing', () {
    test('the open flag survives and the rect is brought inside', () {
      final FloatingPanelState state = normalizeFloatingPanel(
        const FloatingPanelState(
          open: true,
          rect: FloatingRect(x: -400, y: -400, width: 4000, height: 4000),
        ),
        viewport,
      );
      expect(state.open, isTrue);
      expect(state.rect.x, kFloatingMargin);
      expect(state.rect.width, kFloatingMaxWidth);
    });
  });
}
