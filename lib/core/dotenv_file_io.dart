import 'dart:io';

import 'dotenv_asset.dart';

/// Desktop / native IO: read and write the checkout-root `.env` when present.
class DotEnvFile {
  DotEnvFile._();

  /// True when a project root with `pubspec.yaml` can be resolved.
  static bool get canWrite => _resolveProjectRoot() != null;

  /// Reads the live `.env` text from the project root, if found.
  static Future<String?> readRaw() async {
    final file = await _resolveEnvFile(createIfMissing: false);
    if (file == null || !await file.exists()) return null;
    return file.readAsString();
  }

  /// Overwrites the project `.env`. Creates from `.env.example` if needed.
  static Future<bool> writeRaw(String contents) async {
    final file = await _resolveEnvFile(createIfMissing: true);
    if (file == null) return false;
    await file.writeAsString(contents);
    return true;
  }

  /// Upserts [updates] into the project `.env` (best-effort).
  static Future<bool> upsertValues(Map<String, String> updates) async {
    if (updates.isEmpty) return true;
    final file = await _resolveEnvFile(createIfMissing: true);
    if (file == null) return false;
    final raw = await file.exists() ? await file.readAsString() : '';
    final next = DotEnvAsset.upsert(raw, updates);
    await file.writeAsString(next);
    return true;
  }

  static Directory? _resolveProjectRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final pubspec = File('${dir.path}/pubspec.yaml');
      if (pubspec.existsSync()) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static Future<File?> _resolveEnvFile({required bool createIfMissing}) async {
    final root = _resolveProjectRoot();
    if (root == null) return null;
    final env = File('${root.path}/.env');
    if (await env.exists()) return env;
    if (!createIfMissing) return null;

    final example = File('${root.path}/.env.example');
    if (await example.exists()) {
      await example.copy(env.path);
    } else {
      await env.writeAsString('');
    }
    return env;
  }
}
