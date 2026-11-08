/// Un mensaje de telemetría con el MISMO formato JSON que publica el firmware
/// del ESP32 por MQTT:
/// ```json
/// { "device_id": "ESP32_01", "sensor": "temperature", "value": 36.2,
///   "unit": "C", "ts": 1794100090, "location": "Invernadero A" }
/// ```
class SensorMessage {
  final String deviceId;
  final String sensor;
  final double value;
  final String unit;
  final DateTime ts;
  final String? location;

  SensorMessage({
    required this.deviceId,
    required this.sensor,
    required this.value,
    required this.unit,
    required this.ts,
    this.location,
  });

  factory SensorMessage.fromJson(Map<String, dynamic> json) => SensorMessage(
        deviceId: json['device_id'] as String,
        sensor: json['sensor'] as String,
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String? ?? '',
        ts: DateTime.fromMillisecondsSinceEpoch(
            (json['ts'] as num).toInt() * 1000),
        location: json['location'] as String?,
      );
}

/// Contrato de cualquier fuente de lecturas. La app solo conoce esta interfaz,
/// así que cambiar el simulador por el ESP32 real es cambiar UNA línea
/// (ver `sensorSource` en `sensor_ingest_service.dart`).
abstract class SensorSource {
  /// Nombre para mostrar en la UI.
  String get name;

  /// Flujo de mensajes del hardware.
  Stream<SensorMessage> readings();
}
