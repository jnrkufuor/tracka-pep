/// Build-time settings. Pass them with --dart-define, e.g.
///   flutter run --dart-define=PEP_API_URL=http://10.0.2.2:8000     (Android emulator → your laptop)
///   flutter build web --dart-define=PEP_API_URL=https://api.tracka.app
class AppConfig {
  static const apiUrl = String.fromEnvironment('PEP_API_URL', defaultValue: 'http://localhost:8000');
}
