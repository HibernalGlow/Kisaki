import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../theme/board_theme.dart';
import '../util/format.dart';
import 'widgets/primitives.dart';

/// Pixels for the comparison dialog: the decode seam, the frame cache, the painter that places a
/// picture without distortion, and the two ways a pane shows an image or its absence.

/// Where an image of [imageSize] lands inside [canvas] when scaled without distortion. Every stage
/// uses it, so a swipe split and an overlay cannot disagree about the picture's geometry.
Rect imageDestRect(Size canvas, Size imageSize, BoxFit fit) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      canvas.width <= 0 ||
      canvas.height <= 0) {
    return Rect.zero;
  }
  final double contain =
      (canvas.width / imageSize.width < canvas.height / imageSize.height)
      ? canvas.width / imageSize.width
      : canvas.height / imageSize.height;
  final double cover =
      (canvas.width / imageSize.width > canvas.height / imageSize.height)
      ? canvas.width / imageSize.width
      : canvas.height / imageSize.height;
  final double scale = fit == BoxFit.cover ? cover : contain;
  final Size scaled = Size(imageSize.width * scale, imageSize.height * scale);
  return Rect.fromLTWH(
    (canvas.width - scaled.width) / 2,
    (canvas.height - scaled.height) / 2,
    scaled.width,
    scaled.height,
  );
}

/// One image painted into a stage, clipped to a left fraction and optionally difference-blended, so
/// the swipe and onion modes share the exact geometry the other layer already used.
class ComparisonLayer extends StatelessWidget {
  const ComparisonLayer({
    required this.path,
    required this.fraction,
    required this.colorCoding,
    this.opacity = 1,
    super.key,
  });

  final String path;
  final double fraction;
  final bool colorCoding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    comparisonImageCache.load(path);
    return ClipRect(
      child: CustomPaint(
        painter: ComparisonImagePainter(
          path: path,
          fraction: fraction,
          colorCoding: colorCoding,
          opacity: opacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class ComparisonImagePainter extends CustomPainter {
  const ComparisonImagePainter({
    required this.path,
    required this.fraction,
    required this.colorCoding,
    required this.opacity,
    this.fit = BoxFit.contain,
  });

  final String path;
  final double fraction;
  final bool colorCoding;
  final double opacity;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = comparisonImageCache.get(path);
    if (image == null || size.width <= 0 || size.height <= 0) {
      return;
    }
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fraction, size.height));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageDestRect(
        size,
        Size(image.width.toDouble(), image.height.toDouble()),
        fit,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..blendMode = colorCoding ? BlendMode.difference : BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(ComparisonImagePainter old) =>
      old.path != path ||
      old.fraction != fraction ||
      old.colorCoding != colorCoding ||
      old.opacity != opacity ||
      old.fit != fit;
}

/// Where the dialog gets its pixels. A widget test replaces this with a loader that answers at
/// once, because a real file decode never resumes on the clock a widget test runs on.
ImageLoader comparisonImageLoader = loadFileImage;

typedef ImageLoader = Future<ui.Image?> Function(String path);

Future<ui.Image?> loadFileImage(String path) async {
  try {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } catch (error) {
    return null;
  }
}

class ComparisonImageCache {
  /// Decoded frames live only while a comparison is on screen, and the cap keeps a long browsing
  /// session from holding every thumbnail in memory.
  static const int _capacity = 48;

  final Map<String, ui.Image> _images = <String, ui.Image>{};
  final Set<String> _failed = <String>{};
  final Set<String> _pending = <String>{};
  final List<VoidCallback> _listeners = <VoidCallback>[];

  ui.Image? get(String path) => _images[path];

  bool failed(String path) => _failed.contains(path);

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  Future<void> load(String path) async {
    if (_images.containsKey(path) ||
        _pending.contains(path) ||
        _failed.contains(path)) {
      return;
    }
    _pending.add(path);
    final ui.Image? image = await comparisonImageLoader(path);
    _pending.remove(path);
    if (image == null) {
      _failed.add(path);
      _notify();
      return;
    }
    while (_images.length >= _capacity) {
      _images.remove(_images.keys.first)?.dispose();
    }
    _images[path] = image;
    _notify();
  }

  void _notify() {
    for (final VoidCallback listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

final ComparisonImageCache comparisonImageCache = ComparisonImageCache();

/// A single picture in a pane or a thumbnail slot. It owns no controller of its own because the
/// dialog repaints from the cache, not from a per-widget future.
class DiskImage extends StatefulWidget {
  const DiskImage({
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String path;
  final Widget placeholder;
  final BoxFit fit;

  @override
  State<DiskImage> createState() => _DiskImageState();
}

class _DiskImageState extends State<DiskImage> {
  @override
  void initState() {
    super.initState();
    comparisonImageCache.addListener(_onDecoded);
    comparisonImageCache.load(widget.path);
  }

  @override
  void didUpdateWidget(DiskImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      comparisonImageCache.load(widget.path);
    }
  }

  @override
  void dispose() {
    comparisonImageCache.removeListener(_onDecoded);
    super.dispose();
  }

  void _onDecoded() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (comparisonImageCache.get(widget.path) == null) {
      // A decode that has not answered is not a broken file, so it must not claim one.
      return comparisonImageCache.failed(widget.path)
          ? widget.placeholder
          : const ColoredBox(color: Colors.transparent);
    }
    return CustomPaint(
      painter: ComparisonImagePainter(
        path: widget.path,
        fraction: 1,
        colorCoding: false,
        opacity: 1,
        fit: widget.fit,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class MissingImage extends StatelessWidget {
  const MissingImage({required this.path, super.key});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Center(
      child: Text(
        Labels.of('comparison-missing'),
        key: const Key('comparison-missing'),
        style: palette.text.bodySmall,
      ),
    );
  }
}

/// A pane: the label and the size above, the picture in a hairline frame, the path underneath.
class ComparisonImagePane extends StatelessWidget {
  const ComparisonImagePane({
    required this.entry,
    required this.labelKey,
    super.key,
  });

  final ScanRow entry;
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: MicroHeading(Labels.of(labelKey))),
            Text(
              humanBytes(entry.sizeBytes),
              style: palette.tableFigure(color: palette.fgMuted),
            ),
          ],
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: palette.border),
              color: palette.sunken,
            ),
            child: DiskImage(
              key: Key('comparison-pane-$labelKey'),
              path: entry.path,
              placeholder: MissingImage(path: entry.path),
            ),
          ),
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        Text(
          entry.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: palette.text.bodySmall,
        ),
      ],
    );
  }
}
