import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';

/// Resultado de una importación (para mostrarlo en pantalla).
class CsvImportResult {
  final bool valid;
  final String expectedChecksum;
  final String actualChecksum;
  final int rows;
  final int inserted;
  final String message;

  CsvImportResult({
    required this.valid,
    this.expectedChecksum = '',
    this.actualChecksum = '',
    this.rows = 0,
    this.inserted = 0,
    required this.message,
  });
}

/// Práctica Guiada 1 (Módulo 1): exportar/importar CSV con checksum SHA-256.
///
/// Formato del archivo:
/// ```
/// # CHECKSUM:<sha256 del cuerpo>
/// uuid,node_id,sensorType,value,timestamp,is_alert,updated_at,ubicacion_nodo
/// ...filas...
/// ```
/// Al importar se recalcula el SHA-256 del cuerpo; si no coincide con el de
/// la cabecera, el archivo se RECHAZA y no se toca la base de datos.
class CsvNodeManager {
  static const fileName = 'iot_readings_export.csv';
  static const header = [
    'uuid', 'node_id', 'sensorType', 'value', 'timestamp',
    'is_alert', 'updated_at', 'ubicacion_nodo'
  ];

  // Ojo: el ejemplo del curso usa ListToCsvConverter() con su fin de línea por
  // defecto (\r\n), pero al importar une las líneas con \n. Eso hace que el
  // checksum NUNCA coincida. Aquí se fija eol: '\n' en ambos lados.
  static const _toCsv = ListToCsvConverter(eol: '\n');
  static const _fromCsv =
      CsvToListConverter(eol: '\n', shouldParseNumbers: false);

  Future<String> get filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }

  static String sha256Of(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// Exporta todas las lecturas. Regresa la ruta completa del archivo.
  Future<String> exportReadingsToCsv() async {
    final readings = await DatabaseHelper.instance.getAllReadings();
    final rows = <List<dynamic>>[
      header,
      for (final r in readings)
        [
          r.uuid, r.nodeId, r.sensorType, r.value, r.timestamp,
          r.isAlert ? 1 : 0, r.updatedAt, r.ubicacionNodo ?? ''
        ],
    ];
    final csvData = _toCsv.convert(rows);
    final checksum = sha256Of(csvData);

    final path = await filePath;
    await File(path).writeAsString('# CHECKSUM:$checksum\n$csvData');
    return path;
  }

  /// Simula que alguien edita el archivo fuera de la app: cambia el valor de
  /// la primera lectura pero deja el checksum original.
  Future<String> tamperCsv() async {
    final file = File(await filePath);
    final lines = await file.readAsLines();
    if (lines.length < 3) return 'No hay filas para alterar (exporta primero).';
    final cols = lines[2].split(',');
    final before = cols[3];
    cols[3] = '99.9';
    lines[2] = cols.join(',');
    await file.writeAsString(lines.join('\n'));
    return 'Fila 1 alterada: value $before → 99.9 (checksum sin tocar)';
  }

  /// Verifica la integridad y, solo si es válido, importa las filas.
  Future<CsvImportResult> verifyAndImportCsv() async {
    final file = File(await filePath);
    if (!await file.exists()) {
      return CsvImportResult(valid: false, message: 'No existe el archivo.');
    }

    final lines = await file.readAsLines();
    if (lines.isEmpty || !lines[0].startsWith('# CHECKSUM:')) {
      return CsvImportResult(valid: false, message: 'Falta la cabecera CHECKSUM.');
    }

    final originalChecksum = lines[0].replaceFirst('# CHECKSUM:', '').trim();
    final csvBody = lines.sublist(1).join('\n');
    final recalculated = sha256Of(csvBody);

    if (originalChecksum != recalculated) {
      return CsvImportResult(
        valid: false,
        expectedChecksum: originalChecksum,
        actualChecksum: recalculated,
        message: 'ALERTA: el CSV fue alterado. Importación rechazada.',
      );
    }

    final parsed = _fromCsv.convert(csvBody).skip(1).toList(); // sin header
    final readings = <SensorReading>[];
    final nodeIds = <String>{};
    for (final row in parsed) {
      nodeIds.add(row[1].toString());
      readings.add(SensorReading(
        uuid: row[0].toString(),
        nodeId: row[1].toString(),
        sensorType: row[2].toString(),
        value: double.parse(row[3].toString()),
        timestamp: row[4].toString(),
        isAlert: row[5].toString() == '1',
        updatedAt: int.parse(row[6].toString()),
        ubicacionNodo: row[7].toString().isEmpty ? null : row[7].toString(),
      ));
    }
    // La FK exige que el nodo exista antes que sus lecturas.
    for (final id in nodeIds) {
      await DatabaseHelper.instance.ensureNode(id);
    }
    final inserted = await DatabaseHelper.instance
        .insertBatchReadings(readings, ignoreDuplicates: true);

    return CsvImportResult(
      valid: true,
      expectedChecksum: originalChecksum,
      actualChecksum: recalculated,
      rows: readings.length,
      inserted: inserted,
      message: 'Checksum válido. ${readings.length} filas leídas, '
          '$inserted nuevas, ${readings.length - inserted} ya existían.',
    );
  }
}
