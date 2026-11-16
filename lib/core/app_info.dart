/// App identity shown in Settings (sidebar version footer).
///
/// [version] is the same `MAJOR.MINOR.PATCH+BUILD` string as `pubspec.yaml`
/// (`BUILD` is numeric for Android `versionCode` / iOS). Keep them in sync via
/// `make bump-patch` / CI on push to `main` — do not hand-edit this alone.
abstract final class AppInfo {
  static const name = 'Omniscope';
  static const version = '1.0.8+9';
}
