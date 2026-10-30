String _two(int n) => n.toString().padLeft(2, '0');

/// 2024-03-05
String formatDate(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// 2024-03-05 14:30
String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${_two(date.hour)}:${_two(date.minute)}';

/// Reads 2024-03-05, 2024/3/5 or a full ISO timestamp. Null if unreadable.
DateTime? parseDate(String? text) {
  final value = text?.trim();
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// 45m, 2h or 2h 5m.
String formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
