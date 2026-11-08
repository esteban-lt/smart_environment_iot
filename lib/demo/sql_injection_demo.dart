import 'package:sqflite/sqflite.dart';

/// Ejercicio de Corrección de Código del Módulo 2.
///
/// Usa una base EN MEMORIA aparte (tabla `users`) para no tocar los datos
/// reales del proyecto. Sirve solo para demostrar el riesgo en la pantalla Demo.
class SqlInjectionDemo {
  late Database db;

  Future<void> open() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1,
        onCreate: (db, _) async {
      await db.execute('CREATE TABLE users (name TEXT NOT NULL)');
    });
    await db.delete('users');
  }

  // ❌ CÓDIGO CON ERRORES (tal cual el ejercicio): concatena la entrada del
  // usuario dentro del SQL. NO usar en la app real.
  Future<void> saveUserDataVulnerable(String userInput) async {
    await db.rawQuery("INSERT INTO users VALUES ('" + userInput + "')");
  }

  // ✅ CORREGIDO: el valor viaja como parámetro (`?`), nunca como parte del SQL.
  Future<void> saveUserData(String userInput) async {
    await db.insert('users', {'name': userInput});
    // Equivalente con SQL explícito:
    // await db.rawInsert('INSERT INTO users (name) VALUES (?)', [userInput]);
  }

  Future<List<String>> allUsers() async {
    final rows = await db.query('users');
    return rows.map((r) => r['name'] as String).toList();
  }
}
