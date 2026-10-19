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
