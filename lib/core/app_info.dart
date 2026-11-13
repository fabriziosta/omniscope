/// App identity for Settings → About.
///
/// [version] is `MAJOR.MINOR.PATCH+SHORTSHA` (7-char commit). The `X.Y.Z` part
/// must match `pubspec.yaml`; the `+BUILD` in pubspec stays numeric for stores.
/// Patch bumps: `make bump-patch` / CI on push to `main`.
abstract final class AppInfo {
  static const name = 'Omniscope';
  static const version = '1.0.3+739978a';
}
