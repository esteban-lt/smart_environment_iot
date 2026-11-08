import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../demo/sql_injection_demo.dart';
import '../models/sensor_reading.dart';
import '../storage/csv_node_manager.dart';
import '../storage/preferences_storage.dart';

/// Pantalla "Demo": botones para enseñar en vivo cada punto de las actividades.
/// El resultado de cada botón aparece en el panel fijo de abajo.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final _db = DatabaseHelper.instance;
  final _prefs = PreferencesStorage();
  final _csv = CsvNodeManager();
  Map<String, dynamic>? _info;
  String _log = '';
  bool? _ok; // icono verde/rojo del panel (null = sin icono)

  static const _payload = "pepe'), ('admin";
  static const _labNode = 'ESP32_LAB';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final info = await _db.getDbInfo();
    if (mounted) setState(() => _info = info);
  }

  void _setLog(String text, {bool? ok}) => setState(() {
        _log = text;
        _ok = ok;
      });

  // ---------------------------------------------------------------- BD v1 ---

  /// Carga un nodo y unas lecturas de ejemplo.
  Future<void> _loadV1Data() async {
    await _db.insertNode('ESP32_01', 'Nodo invernadero');
    final threshold = await _db.getThreshold('ESP32_01');
    const values = [24.5, 31.2, 36.8, 29.9, 38.4];
    for (final v in values) {
      final now = DateTime.now();
      await _db.insertReading(SensorReading(
        uuid: const Uuid().v4(),
        nodeId: 'ESP32_01',
        sensorType: 'temperature',
        value: v,
        timestamp: now.toIso8601String(),
        isAlert: v > threshold,
        updatedAt: now.millisecondsSinceEpoch,
      ));
    }
    await _refresh();
    _setLog('Se insertaron ${values.length} lecturas del nodo ESP32_01 '
        '(umbral $threshold °C).');
  }

  /// Intenta guardar una lectura de un nodo que no existe.
  Future<void> _testForeignKey() async {
    try {
      await _db.insertReading(SensorReading(
        uuid: const Uuid().v4(),
        nodeId: 'NODO_FANTASMA',
        sensorType: 'temperature',
        value: 20,
        timestamp: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _setLog('Se insertó (las FK NO están activas).', ok: false);
    } catch (e) {
      _setLog('Rechazado por la llave foránea:\n$e', ok: true);
    }
  }

  Future<void> _showSchema() async {
    await _refresh();
    final schema =
        (_info!['schema'] as List).map((t) => t['sql']).join('\n\n');
    _setLog(schema);
  }

  /// Muestra las lecturas tal como están en la tabla (para el antes/después
  /// de la migración).
  Future<void> _showRows() async {
    final rows = await (await _db.database).query('readings', orderBy: 'id');
    if (rows.isEmpty) return _setLog('La tabla readings está vacía.');
    final cols = rows.first.keys.where((k) => k != 'uuid' && k != 'timestamp');
    final buf = StringBuffer('readings (${rows.length} filas)\n'
        '${cols.join(' | ')}\n');
    for (final r in rows.take(12)) {
      buf.writeln(cols.map((c) => r[c]).join(' | '));
    }
    if (rows.length > 12) buf.writeln('… (${rows.length - 12} más)');
    _setLog(buf.toString());
  }

  // ----------------------------------------------------------------- JSON ---

  Future<void> _saveJson() async {
    final prefs = {
      'tema': 'oscuro',
      'intervalo_muestreo_s': 5,
      'umbral_temperatura_c': DatabaseHelper.defaultTempThreshold,
      'nodo_principal': 'ESP32_01',
      'guardado_en': DateTime.now().toIso8601String(),
    };
    try {
      final path = await _prefs.save(prefs);
      final ok = await _prefs.verify(prefs);
      final size = await File(path).length();
      _setLog(
          'JSON guardado ($size bytes) y verificado: ${ok ? "OK" : "NO coincide"}\n'
          'Ruta completa:\n$path',
          ok: ok);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('No se pudo guardar: ${e.message}')));
    }
  }

  Future<void> _readJson() async {
    final f = await _prefs.file;
    final data = await _prefs.read();
    if (data == null) {
      return _setLog('No existe ${f.path}\n(primero toca "Guardar JSON")',
          ok: false);
    }
    _setLog('Leído de:\n${f.path}\n\n${await f.readAsString()}', ok: true);
  }

  // ------------------------------------------------------------------ CSV ---

  Future<void> _exportCsv() async {
    final path = await _csv.exportReadingsToCsv();
    final lines = await File(path).readAsLines();
    _setLog('CSV exportado (${lines.length - 2} lecturas)\n'
        'Ruta completa:\n$path\n\n'
        '${lines.take(4).join('\n')}\n…');
  }

  Future<void> _tamperCsv() async {
    final msg = await _csv.tamperCsv();
    final lines = await File(await _csv.filePath).readAsLines();
    _setLog('$msg\n\n${lines.take(3).join('\n')}\n…');
  }

  Future<void> _importCsv() async {
    final r = await _csv.verifyAndImportCsv();
    await _refresh();
    _setLog(
        '${r.valid ? "✅" : "❌"} ${r.message}\n\n'
        'Checksum en cabecera:\n${r.expectedChecksum}\n'
        'Checksum recalculado:\n${r.actualChecksum}',
        ok: r.valid);
  }

  // ---------------------------------------------------------- Masivo/ACID ---

  List<SensorReading> _fakeReadings(int n, double threshold) {
    final rnd = Random();
    final now = DateTime.now();
    return List.generate(n, (i) {
      final v = double.parse((20 + rnd.nextDouble() * 20).toStringAsFixed(1));
      return SensorReading(
        uuid: const Uuid().v4(),
        nodeId: _labNode,
        sensorType: 'temperature',
        value: v,
        timestamp: now.add(Duration(seconds: i)).toIso8601String(),
        isAlert: v > threshold,
        updatedAt: now.millisecondsSinceEpoch,
        ubicacionNodo: 'Laboratorio',
      );
    });
  }

  /// Compara 200 inserts sueltos contra 200 en transaction + batch.
  Future<void> _bulkInsert() async {
    const n = 200;
    _setLog('Insertando 2 × $n lecturas…');
    await _db.insertNode(_labNode, 'Nodo de pruebas');
    final threshold = await _db.getThreshold(_labNode);

    final sw1 = Stopwatch()..start();
    for (final r in _fakeReadings(n, threshold)) {
      await _db.insertReading(r);
    }
    sw1.stop();

    final sw2 = Stopwatch()..start();
    final inserted = await _db.insertBatchReadings(_fakeReadings(n, threshold));
    sw2.stop();

    await _refresh();
    final speedup = sw1.elapsedMilliseconds / max(sw2.elapsedMilliseconds, 1);
    _setLog('Nodo $_labNode\n'
        '• $n inserts uno por uno: ${sw1.elapsedMilliseconds} ms\n'
        '• $inserted en db.transaction + batch: ${sw2.elapsedMilliseconds} ms\n'
        '→ el batch fue ${speedup.toStringAsFixed(1)}× más rápido\n'
        'Total de lecturas en la BD: ${_info!['readings']}');
  }

  Future<void> _deleteLabNode() async {
    final before = await _db.countReadings();
    final n = await _db.deleteNode(_labNode);
    final after = await _db.countReadings();
    await _refresh();
    _setLog(n == 0
        ? 'No existe el nodo $_labNode.'
        : "DELETE FROM nodes WHERE id = ?  ['$_labNode']\n"
            'ON DELETE CASCADE borró ${before - after} lecturas\n'
            '(de $before a $after).');
  }

  // ------------------------------------------------------------------ SQLi ---

  Future<void> _sqlInjection({required bool vulnerable}) async {
    final demo = SqlInjectionDemo();
    await demo.open();
    if (vulnerable) {
      await demo.saveUserDataVulnerable(_payload);
    } else {
      await demo.saveUserData(_payload);
    }
    final users = await demo.allUsers();
    _setLog(
        '${vulnerable ? "❌ Vulnerable (concatenación)" : "✅ Parametrizado"}\n'
        'Entrada: $_payload\n'
        'Filas en users: ${users.length}\n'
        '${users.map((u) => '  • $u').join('\n')}');
  }

  // ------------------------------------------------------------------- UI ---

  Widget _section(String title, List<Widget> buttons) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: buttons),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Demo')),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: info == null
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Base de datos SQLite',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text('Versión del esquema: ${info['version']}   '
                                'PRAGMA foreign_keys = ${info['foreign_keys']}'),
                            Text('Nodos: ${info['nodes']}   '
                                'Lecturas: ${info['readings']}'),
                            Text('Columnas de readings: '
                                '${(info['columns'] as List).join(', ')}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                ),
              ),
              _section('Base de datos', [
                FilledButton(
                    onPressed: _loadV1Data,
                    child: const Text('Cargar datos v1')),
                OutlinedButton(
                    onPressed: _showRows, child: const Text('Ver filas')),
                OutlinedButton(
                    onPressed: _showSchema, child: const Text('Ver esquema')),
                OutlinedButton(
                    onPressed: _testForeignKey,
                    child: const Text('Probar FK')),
              ]),
              _section('Archivo JSON (preferencias)', [
                FilledButton.tonal(
                    onPressed: _saveJson, child: const Text('Guardar JSON')),
                FilledButton.tonal(
                    onPressed: _readJson,
                    child: const Text('Leer JSON')),
              ]),
              _section('CSV con checksum SHA-256', [
                FilledButton.tonal(
                    onPressed: _exportCsv, child: const Text('Exportar CSV')),
                FilledButton.tonal(
                    onPressed: _tamperCsv, child: const Text('Alterar CSV')),
                FilledButton.tonal(
                    onPressed: _importCsv, child: const Text('Importar CSV')),
              ]),
              _section('Transacciones (inserción masiva)', [
                FilledButton.tonal(
                    onPressed: _bulkInsert,
                    child: const Text('Inserción masiva')),
                OutlinedButton(
                    onPressed: _deleteLabNode,
                    child: const Text('Borrar nodo de prueba')),
              ]),
              _section('Inyección SQL (Módulo 2)', [
                FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade100),
                    onPressed: () => _sqlInjection(vulnerable: true),
                    child: const Text('Código vulnerable')),
                FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade100),
                    onPressed: () => _sqlInjection(vulnerable: false),
                    child: const Text('Código parametrizado')),
              ]),
            ],
          ),
        ),
        if (_log.isNotEmpty)
          Container(
            width: double.infinity,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.38),
            decoration: BoxDecoration(
              color: _ok == null
                  ? Colors.grey.shade200
                  : (_ok! ? Colors.green.shade50 : Colors.red.shade50),
              border: Border(
                  top: BorderSide(
                      width: 3,
                      color: _ok == null
                          ? Colors.grey
                          : (_ok! ? Colors.green : Colors.red))),
            ),
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_ok != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(_ok! ? Icons.verified : Icons.gpp_bad,
                        color: _ok! ? Colors.green : Colors.red, size: 32),
                  ),
                Expanded(
                  child: SelectableText(_log,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11.5)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
