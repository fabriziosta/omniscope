import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Desktop / native IO: read and write omniscope.json on disk.
class UserConfigFile {
  UserConfigFile._();

  static bool get supportsFilesystem => true;

  /// `{applicationSupport}/omniscope.json`.
  static Future<String?> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}omniscope.json';
  }

  static Future<String?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<bool> write(String path, String contents) async {
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(contents);
    return true;
  }

  static Future<bool> copy(String fromPath, String toPath) async {
    final from = File(fromPath);
    if (!await from.exists()) return false;
    final to = File(toPath);
    final parent = to.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await from.copy(toPath);
    return true;
  }
}
