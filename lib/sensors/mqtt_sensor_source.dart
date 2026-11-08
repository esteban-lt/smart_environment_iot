import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'sensor_source.dart';

/// Fuente REAL: se suscribe al broker MQTT donde publica el ESP32.
///
/// Está escrita pero la demo no la usa (no tengo el ESP32 a la mano). Para
/// usarla basta con cambiar `sensorSource` en `sensor_ingest_service.dart`
/// por `MqttSensorSource(host: '192.168.1.50')`.
class MqttSensorSource implements SensorSource {
  final String host;
  final int port;
  final String topic;

  MqttSensorSource({
    required this.host,
    this.port = 1883,
    this.topic = 'smartenv/+/telemetry',
  });

  @override
  String get name => 'MQTT $host:$port ($topic)';

  @override
  Stream<SensorMessage> readings() async* {
    final client = MqttServerClient(
        host, 'smartenv-app-${DateTime.now().millisecondsSinceEpoch}')
      ..port = port
      ..keepAlivePeriod = 30
      ..autoReconnect = true;

    await client.connect();
    client.subscribe(topic, MqttQos.atLeastOnce);

    try {
      await for (final batch in client.updates!) {
        for (final msg in batch) {
          final publish = msg.payload as MqttPublishMessage;
          final text =
              MqttPublishPayload.bytesToStringAsString(publish.payload.message);
          try {
            yield SensorMessage.fromJson(jsonDecode(text) as Map<String, dynamic>);
          } on FormatException {
            // Mensaje mal formado: se ignora en vez de tumbar el flujo.
          }
        }
      }
    } finally {
      client.disconnect();
    }
  }
}
