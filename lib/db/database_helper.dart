import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sensor_reading.dart';

/// DatabaseHelper: único punto de acceso a la base SQLite local (`iot_local.db`).
///
/// Sigue el patrón del Subtema 2.1 del curso:
/// - **Singleton**: el constructor `DatabaseHelper._init()` es privado y la única
///   instancia vive en [instance]. Así toda la app comparte una sola conexión.
/// - **Inicialización perezosa**: la base se abre la primera vez que alguien pide
///   [database]; las siguientes veces se reutiliza la misma conexión.
/// - **Integridad referencial**: en `onConfigure` se ejecuta
///   `PRAGMA foreign_keys = ON` (SQLite las trae apagadas por defecto).
/// - **Consultas parametrizadas**: todos los métodos usan `insert`, `query`
///   con `whereArgs`, etc. Nunca se concatena texto del usuario dentro del SQL.
///
/// - **Migraciones**: `onUpgrade` lleva el esquema de una versión a otra con
///   `ALTER TABLE`, sin borrar tablas ni datos (nunca `DROP TABLE`).
///
/// Esquema:
/// ```
/// nodes (1) ────< (N) readings
/// v1: esquema base (Actividad 1)
/// v2: readings + ubicacion_nodo (Actividad 2)
/// ```
class DatabaseHelper {
  /// Nombre del archivo de la base de datos.
  static const String dbName = 'iot_local.db';

  /// Versión actual del esquema.
  /// v1 = esquema base, v2 = se agrega `ubicacion_nodo` a `readings`.
  static const int dbVersion = 2;

  /// Valor que reciben las lecturas que ya existían antes de la migración.
  static const String defaultUbicacion = 'Sin asignar';

  /// Umbral por defecto de temperatura (°C) para marcar una lectura como alerta.
  static const double defaultTempThreshold = 35.0;

  /// La única instancia de la clase (Singleton).
  static final DatabaseHelper instance = DatabaseHelper._init();

  /// Conexión abierta (se crea una sola vez).
  static Database? _database;

  /// Constructor privado: nadie fuera de esta clase puede hacer `DatabaseHelper()`.
  DatabaseHelper._init();

