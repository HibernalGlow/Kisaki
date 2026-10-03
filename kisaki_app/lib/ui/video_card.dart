import 'package:flutter/material.dart';

import '../engine/models.dart' show OptimizeItem, OptimizeStatus;
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/video_optimize.dart';
import '../theme/board_theme.dart';
import '../util/format.dart';
import 'widgets/primitives.dart';

/// Video optimizer settings and its one verb, from `czkawka/views/CzkawkaCardsView.tsx`.
///
/// The reference builds a candidate preview client-side from the scan's own entries; Kisaki asks the
/// engine, which re-derives the candidates and answers with the reason a file was left out, so the
/// card shows the selection before the run and the engine's verdict after it.
class VideoCard extends StatelessWidget {
  const VideoCard({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final VideoOptions video = controller.video;
    final bool crop = video.mode == VideoOptimizeMode.crop;
    final int selected = controller.selectedCount;
    final List<OptimizeItem> items =
        controller.videoOutcome?.items ?? const <OptimizeItem>[];

    return SectionCard(
      title: Labels.of('video-card-title'),
      children: <Widget>[
        Text(Labels.of('video-card-hint'), style: palette.text.bodySmall),
        const SizedBox(height: BoardTokens.gap),
        BoardDropdown<VideoOptimizeMode>(
          key: const Key('video-mode'),
          labelKey: 'video-mode-label',
          values: VideoOptimizeMode.values,
          current: video.mode,
          label: (VideoOptimizeMode value) => Labels.of(
            value == VideoOptimizeMode.crop
                ? 'video-mode-crop'
                : 'video-mode-transcode',
          ),
          onChanged: (VideoOptimizeMode value) => controller.updateVideo(
            (VideoOptions o) => o.copyWith(mode: value),
          ),
        ),
        const SizedBox(height: BoardTokens.gap),
        if (crop) ...<Widget>[
          _SwitchRow(
            keyName: 'video-crop-transcode',
            labelKey: 'video-crop-transcode-label',
            value: video.cropTranscode,
            onChanged: (bool value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(cropTranscode: value),
            ),
          ),
          if (video.cropTranscode) ...<Widget>[
            const SizedBox(height: BoardTokens.gap),
            _CodecDropdown(
              keyName: 'video-crop-codec',
              labelKey: 'video-crop-codec-label',
              current: video.cropCodec,
              onChanged: (VideoCodec value) => controller.updateVideo(
                (VideoOptions o) => o.copyWith(cropCodec: value),
              ),
            ),
            const SizedBox(height: BoardTokens.gap),
            _NumberField(
              keyName: 'video-crop-quality',
              labelKey: 'video-crop-quality-label',
              value: video.cropQuality,
              onChanged: (int value) => controller.updateVideo(
                (VideoOptions o) => o.copyWith(cropQuality: value),
              ),
            ),
          ],
        ] else ...<Widget>[
          _CodecDropdown(
            keyName: 'video-codec',
            labelKey: 'video-codec-label',
            current: video.codec,
            onChanged: (VideoCodec value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(codec: value),
            ),
          ),
          const SizedBox(height: BoardTokens.gap),
          _NumberField(
            keyName: 'video-quality',
            labelKey: 'video-quality-label',
            value: video.quality,
            onChanged: (int value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(quality: value),
            ),
          ),
          const SizedBox(height: BoardTokens.gap),
          BoardDropdown<VideoHardware>(
            key: const Key('video-hardware'),
            labelKey: 'video-hardware-label',
            values: VideoHardware.values,
            current: video.hardware,
            label: (VideoHardware value) =>
                Labels.of('video-hardware-${value.wire}'),
            onChanged: (VideoHardware value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(hardware: value),
            ),
          ),
          const SizedBox(height: BoardTokens.gap),
          BoardDropdown<VideoNoise>(
            key: const Key('video-noise'),
            labelKey: 'video-noise-label',
            values: VideoNoise.values,
            current: video.noise,
            label: (VideoNoise value) => Labels.of('video-noise-${value.wire}'),
            onChanged: (VideoNoise value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(noise: value),
            ),
          ),
          if (video.noise == VideoNoise.hqdn3d) ...<Widget>[
            const SizedBox(height: BoardTokens.gap),
            _NumberField(
              keyName: 'video-noise-strength',
              labelKey: 'video-noise-strength-label',
              value: video.noiseStrength,
              onChanged: (int value) => controller.updateVideo(
                (VideoOptions o) => o.copyWith(noiseStrength: value),
              ),
            ),
          ],
          const SizedBox(height: BoardTokens.gapSmall),
          _SwitchRow(
            keyName: 'video-limit-size',
            labelKey: 'video-limit-size-label',
            value: video.limitVideoSize,
            onChanged: (bool value) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(limitVideoSize: value),
            ),
          ),
          if (video.limitVideoSize) ...<Widget>[
            const SizedBox(height: BoardTokens.gap),
            _NumberField(
              keyName: 'video-max-width',
              labelKey: 'video-max-width-label',
              value: video.maxWidth,
              onChanged: (int value) => controller.updateVideo(
                (VideoOptions o) => o.copyWith(maxWidth: value),
              ),
            ),
            const SizedBox(height: BoardTokens.gap),
            _NumberField(
              keyName: 'video-max-height',
              labelKey: 'video-max-height-label',
              value: video.maxHeight,
              onChanged: (int value) => controller.updateVideo(
                (VideoOptions o) => o.copyWith(maxHeight: value),
              ),
            ),
          ],
          const SizedBox(height: BoardTokens.gap),
          BoardField(
            key: const Key('video-command'),
            labelKey: 'video-command-label',
            value: video.customCommand,
            onChanged: (String text) => controller.updateVideo(
              (VideoOptions o) => o.copyWith(customCommand: text),
            ),
          ),
        ],
        const SizedBox(height: BoardTokens.gapSmall),
        _SwitchRow(
          keyName: 'video-fail-smaller',
          labelKey: 'video-fail-smaller-label',
          value: video.failIfNotSmaller,
          onChanged: (bool value) => controller.updateVideo(
            (VideoOptions o) => o.copyWith(failIfNotSmaller: value),
          ),
        ),
        _SwitchRow(
          keyName: 'video-overwrite',
          labelKey: 'video-overwrite-label',
          value: video.overwriteOriginal,
          onChanged: (bool value) => controller.updateVideo(
            (VideoOptions o) => o.copyWith(overwriteOriginal: value),
          ),
        ),
        const SizedBox(height: BoardTokens.gap),
        Row(
          children: <Widget>[
            Expanded(
              child: BoardAction(
                key: const Key('video-optimize'),
                labelKey: 'video-action-optimize',
                icon: Icons.movie_filter_outlined,
                tone: selected == 0 ? null : palette.primary,
                onPressed: selected == 0 || controller.actionRunning
                    ? null
                    : controller.requestOptimizeVideos,
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            Text(
              '$selected',
              key: const Key('video-selected-count'),
              style: palette.tableFigure(color: palette.fgMuted),
            ),
          ],
        ),
        if (items.isNotEmpty) ...<Widget>[
          const SizedBox(height: BoardTokens.gap),
          for (final OptimizeItem item in items.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.text.bodySmall,
                  ),
                  Text(
                    _outcomeText(item),
                    style: palette.text.bodySmall?.copyWith(
                      color: item.status == OptimizeStatus.failed
                          ? palette.danger
                          : palette.fgFaint,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _outcomeText(OptimizeItem item) {
    final String state = switch (item.status) {
      OptimizeStatus.transcoded => 'video-result-transcoded',
      OptimizeStatus.cropped => 'video-result-cropped',
      OptimizeStatus.planned => 'video-result-planned',
      OptimizeStatus.skipped => 'video-result-skipped',
      OptimizeStatus.failed => 'video-result-failed',
    };
    final String sizes = item.sizeBefore > 0 && item.sizeAfter > 0
        ? ' ${humanBytes(item.sizeBefore)} -> ${humanBytes(item.sizeAfter)}'
        : '';
    final String detail = item.detail.isEmpty ? '' : ' ${item.detail}';
    return '${Labels.of(state)}$sizes$detail';
  }
}

class _CodecDropdown extends StatelessWidget {
  const _CodecDropdown({
    required this.keyName,
    required this.labelKey,
    required this.current,
    required this.onChanged,
  });

  final String keyName;
  final String labelKey;
  final VideoCodec current;
  final ValueChanged<VideoCodec> onChanged;

  @override
  Widget build(BuildContext context) {
    return BoardDropdown<VideoCodec>(
      key: Key(keyName),
      labelKey: labelKey,
      values: VideoCodec.values,
      current: current,
      label: (VideoCodec value) => value.displayName,
      onChanged: onChanged,
    );
  }
}

/// A numeric setting that keeps the last valid value, so typing cannot send the engine a blank.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.keyName,
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String keyName;
  final String labelKey;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _editor = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _editor.text != '${widget.value}') {
      _editor.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of(widget.labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        TextField(
          key: Key(widget.keyName),
          controller: _editor,
          keyboardType: TextInputType.number,
          style: palette.tableFigure(),
          onChanged: (String text) {
            final int? parsed = int.tryParse(text.trim());
            if (parsed != null) {
              widget.onChanged(parsed);
            }
          },
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.keyName,
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String keyName;
  final String labelKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ToggleRow(
      key: Key(keyName),
      labelKey: labelKey,
      value: value,
      onChanged: onChanged,
    );
  }
}
