import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';
import '../sync/sync_service.dart';
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
  /// Offline-first: primero SQLite; después se avisa al SyncService, que
  /// sube solo si hay red (si no, quedan pendientes).
  Future<IngestResult> ingest(Stream<SensorMessage> messages) async {
    var total = 0, alerts = 0;
    final uuids = <String>[];
    await for (final m in messages) {
      final r = await save(m);
      total++;
      uuids.add(r.uuid);
      if (r.isAlert) alerts++;
    }
    lastUuids = uuids;
    SyncService.instance.onLocalChange(); // no se espera: no bloquea la UI
    return IngestResult(total, alerts);
  }

  /// uuids de la última tanda guardada (para verificarlas en Firestore).
  static List<String> lastUuids = [];

  /// Prueba 4.3: el sensor reporta 5 alertas seguidas (> umbral).
  Stream<SensorMessage> fiveAlerts() async* {
    final threshold = await _db.getThreshold('ESP32_01');
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      yield SensorMessage(
        deviceId: 'ESP32_01',
        sensor: 'temperature',
        value: double.parse((threshold + 1.5 + i * 0.8).toStringAsFixed(1)),
        unit: 'C',
        ts: DateTime.now(),
        location: 'Invernadero A',
      );
    }
  }
}
