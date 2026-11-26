import 'package:shared_preferences/shared_preferences.dart';

/// Saved copies of the last good answers from the API, so the app can show
/// something useful offline ("You're offline. Showing what's saved.").
///
/// This is a CACHE: a copy that may be out of date, used only when the real
/// thing can't be reached. It's cleared on log out, and never holds tokens.
abstract class ResponseCache {
  Future<String?> get(String key);
  Future<void> put(String key, String value);
  Future<void> clear();
}

/// The phone's preferences store (web: browser storage).
class PrefsCache implements ResponseCache {
  static const _prefix = 'cache:';

  @override
  Future<String?> get(String key) async => (await SharedPreferences.getInstance()).getString('$_prefix$key');

  @override
  Future<void> put(String key, String value) async => (await SharedPreferences.getInstance()).setString('$_prefix$key', value);

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}

/// For tests.
class MemoryCache implements ResponseCache {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> put(String key, String value) async => data[key] = value;

  @override
  Future<void> clear() async => data.clear();
}
