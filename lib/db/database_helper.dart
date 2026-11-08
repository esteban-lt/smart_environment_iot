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
/// Esquema v1:
/// ```
/// nodes (1) ────< (N) readings
/// ```
class DatabaseHelper {
  /// Nombre del archivo de la base de datos.
  static const String dbName = 'iot_local.db';

  /// Versión actual del esquema. Se sube a 2 en la migración de la Actividad 2.
  static const int dbVersion = 1;

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
    );
  }

  /// Se ejecuta cada vez que se abre la conexión, antes de onCreate/onUpgrade.
  /// Activa las llaves foráneas; sin esto SQLite ignora los REFERENCES.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Crea el esquema v1 la primera vez que se instala la app.
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
  }

  // ---------------------------------------------------------------------------
  // Nodos
  // ---------------------------------------------------------------------------

  /// Inserta (o reemplaza) un nodo. Parametrizado: sqflite arma el
  /// `INSERT ... VALUES (?, ?, ?)` y pasa los valores aparte.
  Future<int> insertNode(String id, String name,
      {double tempThreshold = defaultTempThreshold}) async {
    final db = await instance.database;
    return await db.insert(
      'nodes',
      {'id': id, 'name': name, 'temp_threshold': tempThreshold},
      conflictAlgorithm: ConflictAlgorithm.replace,
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

  // ---------------------------------------------------------------------------
  // Lecturas
  // ---------------------------------------------------------------------------

  /// Inserción parametrizada para PREVENIR SQL Injection.
  /// Si `node_id` no existe en `nodes`, SQLite lanza un error de FOREIGN KEY.
  Future<int> insertReading(SensorReading reading) async {
    final db = await instance.database;
    final map = reading.toMap()..remove('id');
    return await db.insert('readings', map);
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
    return {
      'path': await dbPath,
      'version': await db.getVersion(),
      'foreign_keys': fk.first.values.first,
      'schema': schema,
      'nodes': nodes,
      'readings': readings,
    };
  }
}
