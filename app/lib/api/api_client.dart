import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import 'models.dart';

/// An API error with a message that's safe to show the player.
class ApiError implements Exception {
  ApiError(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Talks to the Pep API.
///
/// Auth: the access token goes in `Authorization: Bearer …` on every call.
/// When it expires (401), we use the refresh token once to get a new pair and
/// retry the call. If that fails too, the player is logged out ([onLoggedOut]).
/// Tokens live in secure storage (Keychain on iOS, Keystore on Android,
/// browser storage on web), never in plain preferences.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _http = client ?? http.Client(),
        _store = storage ?? const FlutterSecureStorage();

  final http.Client _http;
  final FlutterSecureStorage _store;
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing; // one refresh at a time, even if several calls hit 401 together
  void Function()? onLoggedOut;

  Uri _u(String path) => Uri.parse('${AppConfig.apiUrl}$path');

  bool get loggedIn => _refresh != null;

  Future<void> loadTokens() async {
    _access = await _store.read(key: 'access');
    _refresh = await _store.read(key: 'refresh');
  }

  Future<void> _saveTokens(Map<String, dynamic> t) async {
    _access = t['accessToken'] as String;
    _refresh = t['refreshToken'] as String;
    await _store.write(key: 'access', value: _access);
    await _store.write(key: 'refresh', value: _refresh);
  }

  Future<void> clearTokens() async {
    _access = _refresh = null;
    await _store.delete(key: 'access');
    await _store.delete(key: 'refresh');
  }

  // ------------------------------------------------------------- plumbing

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_access != null) 'Authorization': 'Bearer $_access',
      };

  Future<dynamic> _send(String method, String path, {Object? body, bool auth = true}) async {
    Future<http.Response> go() {
      final req = http.Request(method, _u(path))..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      return _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    }

    http.Response res;
    try {
      res = await go();
      if (res.statusCode == 401 && auth && _refresh != null && await _tryRefresh()) {
        res = await go();
      }
    } on TimeoutException {
      throw ApiError(0, 'The connection is slow. Try again in a moment.');
    } on http.ClientException {
      throw ApiError(0, "Can't reach Tracka. Check your connection.");
    }
    return _decode(res, auth: auth);
  }

  dynamic _decode(http.Response res, {bool auth = true}) {
    if (res.statusCode == 204) return null;
    final text = utf8.decode(res.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && auth) {
      clearTokens();
      onLoggedOut?.call();
    }
    final detail = data is Map ? data['detail'] : null;
    throw ApiError(res.statusCode, detail is String ? detail : 'Something went wrong (${res.statusCode}).');
  }

  Future<bool> _tryRefresh() {
    return _refreshing ??= () async {
      try {
        final res = await _http.post(_u('/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': _refresh}));
        if (res.statusCode != 200) return false;
        await _saveTokens(jsonDecode(res.body) as Map<String, dynamic>);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  // ------------------------------------------------------------- auth

  Future<void> signUp(String email, String password) async =>
      _saveTokens(await _send('POST', '/v1/auth/signup', body: {'email': email, 'password': password}, auth: false)
          as Map<String, dynamic>);

  Future<void> logIn(String email, String password) async =>
      _saveTokens(await _send('POST', '/v1/auth/login', body: {'email': email, 'password': password}, auth: false)
          as Map<String, dynamic>);

  Future<void> logOut() async {
    try {
      if (_refresh != null) await _send('POST', '/v1/auth/logout', body: {'refreshToken': _refresh}, auth: false);
    } catch (_) {}
    await clearTokens();
  }

  // ------------------------------------------------------------- profile

  Future<Me> me() async => Me.fromJson(await _send('GET', '/v1/me') as Map<String, dynamic>);

  Future<Me> updateMe(Map<String, dynamic> changes) async =>
      Me.fromJson(await _send('PATCH', '/v1/me', body: changes) as Map<String, dynamic>);

  Future<void> deleteAccount() async {
    await _send('DELETE', '/v1/me');
    await clearTokens();
  }

  Future<Meta> meta() async => Meta.fromJson(await _send('GET', '/v1/meta', auth: false) as Map<String, dynamic>);

  // ------------------------------------------------------------- videos

  Future<List<Video>> videos() async =>
      (await _send('GET', '/v1/videos') as List).map((e) => Video.fromJson(e as Map<String, dynamic>)).toList();

  Future<Video> video(String id) async => Video.fromJson(await _send('GET', '/v1/videos/$id') as Map<String, dynamic>);

  Future<void> renameVideo(String id, String title) => _send('PATCH', '/v1/videos/$id', body: {'title': title});

  Future<void> deleteVideo(String id) => _send('DELETE', '/v1/videos/$id');

  /// Uploads a clip with progress (0..1). Streams the file: a 200 MB clip never sits in memory.
  Future<String> upload(XFile file, Map<String, dynamic> meta, {void Function(double)? onProgress}) async {
    if (_access == null) throw ApiError(401, 'Not logged in.');
    Future<http.StreamedResponse> go() async {
      final length = await file.length();
      var sent = 0;
      final stream = file.openRead().transform<List<int>>(StreamTransformer.fromHandlers(handleData: (chunk, sink) {
        sent += chunk.length;
        onProgress?.call(sent / length);
        sink.add(chunk);
      }));
      final req = http.MultipartRequest('POST', _u('/v1/videos'))
        ..headers['Authorization'] = 'Bearer $_access'
        ..fields['meta'] = jsonEncode(meta)
        ..files.add(http.MultipartFile('video', stream, length, filename: file.name.isEmpty ? 'clip.mp4' : file.name));
      return _http.send(req);
    }

    try {
      var res = await go();
      if (res.statusCode == 401 && await _tryRefresh()) res = await go();
      final data = _decode(await http.Response.fromStream(res)) as Map<String, dynamic>;
      return data['id'] as String;
    } on http.ClientException {
      throw ApiError(0, 'The upload stopped. Check your connection and try again.');
    }
  }

  // ------------------------------------------------------------- coach

  Future<CoachSummary> coach() async =>
      CoachSummary.fromJson(await _send('GET', '/v1/coach') as Map<String, dynamic>);

  Future<bool> opportunitiesComingSoon() async =>
      ((await _send('GET', '/v1/opportunities')) as Map<String, dynamic>)['comingSoon'] as bool? ?? true;
}
