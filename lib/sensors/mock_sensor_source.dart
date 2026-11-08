import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'sensor_source.dart';

/// Simulador del ESP32 (la fuente que usa la demo).
///
/// Lee `assets/mocks/esp32_telemetry.json`, que tiene los mensajes con el
/// mismo formato que publica el firmware, y los emite uno por uno con una
/// pequeña pausa, como si fueran llegando del broker MQTT. Cambia `ts` por la
/// hora actual para que se vean como lecturas en vivo.
class MockSensorSource implements SensorSource {
  final String assetPath;
  final Duration interval;

  MockSensorSource({
    this.assetPath = 'assets/mocks/esp32_telemetry.json',
    this.interval = const Duration(milliseconds: 150),
  });

  @override
  String get name => 'Simulador ESP32 (JSON con formato del firmware)';

  @override
  Stream<SensorMessage> readings() async* {
    final raw = jsonDecode(await rootBundle.loadString(assetPath))
        as Map<String, dynamic>;
    for (final m in raw['messages'] as List) {
      await Future.delayed(interval);
      final json = Map<String, dynamic>.from(m as Map)
        ..['ts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      yield SensorMessage.fromJson(json);
    }
  }
}
