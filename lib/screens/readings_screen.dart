import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';
import '../sync/sync_service.dart';

/// CRUD de lecturas: lista (READ), botón + (CREATE), tocar una fila (UPDATE)
/// e icono de basura (DELETE).
class ReadingsScreen extends StatefulWidget {
  const ReadingsScreen({super.key});

  @override
  State<ReadingsScreen> createState() => _ReadingsScreenState();
}

class _ReadingsScreenState extends State<ReadingsScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<SensorReading>> _future;

  @override
  void initState() {
    super.initState();
    _future = _db.getAllReadings();
  }

  void _refresh() {
    setState(() {
      _future = _db.getAllReadings();
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  /// Diálogo compartido para crear y editar (valor + ubicación).
  Future<(double, String)?> _askValues(
      {String title = 'Nueva lectura', double? value, String? ubicacion}) {
    final valueCtrl = TextEditingController(text: value?.toString() ?? '');
    final ubicCtrl = TextEditingController(text: ubicacion ?? '');
    return showDialog<(double, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: valueCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Temperatura (°C)'),
          ),
          TextField(
            controller: ubicCtrl,
            decoration: const InputDecoration(labelText: 'Ubicación del nodo'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(valueCtrl.text.replaceAll(',', '.'));
              if (v == null) return;
              Navigator.pop(ctx, (v, ubicCtrl.text.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final res = await _askValues();
    if (res == null) return;
    await _db.ensureNode('ESP32_01');
    final threshold = await _db.getThreshold('ESP32_01');
    final now = DateTime.now();
    await _db.insertReading(SensorReading(
      uuid: const Uuid().v4(),
      nodeId: 'ESP32_01',
      sensorType: 'temperature',
      value: res.$1,
      timestamp: now.toIso8601String(),
      isAlert: res.$1 > threshold,
      updatedAt: now.millisecondsSinceEpoch,
      ubicacionNodo: res.$2.isEmpty ? null : res.$2,
    ));
    _snack('Lectura creada');
    _refresh();
    SyncService.instance.onLocalChange();
  }

  Future<void> _edit(SensorReading r) async {
    final res = await _askValues(
        title: 'Editar lectura #${r.id}', value: r.value, ubicacion: r.ubicacionNodo);
    if (res == null) return;
    await _db.updateReading(r.copyWith(value: res.$1, ubicacionNodo: res.$2));
    _snack('Lectura #${r.id} actualizada');
    _refresh();
    SyncService.instance.onLocalChange();
  }

  Future<void> _delete(SensorReading r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar lectura?'),
        content: Text('#${r.id}: ${r.value} °C de ${r.nodeId}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteReading(r.id!);
    _snack('Lectura #${r.id} borrada');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lecturas (CRUD)')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'Nueva lectura',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<SensorReading>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No hay lecturas guardadas.'));
          }
          final items = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final r = items[i];
              return ListTile(
                onTap: () => _edit(r),
                leading: CircleAvatar(child: Text('${r.id}')),
                title: Text('${r.value} °C · ${r.nodeId}'),
                subtitle: Text('${r.ubicacionNodo ?? '—'}\n'
                    '${r.timestamp.substring(0, 19).replaceFirst('T', ' ')}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
