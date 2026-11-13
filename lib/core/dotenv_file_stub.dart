/// Web / non-IO stub: project `.env` cannot be written at runtime.
class DotEnvFile {
  DotEnvFile._();

  /// Always false on platforms without a project filesystem.
  static bool get canWrite => false;

  /// No project `.env` on this platform.
  static Future<String?> readRaw() async => null;

  /// No-op; returns false.
  static Future<bool> writeRaw(String contents) async => false;

  /// No-op; returns false.
  static Future<bool> upsertValues(Map<String, String> updates) async => false;
}
