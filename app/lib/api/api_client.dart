import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import 'cache.dart';
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
///
/// Offline: answers to the GETs in [_cached] are saved ([ResponseCache]). If the
/// network is down, the saved copy is returned instead and [offline] turns true,
/// so screens show what they last saw with a "You're offline" note.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage, ResponseCache? cache})
      : _http = client ?? http.Client(),
        _store = storage ?? const FlutterSecureStorage(),
        cache = cache ?? PrefsCache();

  final http.Client _http;
  final FlutterSecureStorage _store;
  final ResponseCache cache;

  /// True while the last call couldn't reach Tracka and a saved copy was shown.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  static const _cached = ['/v1/me', '/v1/meta', '/v1/videos', '/v1/coach', '/v1/week', '/v1/health', '/v1/tips', '/v1/card', '/v1/guardian', '/v1/challenges', '/v1/pitches', '/v1/notifications', '/v1/focus', '/v1/progress'];
  static bool _cacheable(String method, String path) => method == 'GET' && _cached.any((p) => path == p || path.startsWith('$p?'));
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

    final save = _cacheable(method, path);
    http.Response res;
    try {
      res = await go();
      if (res.statusCode == 401 && auth && _refresh != null && await _tryRefresh()) {
        res = await go();
      }
    } on TimeoutException {
      return _fromCache(path, save, ApiError(0, 'The connection is slow. Try again in a moment.'));
    } on http.ClientException {
      return _fromCache(path, save, ApiError(0, "Can't reach Tracka. Check your connection."));
    }
    offline.value = false;
    if (save && res.statusCode == 200) unawaited(cache.put(path, utf8.decode(res.bodyBytes)));
    return _decode(res, auth: auth);
  }

  Future<dynamic> _fromCache(String path, bool cacheable, ApiError error) async {
    final saved = cacheable ? await cache.get(path) : null;
    if (saved == null) throw error;
    offline.value = true;
    return jsonDecode(saved);
  }

  dynamic _decode(http.Response res, {bool auth = true}) {
    if (res.statusCode == 204) return null;
    final text = utf8.decode(res.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && auth) {
      clearTokens();
      cache.clear();
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
    await cache.clear(); // saved screens and the upload queue belong to this player
  }

  // ------------------------------------------------------------- profile

  Future<Me> me() async => Me.fromJson(await _send('GET', '/v1/me') as Map<String, dynamic>);

  Future<Me> updateMe(Map<String, dynamic> changes) async =>
      Me.fromJson(await _send('PATCH', '/v1/me', body: changes) as Map<String, dynamic>);

  Future<void> deleteAccount() async {
    await _send('DELETE', '/v1/me');
    await clearTokens();
    await cache.clear();
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

  Future<ProgressState> progress() async => ProgressState.fromJson(await _send('GET', '/v1/progress') as Map<String, dynamic>);

  Future<FocusState> focus() async => FocusState.fromJson(await _send('GET', '/v1/focus') as Map<String, dynamic>);

  // ------------------------------------------------------------- notifications

  Future<({List<AppNotification> items, int unread, bool quietNow})> notifications() async {
    final j = await _send('GET', '/v1/notifications') as Map<String, dynamic>;
    return (
      items: [for (final n in j['items'] as List) AppNotification.fromJson(n as Map<String, dynamic>)],
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      quietNow: j['quietNow'] as bool? ?? false,
    );
  }

  /// Mark these read, or all of them when [ids] is null.
  Future<void> markRead([List<String>? ids]) => _send('POST', '/v1/notifications/read', body: {if (ids != null) 'ids': ids});

  // ------------------------------------------------------------- pitchside

  Future<({List<FeedPost> posts, bool canPost})> feed({String tab = 'for_you'}) async {
    final j = await _send('GET', '/v1/feed?tab=$tab') as Map<String, dynamic>;
    return (posts: [for (final p in j['posts'] as List) FeedPost.fromJson(p as Map<String, dynamic>)], canPost: j['canPost'] as bool? ?? false);
  }

  Future<FeedPost> post(String videoId, {String caption = ''}) async =>
      FeedPost.fromJson(await _send('POST', '/v1/posts', body: {'videoId': videoId, 'caption': caption}) as Map<String, dynamic>);

  Future<void> deletePost(String id) => _send('DELETE', '/v1/posts/$id');
  Future<void> respect(String id, bool on) => _send(on ? 'PUT' : 'DELETE', '/v1/posts/$id/respect');
  Future<void> savePost(String id, bool on) => _send(on ? 'PUT' : 'DELETE', '/v1/posts/$id/save');
  Future<void> report(String id, String reason) => _send('POST', '/v1/posts/$id/report', body: {'reason': reason});

  Future<({List<FeedAuthor> players, List<FeedAuthor> nearYou})> searchPlayers(String q) async {
    final j = await _send('GET', '/v1/players?q=${Uri.encodeQueryComponent(q)}') as Map<String, dynamic>;
    return (
      players: [for (final p in j['players'] as List) FeedAuthor.fromJson(p as Map<String, dynamic>)],
      nearYou: [for (final p in j['nearYou'] as List) FeedAuthor.fromJson(p as Map<String, dynamic>)],
    );
  }

  Future<PlayerPage> player(String id) async => PlayerPage.fromJson(await _send('GET', '/v1/players/$id') as Map<String, dynamic>);
  Future<void> follow(String id, bool on) => _send(on ? 'PUT' : 'DELETE', '/v1/players/$id/follow');
  Future<void> block(String id, bool on) => _send(on ? 'PUT' : 'DELETE', '/v1/players/$id/block');

  Future<ChallengesState> challenges() async => ChallengesState.fromJson(await _send('GET', '/v1/challenges') as Map<String, dynamic>);

  Future<List<Pitch>> pitches() async =>
      [for (final p in ((await _send('GET', '/v1/pitches') as Map)['pitches'] as List)) Pitch.fromJson(p as Map<String, dynamic>)];

  Future<List<Pitch>> addPitch({required String name, required String surface, required String size, required String town}) async => [
        for (final p in ((await _send('POST', '/v1/pitches', body: {'name': name, 'surface': surface, 'size': size, 'town': town}) as Map)['pitches'] as List))
          Pitch.fromJson(p as Map<String, dynamic>)
      ];

  Future<List<Pitch>> confirmPitch(String id) async =>
      [for (final p in ((await _send('PUT', '/v1/pitches/$id/confirm') as Map)['pitches'] as List)) Pitch.fromJson(p as Map<String, dynamic>)];

  // ------------------------------------------------------------- card

  Future<CardState> card() async => CardState.fromJson(await _send('GET', '/v1/card') as Map<String, dynamic>);

  Future<CardState> setCardLink(bool on, {bool newLink = false}) async =>
      CardState.fromJson(await _send('PUT', '/v1/card/link', body: {'on': on, 'newLink': newLink}) as Map<String, dynamic>);

  Future<CardState> updateCard({Map<String, bool>? show, List<String>? portfolio}) async =>
      CardState.fromJson(await _send('PATCH', '/v1/card', body: {
        if (show != null) 'show': show,
        if (portfolio != null) 'portfolio': portfolio,
      }) as Map<String, dynamic>);

  // ------------------------------------------------------------- guardian

  Future<GuardianState> guardian() async =>
      GuardianState.fromJson(await _send('GET', '/v1/guardian') as Map<String, dynamic>);

  Future<GuardianState> setGuardian({required String phone, String? relation, String? name}) async =>
      GuardianState.fromJson(await _send('PUT', '/v1/guardian', body: {
        'phone': phone,
        if (relation != null) 'relation': relation,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }) as Map<String, dynamic>);

  Future<GuardianState> resendGuardian() async =>
      GuardianState.fromJson(await _send('POST', '/v1/guardian/resend') as Map<String, dynamic>);

  /// Ask the guardian for something new: post | share_card | search.
  Future<GuardianState> askGuardian(String kind) async =>
      GuardianState.fromJson(await _send('POST', '/v1/guardian/requests', body: {'kind': kind}) as Map<String, dynamic>);

  Future<List<ReviewTip>> tips() async =>
      [for (final t in await _send('GET', '/v1/tips') as List) ReviewTip.fromJson(t as Map<String, dynamic>)];

  Future<CoachSummary> coach() async =>
      CoachSummary.fromJson(await _send('GET', '/v1/coach') as Map<String, dynamic>);

  Future<bool> opportunitiesComingSoon() async =>
      ((await _send('GET', '/v1/opportunities')) as Map<String, dynamic>)['comingSoon'] as bool? ?? true;

  // ---------------------------------------------------------------- training

  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Week> week({DateTime? start}) async =>
      Week.fromJson(await _send('GET', start == null ? '/v1/week' : '/v1/week?start=${_d(start)}') as Map<String, dynamic>);

  Future<SessionPlan> session(String key) async =>
      SessionPlan.fromJson(await _send('GET', '/v1/sessions/$key') as Map<String, dynamic>);

  Future<Week> moveSession(String key, DateTime to) async =>
      Week.fromJson(await _send('POST', '/v1/sessions/$key/move', body: {'to': _d(to)}) as Map<String, dynamic>);

  Future<Week> skipSession(String key) async =>
      Week.fromJson(await _send('POST', '/v1/sessions/$key/skip') as Map<String, dynamic>);

  Future<Week> restoreSession(String key) async =>
      Week.fromJson(await _send('POST', '/v1/sessions/$key/restore') as Map<String, dynamic>);

  /// Log a finished session. Returns the follow-up line to show.
  Future<String> finishSession(String key, {required String effort, required bool hurt}) async {
    final r = await _send('POST', '/v1/sessions/$key/done', body: {'effort': effort, 'hurt': hurt}) as Map<String, dynamic>;
    return r['next'] as String? ?? '';
  }

  Future<List<FootballEvent>> events() async =>
      (await _send('GET', '/v1/events') as List).map((e) => FootballEvent.fromJson(e as Map<String, dynamic>)).toList();

  Future<FootballEvent> addEvent(Map<String, dynamic> body) async =>
      FootballEvent.fromJson(await _send('POST', '/v1/events', body: body) as Map<String, dynamic>);

  Future<FootballEvent> updateEvent(String id, Map<String, dynamic> body) async =>
      FootballEvent.fromJson(await _send('PATCH', '/v1/events/$id', body: body) as Map<String, dynamic>);

  Future<void> deleteEvent(String id) => _send('DELETE', '/v1/events/$id');

  Future<HealthState> health() async => HealthState.fromJson(await _send('GET', '/v1/health') as Map<String, dynamic>);

  Future<HealthState> setHealth(String status, {String? area}) async =>
      HealthState.fromJson(await _send('PUT', '/v1/health', body: {'status': status, 'area': area}) as Map<String, dynamic>);
}
