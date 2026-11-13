/// Web / non-IO stub: no filesystem config path.
class UserConfigFile {
  UserConfigFile._();

  /// Always false on platforms without dart:io filesystem access.
  static bool get supportsFilesystem => false;

  /// No default path on this platform.
  static Future<String?> defaultPath() async => null;

  /// No-op.
  static Future<String?> read(String path) async => null;

  /// No-op; returns false.
  static Future<bool> write(String path, String contents) async => false;

  /// No-op; returns false.
  static Future<bool> copy(String fromPath, String toPath) async => false;
}
