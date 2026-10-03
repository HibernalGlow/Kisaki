/// Display formatting for the numbers the board shows itself.
///
/// Result cells arrive already formatted from the engine; only the metric strip and
/// the plan/confirm text are produced here.
library;

String humanBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value >= 100 ? 0 : 1);
  return '$text ${units[unit]}';
}

String humanCount(int count) => count.toString();

/// Engine timestamps are unix seconds; results stay readable when a scan reports 0.
String humanDate(int epochSeconds) {
  if (epochSeconds <= 0) {
    return '-';
  }
  final DateTime date = DateTime.fromMillisecondsSinceEpoch(
    epochSeconds * 1000,
  );
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

String humanPercent(int percent) => percent < 0 ? '-' : '$percent%';
