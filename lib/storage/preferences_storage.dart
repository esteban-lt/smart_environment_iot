import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Ejercicio de clase 1 (Módulo 1): preferencias del usuario en un archivo
/// JSON local.
///
/// - Se guarda en el directorio de documentos privado de la app
///   (`getApplicationDocumentsDirectory()`), que en Android es
///   `/data/user/0/<paquete>/app_flutter/`.
/// - Escritura **atómica**: primero se escribe `preferencias.json.tmp` y luego
///   se renombra. Si la app se cierra a media escritura, el archivo bueno no
///   se corrompe.
/// - Todo es asíncrono (`await`), así que no bloquea el hilo de la UI.
class PreferencesStorage {
  static const fileName = 'preferencias.json';

  Future<File> get file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Guarda las preferencias. Lanza [FileSystemException] si no se puede
  /// escribir (la pantalla la atrapa y avisa con un SnackBar).
  Future<String> save(Map<String, dynamic> prefs) async {
    final target = await file;
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(prefs),
        flush: true);
    await tmp.rename(target.path);
    return target.path;
  }

  /// Lee las preferencias, o `null` si el archivo no existe o está corrupto.
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await file;
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null; // JSON mal formado
    }
  }

  /// Verificación: lo que se lee del disco es idéntico a lo que se escribió.
  Future<bool> verify(Map<String, dynamic> expected) async {
    final actual = await read();
    return actual != null && jsonEncode(actual) == jsonEncode(expected);
  }
}
