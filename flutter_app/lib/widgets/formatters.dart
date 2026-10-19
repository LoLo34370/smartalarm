String _two(int value) => value.toString().padLeft(2, '0');

/// 14:05:09
String formatTime(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

/// Temps écoulé depuis le démarrage de l'ESP32 : « 2 min 05 s », « 42,3 s ».
String formatUptime(int uptimeMs) {
  final totalSeconds = uptimeMs ~/ 1000;
  if (totalSeconds < 60) {
    return '${(uptimeMs / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return hours > 0
      ? '$hours h ${_two(minutes)} min'
      : '$minutes min ${_two(seconds)} s';
}

const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// « Aujourd'hui », « Hier » ou « lundi 19 octobre » (année ajoutée si besoin).
String formatDay(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (isSameDay(day, today)) return 'Aujourd\'hui';
  if (isSameDay(day, today.subtract(const Duration(days: 1)))) return 'Hier';
  final label = '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return day.year == today.year ? label : '$label ${day.year}';
}

/// Heure seule le jour même, sinon « 19/10 14:05 ».
String formatShortDateTime(DateTime time, {DateTime? now}) {
  final hhmm = '${_two(time.hour)}:${_two(time.minute)}';
  return isSameDay(time, now ?? DateTime.now())
      ? formatTime(time)
      : '${_two(time.day)}/${_two(time.month)} $hhmm';
}
