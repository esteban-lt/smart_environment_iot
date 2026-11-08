import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../demo/sql_injection_demo.dart';
import '../models/sensor_reading.dart';

/// Pantalla "Demo": botones para enseñar en vivo cada punto de las actividades.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, dynamic>? _info;
  String _log = '';

  static const _payload = "pepe'), ('admin";

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final info = await _db.getDbInfo();
    setState(() => _info = info);
  }

  void _setLog(String text) => setState(() => _log = text);

  /// Carga un nodo y unas lecturas de ejemplo en el esquema v1.
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
      _setLog('Se insertó (las FK NO están activas).');
    } catch (e) {
      _setLog('Rechazado por la llave foránea:\n$e');
    }
  }

  Future<void> _sqlInjection({required bool vulnerable}) async {
    final demo = SqlInjectionDemo();
    await demo.open();
    if (vulnerable) {
      await demo.saveUserDataVulnerable(_payload);
    } else {
      await demo.saveUserData(_payload);
    }
    final users = await demo.allUsers();
    _setLog('${vulnerable ? "❌ Vulnerable (concatenación)" : "✅ Parametrizado"}\n'
        'Entrada: $_payload\n'
        'Filas en users: ${users.length}\n'
        '${users.map((u) => '  • $u').join('\n')}');
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Demo')),
      body: ListView(
        padding: const EdgeInsets.all(12),
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
                        const SizedBox(height: 6),
                        SelectableText('Ruta: ${info['path']}'),
                        Text('Versión del esquema: ${info['version']}'),
                        Text('PRAGMA foreign_keys = ${info['foreign_keys']}'),
                        Text('Nodos: ${info['nodes']}   '
                            'Lecturas: ${info['readings']}'),
                      ],
                    ),
            ),
          ),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton(
                onPressed: _loadV1Data, child: const Text('Cargar datos v1')),
            OutlinedButton(
                onPressed: _testForeignKey, child: const Text('Probar FK')),
            OutlinedButton(
                onPressed: () async {
                  await _refresh();
                  final schema = (_info!['schema'] as List)
                      .map((t) => t['sql'])
                      .join('\n\n');
                  _setLog(schema);
                },
                child: const Text('Ver esquema')),
          ]),
          const Divider(),
          Text('Inyección SQL (Módulo 2)',
              style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: 8, children: [
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
          const SizedBox(height: 8),
          if (_log.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.grey.shade200,
              child: SelectableText(_log,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