  /// Devuelve la conexión, abriéndola solo la primera vez.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(dbName);
    return _database!;
  }

  /// Ruta completa del archivo `.db` dentro del almacenamiento interno de la app.
  Future<String> get dbPath async => join(await getDatabasesPath(), dbName);

  /// Abre (o crea) la base de datos y registra los callbacks del ciclo de vida.
  Future<Database> _initDB(String fileName) async {
    final path = join(await getDatabasesPath(), fileName);
    return await openDatabase(
      path,
      version: dbVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// Se ejecuta cada vez que se abre la conexión, antes de onCreate/onUpgrade.
  /// Activa las llaves foráneas; sin esto SQLite ignora los REFERENCES.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Crea el esquema la primera vez que se instala la app.
  ///
  /// Siempre crea el esquema v1 y luego aplica las mismas migraciones que
  /// `onUpgrade`. Así una instalación nueva y una actualizada terminan con
  /// exactamente el mismo esquema (una sola fuente de verdad).
  ///
  /// - `nodes`: cada ESP32 del proyecto, con su umbral de temperatura.
  /// - `readings`: lecturas de la entidad [SensorReading]. Cada una pertenece a
  ///   un nodo (`node_id` → `nodes.id`). Si se borra el nodo, se borran sus
  ///   lecturas (`ON DELETE CASCADE`).
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE nodes (
        id             TEXT PRIMARY KEY,
        name           TEXT NOT NULL,
        temp_threshold REAL NOT NULL DEFAULT $defaultTempThreshold
      )
    ''');

    await db.execute('''
      CREATE TABLE readings (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT    NOT NULL UNIQUE,
        node_id     TEXT    NOT NULL,
        sensorType  TEXT    NOT NULL,
        value       REAL    NOT NULL,
        timestamp   TEXT    NOT NULL,
        is_alert    INTEGER NOT NULL DEFAULT 0 CHECK (is_alert IN (0, 1)),
        synced      INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)),
        updated_at  INTEGER NOT NULL,
        FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE
      )
    ''');

    await _upgradeDB(db, 1, version);
  }

  /// Controlador de migraciones (se ejecuta solo cuando la versión instalada
  /// es menor que [dbVersion]). Cada paso es incremental: de una versión a la
  /// siguiente. sqflite lo corre dentro de una transacción: si algo falla, la
  /// base se queda como estaba.
  ///
  /// Regla: aquí NUNCA se usa DROP TABLE. Solo se agregan cosas.
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: nueva columna. Los registros existentes se conservan tal cual
      // y reciben el valor por defecto.
      await db.execute(
        "ALTER TABLE readings ADD COLUMN ubicacion_nodo TEXT "
        "DEFAULT '$defaultUbicacion'",
      );
    }
    // Futuras migraciones: if (oldVersion < 3) { ... }
  }

  // ---------------------------------------------------------------------------
  // Nodos
  // ---------------------------------------------------------------------------

  /// Inserta un nodo o, si ya existe, actualiza su nombre y umbral (upsert).
  ///
  /// OJO: aquí NO se usa `ConflictAlgorithm.replace`. En SQLite, REPLACE
  /// borra la fila vieja y mete una nueva; ese borrado dispara el
  /// `ON DELETE CASCADE` y se lleva todas las lecturas del nodo.
  /// `ON CONFLICT DO UPDATE` actualiza la fila sin borrarla.
  Future<int> insertNode(String id, String name,
      {double tempThreshold = defaultTempThreshold}) async {
    final db = await instance.database;
    return await db.rawInsert(
      'INSERT INTO nodes (id, name, temp_threshold) VALUES (?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
      'temp_threshold = excluded.temp_threshold',
      [id, name, tempThreshold],
    );
  }

  /// Umbral de temperatura configurado para un nodo (o el de por defecto).
  Future<double> getThreshold(String nodeId) async {
    final db = await instance.database;
    final rows = await db.query(
      'nodes',
      columns: ['temp_threshold'],
      where: 'id = ?',
      whereArgs: [nodeId],
    );
    if (rows.isEmpty) return defaultTempThreshold;
    return (rows.first['temp_threshold'] as num).toDouble();
  }

  /// Cambia el umbral de temperatura de todos los nodos (configurable desde
  /// el histórico). Aplica a las lecturas que lleguen después.
  Future<int> setThresholdForAll(double threshold) async {
    final db = await instance.database;
    return await db.update('nodes', {'temp_threshold': threshold});
  }

  /// Crea el nodo solo si no existe (no toca su nombre ni su umbral).
  Future<void> ensureNode(String id) async {
    final db = await instance.database;
    await db.insert('nodes', {'id': id, 'name': id},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Borra un nodo. Por el `ON DELETE CASCADE` también se borran sus lecturas.
  Future<int> deleteNode(String id) async {
    final db = await instance.database;
    return await db.delete('nodes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Lecturas: CRUD
  // ---------------------------------------------------------------------------

  /// CREATE. Inserción parametrizada para PREVENIR SQL Injection.
  /// Si `node_id` no existe en `nodes`, SQLite lanza un error de FOREIGN KEY.
  Future<int> insertReading(SensorReading reading) async {
    final db = await instance.database;
    final map = reading.toMap()..remove('id');
    return await db.insert('readings', map);
  }

  /// CREATE masivo: todas las lecturas en UNA transacción y UN batch.
  ///
  /// - `db.transaction`: o entran todas o no entra ninguna (ACID).
  /// - `batch`: las sentencias se mandan juntas al motor nativo en vez de ir
  ///   y venir una por una entre Dart y Android, así la UI no se traba.
  /// - `ignoreDuplicates`: si el `uuid` ya existe se salta la fila (se usa al
  ///   importar un CSV para no duplicar).
  /// Regresa cuántas filas se insertaron de verdad.
  Future<int> insertBatchReadings(List<SensorReading> readings,
      {bool ignoreDuplicates = false}) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      Future<int> count() async =>
          Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM readings')) ??
          0;
      final before = await count();
      final batch = txn.batch();
      for (final reading in readings) {
        batch.insert(
          'readings',
          reading.toMap()..remove('id'),
          conflictAlgorithm:
              ignoreDuplicates ? ConflictAlgorithm.ignore : ConflictAlgorithm.abort,
        );
      }
      await batch.commit(noResult: true);
      return await count() - before;
    });
  }

  /// UPDATE. Al editar una lectura se marca como no sincronizada y se
  /// actualiza `updated_at` (lo necesita la sincronización de la Actividad 4).
  Future<int> updateReading(SensorReading reading) async {
    final db = await instance.database;
    final threshold = await getThreshold(reading.nodeId);
    final updated = reading.copyWith(
      isAlert: reading.sensorType == 'temperature' && reading.value > threshold,
      synced: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    return await db.update(
      'readings',
      updated.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [reading.id],
    );
  }

  /// DELETE de una lectura por su id.
  Future<int> deleteReading(int id) async {
    final db = await instance.database;
    return await db.delete('readings', where: 'id = ?', whereArgs: [id]);
  }

  /// Número de lecturas guardadas.
  Future<int> countReadings() async {
    final db = await instance.database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM readings')) ??
        0;
  }

  /// Consulta parametrizada (segura): el tipo viaja en `whereArgs`, no en el SQL.
  Future<List<SensorReading>> getReadingsByType(String type) async {
    final db = await instance.database;
    final result = await db.query(
      'readings',
      where: 'sensorType = ?',
      whereArgs: [type],
      orderBy: 'id DESC',
    );
    return result.map(SensorReading.fromMap).toList();
  }

  /// Solo las lecturas marcadas como alerta (para el filtro del histórico).
  Future<List<SensorReading>> getAlerts() async {
    final db = await instance.database;
    final result = await db.query(
      'readings',
      where: 'is_alert = ?',
      whereArgs: [1],
      orderBy: 'id DESC',
    );
    return result.map(SensorReading.fromMap).toList();
  }

  /// Todas las lecturas, de la más nueva a la más vieja.
  Future<List<SensorReading>> getAllReadings() async {
    final db = await instance.database;
    final result = await db.query('readings', orderBy: 'id DESC');
    return result.map(SensorReading.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Diagnóstico (para la pantalla Demo)
  // ---------------------------------------------------------------------------

  /// Datos para mostrar en pantalla que la base existe y está bien configurada.
  Future<Map<String, dynamic>> getDbInfo() async {
    final db = await instance.database;
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    final schema = await db.query(
      'sqlite_master',
      columns: ['name', 'sql'],
      where: 'type = ? AND name NOT LIKE ?',
      whereArgs: ['table', 'sqlite_%'],
    );
    final nodes = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM nodes'));
    final readings = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM readings'));
    final columns = await db.rawQuery('PRAGMA table_info(readings)');
    return {
      'path': await dbPath,
      'version': await db.getVersion(),
      'foreign_keys': fk.first.values.first,
      'schema': schema,
      'nodes': nodes,
      'readings': readings,
      'columns': columns.map((c) => c['name'] as String).toList(),
    };
  }
}
