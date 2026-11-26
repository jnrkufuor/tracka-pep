/// Build-time settings. Pass them with --dart-define, e.g.
///   flutter run --dart-define=PEP_API_URL=http://10.0.2.2:8000     (Android emulator → your laptop)
///   flutter build web --dart-define=PEP_API_URL=https://api.tracka.app
class AppConfig {
  static const apiUrl = String.fromEnvironment('PEP_API_URL', defaultValue: 'http://localhost:8000');

  /// Shown in Help and sent with crash reports and feedback. CI sets it from pubspec.yaml.
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// Screenshot mode, for CI only (.github/workflows/screenshots.yml): log in as a demo
  /// player automatically. Empty in every real build.
  static const demoEmail = String.fromEnvironment('PEP_DEMO_EMAIL');
  static const demoPassword = String.fromEnvironment('PEP_DEMO_PASSWORD');
  static bool get demo => demoEmail.isNotEmpty;

  /// In screenshot mode, the page's URL can pick what to show: ?tab=2, ?video=<id>, ?welcome=1.
  static String? param(String key) => demo ? Uri.base.queryParameters[key] : null;
}
