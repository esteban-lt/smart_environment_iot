import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';
import 'mock_sensor_source.dart';
import 'sensor_source.dart';

/// Fuente activa de la app. Para usar el ESP32 real:
/// `final SensorSource sensorSource = MqttSensorSource(host: '<ip del broker>');`
final SensorSource sensorSource = MockSensorSource();

class IngestResult {
  final int total;
  final int alerts;
  IngestResult(this.total, this.alerts);
}

/// Lógica de negocio IoT: cada mensaje del hardware se guarda en SQLite y,
/// si es temperatura y supera el umbral del nodo, queda marcado como alerta.
class SensorIngestService {
  final _db = DatabaseHelper.instance;

  /// Guarda un mensaje. Regresa la lectura tal como quedó en la base.
  Future<SensorReading> save(SensorMessage m) async {
    await _db.ensureNode(m.deviceId);
    final threshold = await _db.getThreshold(m.deviceId);
    final reading = SensorReading(
      uuid: const Uuid().v4(),
      nodeId: m.deviceId,
      sensorType: m.sensor,
      value: m.value,
      timestamp: m.ts.toIso8601String(),
      // Regla del proyecto: alerta si temperatura > umbral (35 °C por defecto).
      isAlert: m.sensor == 'temperature' && m.value > threshold,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      ubicacionNodo: m.location,
    );
    await _db.insertReading(reading);
    return reading;
  }

  /// Consume un flujo finito de mensajes (el simulador) y los guarda todos.
  Future<IngestResult> ingest(Stream<SensorMessage> messages) async {
    var total = 0, alerts = 0;
    await for (final m in messages) {
      final r = await save(m);
      total++;
      if (r.isAlert) alerts++;
    }
    return IngestResult(total, alerts);
  }
}
