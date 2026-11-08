import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/sensor_reading.dart';

/// Lo que la UI necesita saber de la sincronización.
class SyncStatus {
  final bool online;
  final bool syncing;
  final int pending;
  final int synced;
  final String message;

  const SyncStatus({
    this.online = false,
    this.syncing = false,
    this.pending = 0,
    this.synced = 0,
    this.message = '',
  });
}

enum SyncOutcome { uploaded, cloudWins }

/// Sincronización Offline-First con Cloud Firestore.
///
/// Reglas:
/// 1. **Siempre se escribe primero en SQLite** (`synced = 0`). La app nunca
///    depende de la red para guardar.
/// 2. Un listener de `connectivity_plus` detecta cuando vuelve la red y
///    sincroniza solo, sin botón ni reinicio.
/// 3. **Sin duplicados**: el id del documento en Firestore es el `uuid` de la
///    lectura, así que subirla dos veces escribe el MISMO documento (`set`
///    idempotente) en vez de crear otro.
/// 4. **Last-Write-Wins** por `updated_at`: dentro de una transacción se lee
///    el documento remoto; si es más reciente que el local, NO se sobrescribe
///    y la versión de la nube reemplaza a la local.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _db = DatabaseHelper.instance;
  final _firestore = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get readings =>
      _firestore.collection('readings');

  final status = ValueNotifier(const SyncStatus());
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = false;
  bool _syncing = false;

  bool get online => _online;

  static bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  /// Se llama una vez al arrancar la app.
  Future<void> start() async {
    _online = _hasNetwork(await Connectivity().checkConnectivity());
    await _publish(_online ? 'En línea' : 'Sin conexión: todo se guarda en SQLite');

    _sub ??= Connectivity().onConnectivityChanged.listen((results) async {
      final wasOnline = _online;
      _online = _hasNetwork(results);
      if (_online == wasOnline) return;
      await _publish(_online
          ? 'Volvió la conexión: sincronizando…'
          : 'Sin conexión: todo se guarda en SQLite');
      if (_online) {
        // Pequeña espera: al salir de modo avión la red tarda un momento en
        // estar realmente utilizable.
        await Future.delayed(const Duration(seconds: 2));
        await syncPending();
      }
    });

    if (_online) await syncPending();
  }

  /// Avisar que hubo cambios locales (lectura nueva/editada).
  Future<void> onLocalChange() async {
    await _publish(_online ? null : 'Sin conexión: guardado en SQLite (pendiente)');
    if (_online) await syncPending();
  }

  /// Sube todas las pendientes. Nunca lanza excepciones hacia la UI.
  Future<String> syncPending() async {
    if (!_online) return 'Sin conexión: se intentará al volver la red.';
    if (_syncing) return 'Ya hay una sincronización en curso.';
    _syncing = true;
    var uploaded = 0, cloudWins = 0;
    String msg;
    try {
      await _publish('Sincronizando…');
      final pending = await _db.getPendingReadings();
      for (final r in pending) {
        final outcome =
            await _syncOne(r).timeout(const Duration(seconds: 20));
        outcome == SyncOutcome.uploaded ? uploaded++ : cloudWins++;
      }
      msg = pending.isEmpty
          ? 'Todo sincronizado'
          : 'Sincronizadas: $uploaded subidas'
              '${cloudWins > 0 ? ', $cloudWins conservadas de la nube (LWW)' : ''}';
    } catch (e) {
      // Se cayó la red a la mitad, timeout, etc.: lo que no subió sigue con
      // synced = 0 y se reintenta solo en la próxima reconexión.
      msg = 'Sincronización pausada ($uploaded subidas); se reintenta luego';
      debugPrint('Sync error: $e');
    } finally {
      _syncing = false;
    }
    await _publish(msg);
    return msg;
  }

  /// Sincroniza UNA lectura aplicando Last-Write-Wins.
  Future<SyncOutcome> _syncOne(SensorReading local) async {
    final doc = readings.doc(local.uuid); // uuid = id del documento
    Map<String, dynamic>? remoteWinner;

    final outcome = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(doc);
      final remote = snap.data();
      final remoteUpdatedAt = (remote?['updated_at'] as num?)?.toInt();

      if (remoteUpdatedAt != null && remoteUpdatedAt > local.updatedAt) {
        // La nube tiene una versión más nueva: NO se sobrescribe.
        remoteWinner = remote;
        return SyncOutcome.cloudWins;
      }
      // La local es igual o más nueva (o el documento no existe): se escribe.
      tx.set(doc, toFirestore(local));
      return SyncOutcome.uploaded;
    });

    if (outcome == SyncOutcome.cloudWins) {
      await _db.applyRemote(local.uuid, remoteWinner!);
    } else {
      await _db.markSynced(local.uuid, local.updatedAt);
    }
    return outcome;
  }

  static Map<String, dynamic> toFirestore(SensorReading r) => {
        'uuid': r.uuid,
        'node_id': r.nodeId,
        'sensorType': r.sensorType,
        'value': r.value,
        'timestamp': r.timestamp,
        'is_alert': r.isAlert,
        'ubicacion_nodo': r.ubicacionNodo,
        'updated_at': r.updatedAt,
        'synced_at': FieldValue.serverTimestamp(),
      };

  Future<void> _publish([String? message]) async {
    final c = await _db.syncCounts();
    status.value = SyncStatus(
      online: _online,
      syncing: _syncing,
      pending: c.pending,
      synced: c.synced,
      message: message ?? status.value.message,
    );
  }

  // ------------------------------------------------------------------------
  // Utilidades para la pantalla Demo
  // ------------------------------------------------------------------------

  /// Cuántos documentos hay en Firestore y si las uuid dadas existen 1 vez.
  Future<String> cloudReport(List<String> uuids) async {
    if (!_online) return 'Sin conexión: no se puede consultar Firestore.';
    final total = (await readings.count().get()).count ?? 0;
    final c = await _db.syncCounts();
    final buf = StringBuffer('Firestore /readings: $total documentos\n'
        'SQLite: ${c.synced} sincronizadas, ${c.pending} pendientes\n');
    for (final id in uuids) {
      final n =
          (await readings.where('uuid', isEqualTo: id).count().get()).count;
      buf.writeln('  ${id.substring(0, 8)}… → $n doc(s) en la nube');
    }
    return buf.toString();
  }

  /// Demostración de Last-Write-Wins con los dos casos posibles.
  Future<String> demoLastWriteWins() async {
    if (!_online) return 'Se necesita conexión para la demo de conflictos.';
    final all = await _db.getAllReadings();
    final synced = all.where((r) => r.synced).toList();
    if (synced.length < 2) return 'Se necesitan al menos 2 lecturas sincronizadas.';
    final now = DateTime.now().millisecondsSinceEpoch;
    final tenMinAgo = now - const Duration(minutes: 10).inMilliseconds;
    final buf = StringBuffer();

    // Caso A: la nube es más reciente que el cambio offline local.
    final a = synced[0];
    await readings.doc(a.uuid).update({
      'value': 30.5,
      'ubicacion_nodo': 'Editado desde otro dispositivo',
      'updated_at': now,
    });
    await _db.editLocalAt(a.uuid, value: 22.2, updatedAt: tenMinAgo);
    var o = await _syncOne((await _db.getByUuid(a.uuid))!);
    var cloud = (await readings.doc(a.uuid).get()).data()!;
    var local = (await _db.getByUuid(a.uuid))!;
    buf.writeln('CASO A  ${a.uuid.substring(0, 8)}…');
    buf.writeln(' nube : 30.5 (updated_at = ahora)');
    buf.writeln(' local: 22.2 (offline, hace 10 min)');
    buf.writeln(' → ${o == SyncOutcome.cloudWins ? "GANA LA NUBE" : "gana local"}');
    buf.writeln(' resultado nube=${cloud['value']} local=${local.value}\n');

    // Caso B: el cambio local es más reciente que la nube.
    final b = synced[1];
    await readings.doc(b.uuid).update({'value': 25.0, 'updated_at': tenMinAgo});
    await _db.editLocalAt(b.uuid, value: 37.7, updatedAt: now);
    o = await _syncOne((await _db.getByUuid(b.uuid))!);
    cloud = (await readings.doc(b.uuid).get()).data()!;
    local = (await _db.getByUuid(b.uuid))!;
    buf.writeln('CASO B  ${b.uuid.substring(0, 8)}…');
    buf.writeln(' nube : 25.0 (hace 10 min)');
    buf.writeln(' local: 37.7 (updated_at = ahora)');
    buf.writeln(' → ${o == SyncOutcome.uploaded ? "GANA LOCAL (se sube)" : "gana nube"}');
    buf.write(' resultado nube=${cloud['value']} local=${local.value}');

    await _publish('Demo LWW terminada');
    return buf.toString();
  }
}
