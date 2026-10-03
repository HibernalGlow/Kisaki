import '../engine/models.dart';

/// The two fixes the video optimizer tool offers; the reference keeps them in one state field.
enum VideoOptimizeMode { transcode, crop }

enum VideoCodec {
  h264('h264', 'H.264'),
  h265('h265', 'H.265 / HEVC'),
  av1('av1', 'AV1'),
  vp9('vp9', 'VP9');

  const VideoCodec(this.wire, this.displayName);

  /// The name the engine's codec table expects.
  final String wire;

  /// Codec names are product names, not translatable sentences, so they paint as written.
  final String displayName;
}

enum VideoHardware {
  none('none'),
  nvenc('nvenc'),
  vaapi('vaapi'),
  qsv('qsv'),
  videotoolbox('videotoolbox'),
  amf('amf');

  const VideoHardware(this.wire);

  final String wire;
}

enum VideoNoise {
  none('none'),
  hqdn3d('hqdn3d');

  const VideoNoise(this.wire);

  final String wire;
}

/// The card's settings, with the reference's defaults and clamps.
class VideoOptions {
  const VideoOptions({
    this.mode = VideoOptimizeMode.transcode,
    this.codec = VideoCodec.h265,
    this.hardware = VideoHardware.none,
    this.quality = 23,
    this.failIfNotSmaller = true,
    this.overwriteOriginal = false,
    this.limitVideoSize = false,
    this.maxWidth = 1920,
    this.maxHeight = 1080,
    this.noise = VideoNoise.none,
    this.noiseStrength = 5,
    this.customCommand = '',
    this.cropTranscode = false,
    this.cropCodec = VideoCodec.h265,
    this.cropQuality = 23,
  });

  final VideoOptimizeMode mode;
  final VideoCodec codec;
  final VideoHardware hardware;
  final int quality;
  final bool failIfNotSmaller;
  final bool overwriteOriginal;
  final bool limitVideoSize;
  final int maxWidth;
  final int maxHeight;
  final VideoNoise noise;
  final int noiseStrength;
  final String customCommand;
  final bool cropTranscode;
  final VideoCodec cropCodec;
  final int cropQuality;

  VideoOptions copyWith({
    VideoOptimizeMode? mode,
    VideoCodec? codec,
    VideoHardware? hardware,
    int? quality,
    bool? failIfNotSmaller,
    bool? overwriteOriginal,
    bool? limitVideoSize,
    int? maxWidth,
    int? maxHeight,
    VideoNoise? noise,
    int? noiseStrength,
    String? customCommand,
    bool? cropTranscode,
    VideoCodec? cropCodec,
    int? cropQuality,
  }) => VideoOptions(
    mode: mode ?? this.mode,
    codec: codec ?? this.codec,
    hardware: hardware ?? this.hardware,
    quality: quality ?? this.quality,
    failIfNotSmaller: failIfNotSmaller ?? this.failIfNotSmaller,
    overwriteOriginal: overwriteOriginal ?? this.overwriteOriginal,
    limitVideoSize: limitVideoSize ?? this.limitVideoSize,
    maxWidth: maxWidth ?? this.maxWidth,
    maxHeight: maxHeight ?? this.maxHeight,
    noise: noise ?? this.noise,
    noiseStrength: noiseStrength ?? this.noiseStrength,
    customCommand: customCommand ?? this.customCommand,
    cropTranscode: cropTranscode ?? this.cropTranscode,
    cropCodec: cropCodec ?? this.cropCodec,
    cropQuality: cropQuality ?? this.cropQuality,
  );

  TranscodeOptions get transcode => TranscodeOptions(
    codec: codec.wire,
    hardwareEncoder: hardware.wire,
    quality: _clamp(quality, 0, 51),
    failIfNotSmaller: failIfNotSmaller,
    overwriteOriginal: overwriteOriginal,
    limitVideoSize: limitVideoSize,
    maxWidth: _clamp(maxWidth, 1, 16384),
    maxHeight: _clamp(maxHeight, 1, 16384),
    noiseReduction: noise.wire,
    noiseReductionStrength: _clamp(noiseStrength, 1, 10),
    customFfmpegCommand: customCommand.trim(),
  );

  /// Cropping keeps the source codec unless the reference's "re-encode while cropping" is on, and a
  /// negative quality leaves the engine's own default in charge.
  CropOptions get crop => CropOptions(
    overwriteOriginal: overwriteOriginal,
    targetCodec: cropTranscode ? cropCodec.wire : '',
    quality: cropTranscode ? _clamp(cropQuality, 0, 51) : -1,
  );
}

int _clamp(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);
