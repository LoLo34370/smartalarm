/// Topics MQTT du projet (voir docs/mqtt-topics.md).
class MqttTopics {
  const MqttTopics(this.base);

  final String base;

  String get command => '$base/command';
  String get state => '$base/state';
  String get motion => '$base/motion';
  String get availability => '$base/availability';
  String get sensors => '$base/sensors';

  /// Topics écoutés par l'application.
  List<String> get subscriptions => [state, motion, availability, sensors];
}
