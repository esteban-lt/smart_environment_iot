/// Entidad SensorReading: una lectura enviada por un nodo (ESP32).
///
/// Basada en el modelo del Módulo 2 (`id`, `sensorType`, `value`, `timestamp`)
/// y extendida con lo mínimo que necesita el proyecto:
/// - `uuid`: identificador global (sirve después como ID del documento en Firestore).
/// - `nodeId`: FK al nodo que generó la lectura.
/// - `isAlert`: 1 si la lectura superó el umbral del nodo.
/// - `synced` / `updatedAt`: control de sincronización (offline-first).
/// - `ubicacionNodo`: dónde está el nodo (columna agregada en la migración v1 → v2).
class SensorReading {
  final int? id;
  final String uuid;
  final String nodeId;
  final String sensorType; // 'temperature', 'humidity'
  final double value;
  final String timestamp; // ISO-8601, momento en que se tomó la lectura
  final bool isAlert;
  final bool synced;
  final int updatedAt; // epoch en milisegundos, para Last-Write-Wins
  final String? ubicacionNodo; // v2

  SensorReading({
    this.id,
    required this.uuid,
    required this.nodeId,
    required this.sensorType,
    required this.value,
    required this.timestamp,
    this.isAlert = false,
    this.synced = false,
    required this.updatedAt,
    this.ubicacionNodo,
  });

  Map<String, dynamic> toMap() {
    return {
      // Si no se manda ubicación, se omite la llave para que SQLite use el DEFAULT.
      if (ubicacionNodo != null) 'ubicacion_nodo': ubicacionNodo,
      'id': id,
      'uuid': uuid,
      'node_id': nodeId,
      'sensorType': sensorType,
      'value': value,
      'timestamp': timestamp,
      'is_alert': isAlert ? 1 : 0,
      'synced': synced ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory SensorReading.fromMap(Map<String, dynamic> map) {
    return SensorReading(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      nodeId: map['node_id'] as String,
      sensorType: map['sensorType'] as String,
      value: (map['value'] as num).toDouble(),
      timestamp: map['timestamp'] as String,
      isAlert: map['is_alert'] == 1,
      synced: map['synced'] == 1,
      updatedAt: map['updated_at'] as int,
      ubicacionNodo: map['ubicacion_nodo'] as String?,
    );
  }

  /// Copia con cambios (para el UPDATE del CRUD).
  SensorReading copyWith({double? value, String? ubicacionNodo, bool? isAlert,
      bool? synced, int? updatedAt}) {
    return SensorReading(
      id: id,
      uuid: uuid,
      nodeId: nodeId,
      sensorType: sensorType,
      value: value ?? this.value,
      timestamp: timestamp,
      isAlert: isAlert ?? this.isAlert,
      synced: synced ?? this.synced,
      updatedAt: updatedAt ?? this.updatedAt,
      ubicacionNodo: ubicacionNodo ?? this.ubicacionNodo,
    );
  }
}
