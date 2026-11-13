/// Portable access to the checkout-root `.env` file.
///
/// On desktop/native IO platforms this reads/writes the real project `.env`
/// (for Python CLI sync). On Web the implementation is a no-op stub.
library;

export 'dotenv_file_stub.dart'
    if (dart.library.io) 'dotenv_file_io.dart';
