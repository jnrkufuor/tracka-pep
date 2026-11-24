import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';

enum Stage { starting, signedOut, onboarding, ready }

/// The whole app's state in one ChangeNotifier (the same pattern YesBut uses).
///
/// Screens read it with `context.watch<AppState>()` and call its methods; it
/// talks to the API and calls `notifyListeners()` so the screens rebuild.
/// One place owns the data, so two screens can never disagree about it.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    this.api.onLoggedOut = _signedOut;
  }

  final ApiClient api;
  Stage stage = Stage.starting;
  Me? me;
  Meta? meta;
  List<Video> videos = [];
  CoachSummary? coach;

  /// This week's plan (football + Pep sessions + tests) and how the body feels.
  Week? week;
  HealthState? health;
  bool loadingVideos = false;
  String? error;

  /// Uploads in progress: local id → progress 0..1.
  final Map<String, double> uploads = {};
  Timer? _poll;

  AppSettings get settings => me?.settings ?? AppSettings();

  Future<void> start() async {
    try {
      meta = await api.meta();
    } catch (e) {
      error = '$e';
    }
    await api.loadTokens();
    if (!api.loggedIn && AppConfig.demo && AppConfig.param('welcome') == null) {
      try {
        await api.logIn(AppConfig.demoEmail, AppConfig.demoPassword);
      } catch (_) {}
    }
    if (!api.loggedIn) {
      stage = Stage.signedOut;
      notifyListeners();
      return;
    }
    try {
      await _afterLogin();
    } catch (_) {
      stage = Stage.signedOut;
      notifyListeners();
    }
  }

  Future<void> _afterLogin() async {
    me = await api.me();
    meta ??= await api.meta();
    stage = me!.profileComplete ? Stage.ready : Stage.onboarding;
    notifyListeners();
    if (stage == Stage.ready) await refresh();
  }

  Future<void> signUp(String email, String password) async {
    await api.signUp(email, password);
    await _afterLogin();
  }

  Future<void> logIn(String email, String password) async {
    await api.logIn(email, password);
    await _afterLogin();
  }

  Future<void> logOut() async {
    await api.logOut();
    _signedOut();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    _signedOut();
  }

  /// Reload the week and health. Never fatal: an older server without these
  /// routes just leaves them empty, and the rest of the app keeps working.
  Future<void> loadWeek() async {
    try {
      final r = await Future.wait([api.week(), api.health()]);
      week = r[0] as Week;
      health = r[1] as HealthState;
    } catch (_) {
      // keep whatever we had
    }
    notifyListeners();
  }

  /// Apply a change the server answered with a new week (move, skip, restore).
  void setWeek(Week w) {
    week = w;
    notifyListeners();
  }

  Future<void> setHealth(String status, {String? area}) async {
    health = await api.setHealth(status, area: area);
    await loadWeek();
  }

  void _signedOut() {
    _poll?.cancel();
    week = null;
    health = null;
    me = null;
    videos = [];
    coach = null;
    stage = Stage.signedOut;
    notifyListeners();
  }

  /// Save profile changes. During onboarding, [finish] false keeps the player
  /// on the onboarding screens (for the "All set" page); call [finishOnboarding] after.
  Future<void> saveProfile(Map<String, dynamic> changes, {bool finish = true}) async {
    me = await api.updateMe(changes);
    if (stage == Stage.onboarding && me!.profileComplete && finish) {
      stage = Stage.ready;
      notifyListeners();
      await refresh();
    }
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    if (stage != Stage.onboarding || me?.profileComplete != true) return;
    stage = Stage.ready;
    notifyListeners();
    await refresh();
  }

  Future<void> saveSettings(Map<String, dynamic> changes) async {
    me = await api.updateMe({'settings': changes});
    notifyListeners();
  }

  /// Reload the library and the coach summary.
  Future<void> refresh() async {
    loadingVideos = true;
    notifyListeners();
    try {
      final results = await Future.wait([api.videos(), api.coach()]);
      videos = results[0] as List<Video>;
      coach = results[1] as CoachSummary;
      error = null;
      await loadWeek();
    } catch (e) {
      error = '$e';
    } finally {
      loadingVideos = false;
      notifyListeners();
      _schedulePoll();
    }
  }

  /// While a clip is being analysed, check every 6 seconds; stop when nothing is processing.
  void _schedulePoll() {
    _poll?.cancel();
    if (videos.any((v) => v.processing)) {
      _poll = Timer(const Duration(seconds: 6), refresh);
    }
  }

  Future<String> upload(XFile file, Map<String, dynamic> meta, {void Function(double)? onProgress}) async {
    final local = DateTime.now().microsecondsSinceEpoch.toString();
    uploads[local] = 0;
    notifyListeners();
    try {
      final id = await api.upload(file, meta, onProgress: (p) {
        uploads[local] = p;
        onProgress?.call(p);
        notifyListeners();
      });
      await refresh();
      return id;
    } finally {
      uploads.remove(local);
      notifyListeners();
    }
  }

  Future<void> deleteVideo(String id) async {
    await api.deleteVideo(id);
    videos.removeWhere((v) => v.id == id);
    notifyListeners();
    await refresh();
  }

  Future<void> renameVideo(String id, String title) async {
    await api.renameVideo(id, title);
    await refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
