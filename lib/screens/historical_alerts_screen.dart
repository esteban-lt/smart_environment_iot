import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';
import '../sensors/sensor_ingest_service.dart';

/// Práctica Guiada 2: histórico local de lecturas y alertas.
///
/// - Los datos vienen de SQLite a través de un `FutureBuilder` (la consulta
///   es asíncrona, la UI nunca se congela) y se pintan con `ListView.builder`.
/// - Se manejan los estados: cargando (`waiting`), error (`hasError`), lista
///   vacía y con datos (`hasData`).
/// - Las alertas (temperatura > umbral) se ven distintas: fondo rojo, icono de
///   advertencia y etiqueta "ALERTA".
class HistoricalAlertsScreen extends StatefulWidget {
  const HistoricalAlertsScreen({super.key});

  @override
  State<HistoricalAlertsScreen> createState() => _HistoricalAlertsScreenState();
}

enum _DemoState { normal, slow, error, empty }

class _HistoricalAlertsScreenState extends State<HistoricalAlertsScreen> {
  final _ingest = SensorIngestService();
  late Future<List<SensorReading>> _readingsFuture;
  bool _onlyAlerts = false;
  bool _receiving = false;
  double _threshold = DatabaseHelper.defaultTempThreshold;

  @override
  void initState() {
    super.initState();
    _readingsFuture = _load();
    _loadThreshold();
  }

  Future<void> _loadThreshold() async {
    final t = await DatabaseHelper.instance.getThreshold('ESP32_01');
    if (mounted) setState(() => _threshold = t);
  }

  /// La consulta a SQLite. `demo` solo existe para poder enseñar los estados
  /// de carga, error y vacío del FutureBuilder en la demostración.
  Future<List<SensorReading>> _load([_DemoState demo = _DemoState.normal]) async {
    switch (demo) {
      case _DemoState.slow:
        await Future.delayed(const Duration(seconds: 3));
      case _DemoState.error:
        await Future.delayed(const Duration(milliseconds: 300));
        throw Exception('No se pudo abrir la base de datos local (simulado)');
      case _DemoState.empty:
        return [];
      case _DemoState.normal:
        break;
    }
    final db = DatabaseHelper.instance;
    return _onlyAlerts ? db.getAlerts() : db.getReadingsByType('temperature');
  }

  void _refreshData([_DemoState demo = _DemoState.normal]) {
    setState(() {
      _readingsFuture = _load(demo);
    });
  }

  /// Recibe las lecturas de la fuente (simulador ESP32) y las guarda.
  Future<void> _receive() async {
    setState(() => _receiving = true);
    final r = await _ingest.ingest(sensorSource.readings());
    if (!mounted) return;
    setState(() => _receiving = false);
    _refreshData();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${r.total} lecturas recibidas y guardadas · '
          '${r.alerts} alertas'),
    ));
  }

  Future<void> _editThreshold() async {
    final ctrl = TextEditingController(text: _threshold.toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Umbral de alerta'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Temperatura máxima (°C)',
              helperText: 'Aplica a las lecturas nuevas'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (value == null) return;
    await DatabaseHelper.instance.setThresholdForAll(value);
    setState(() => _threshold = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Alertas Temp.'),
        actions: [
          IconButton(
            tooltip: 'Umbral',
            icon: const Icon(Icons.tune),
            onPressed: _editThreshold,
          ),
          PopupMenuButton<_DemoState>(
            tooltip: 'Probar estados',
            onSelected: _refreshData,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _DemoState.slow, child: Text('Simular carga lenta')),
              PopupMenuItem(value: _DemoState.error, child: Text('Simular error')),
              PopupMenuItem(value: _DemoState.empty, child: Text('Simular lista vacía')),
              PopupMenuItem(value: _DemoState.normal, child: Text('Volver a datos reales')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _receiving ? null : _receive,
        icon: _receiving
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sensors),
        label: Text(_receiving ? 'Recibiendo…' : 'Recibir del ESP32'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                'Fuente: ${sensorSource.name}\n'
                'Umbral: > ${_threshold.toStringAsFixed(1)} °C',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilterChip(
              label: const Text('Solo alertas'),
              selected: _onlyAlerts,
              onSelected: (v) {
                _onlyAlerts = v;
                _refreshData();
              },
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<SensorReading>>(
            future: _readingsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Consultando SQLite…'),
                  ]),
                );
              } else if (snapshot.hasError) {
                return _message(Icons.error_outline, Colors.red,
                    'Error al cargar datos locales', '${snapshot.error}');
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _message(Icons.inbox_outlined, Colors.grey,
                    'No hay registros guardados.',
                    'Toca "Recibir del ESP32" para cargar lecturas.');
              }

              final readings = snapshot.data!;
              final alerts = readings.where((r) => r.isAlert).length;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Text('${readings.length} lecturas'),
                    const SizedBox(width: 12),
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.red.shade700),
                    Text(' $alerts alertas',
                        style: TextStyle(color: Colors.red.shade700)),
                  ]),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _refreshData(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                      itemCount: readings.length,
                      itemBuilder: (context, index) =>
                          _ReadingTile(item: readings[index]),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _message(IconData icon, Color color, String title, String subtitle) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () => _refreshData(), child: const Text('Reintentar')),
          ]),
        ),
      );
}

/// Una fila del histórico. Alerta = rojo + advertencia; normal = verde.
class _ReadingTile extends StatelessWidget {
  final SensorReading item;
  const _ReadingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final alert = item.isAlert;
    final color = alert ? Colors.red.shade700 : Colors.green.shade700;
    final date = item.timestamp.length >= 19
        ? item.timestamp.substring(0, 19).replaceFirst('T', ' ')
        : item.timestamp;
    return Card(
      color: alert ? Colors.red.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: alert ? Colors.red.shade300 : Colors.transparent),
      ),
      child: ListTile(
        leading: Icon(
          alert ? Icons.warning_amber_rounded : Icons.thermostat,
          color: color,
          size: 32,
        ),
        title: Text(
          '${item.sensorType.toUpperCase()}: ${item.value} °C',
          style: TextStyle(
              fontWeight: alert ? FontWeight.bold : FontWeight.normal,
              color: alert ? Colors.red.shade900 : null),
        ),
        subtitle: Text('${item.nodeId} · ${item.ubicacionNodo ?? '—'}\n'
            'Fecha: $date'),
        isThreeLine: true,
        trailing: Chip(
          label: Text(alert ? 'ALERTA' : 'Normal',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          backgroundColor: color,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
