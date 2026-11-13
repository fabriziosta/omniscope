/// App identity for Settings → About.
///
/// Keep [version] in sync with the `X.Y.Z` part of `pubspec.yaml`.
/// Patch bumps: `make bump-patch` / CI on push to `main`.
/// Major / minor: edit both files manually.
abstract final class AppInfo {
  static const name = 'Omniscope';
  static const version = '1.0.0';
}
