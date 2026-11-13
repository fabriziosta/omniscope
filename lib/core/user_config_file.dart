/// Portable read/write for the omniscope.json user config file.
///
/// On IO platforms this uses the filesystem. On Web the implementation is a
/// no-op stub — [UserConfigStore] falls back to a prefs blob.
library;

export 'user_config_file_stub.dart'
    if (dart.library.io) 'user_config_file_io.dart';
