import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import 'net.dart';
import 'push.dart';
import 'upload_queue.dart';

enum Stage { starting, signedOut, onboarding, ready }

/// The whole app's state in one ChangeNotifier (the same pattern YesBut uses).
///
/// Screens read it with `context.watch<AppState>()` and call its methods; it
/// talks to the API and calls `notifyListeners()` so the screens rebuild.
/// One place owns the data, so two screens can never disagree about it.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api, NetCheck? net})
      : api = api ?? ApiClient(),
        net = net ?? DeviceNet() {
    this.api.onLoggedOut = _signedOut;
    this.api.offline.addListener(notifyListeners);
    queue = UploadQueue(
      upload: (file, meta, onProgress) => this.api.upload(file, meta, onProgress: onProgress),
      net: this.net,
      store: this.api.cache,
      wifiOnly: () => settings.uploadOnWifiOnly,
      needsGuardian: () => me?.needsGuardian ?? false,
      onUploaded: (_) => refresh(),
      exists: (path) async {
        try {
          return await XFile(path).length() > 0;
        } catch (_) {
          return false;
        }
      },
    )..addListener(notifyListeners);
    _netSub = this.net.changes.listen((n) {
      if (n != Net.offline && offline && stage == Stage.ready) refresh();
    });
  }

  final ApiClient api;
  final NetCheck net;
  late final UploadQueue queue;
  StreamSubscription<Net>? _netSub;

  /// The last call couldn't reach Tracka: screens are showing saved copies.
  bool get offline => api.offline.value;
  Stage stage = Stage.starting;
  Me? me;
  Meta? meta;
  List<Video> videos = [];
  CoachSummary? coach;

  /// This week's plan (football + Pep sessions + tests) and how the body feels.
  Week? week;
  HealthState? health;
  bool loadingVideos = false;

  /// Pep's tour ("Show me around") is showing over Home.
  bool tourPending = false;

  void startTour() {
    tourPending = true;
    notifyListeners();
  }

  void endTour() {
    tourPending = false;
    notifyListeners();
    saveSettings({'tourSeen': true}).catchError((_) {});
  }

  /// Unread notifications (the dot on the bell).
  int unread = 0;
  String? error;

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
    await queue.load();
    if (stage == Stage.ready) await refresh();
    unawaited(Push.start(api, onOpen: (data) => onPushOpened?.call(data), onMessage: loadUnread));
  }

  Future<void> signUp(String email, String password) async {
    await api.signUp(email, password);
    await _afterLogin();
  }

  Future<void> logIn(String email, String password) async {
    await api.logIn(email, password);
    await _afterLogin();
  }

  /// Set by the app: open the screen a tapped push is about.
  void Function(Map<String, dynamic>)? onPushOpened;

  Future<void> logOut() async {
    await Push.stop(api);
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

  Future<void> loadUnread() async {
    try {
      unread = (await api.notifications()).unread;
      notifyListeners();
    } catch (_) {}
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
    queue.items.clear();
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
      final results = await Future.wait([api.videos(), api.coach(), api.me()]);
      videos = results[0] as List<Video>;
      coach = results[1] as CoachSummary;
      me = results[2] as Me;
      error = null;
      await loadWeek();
      unawaited(queue.pump(retryFailed: true)); // e.g. the guardian just said yes
      unawaited(loadUnread());
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

  /// Add a clip to the upload queue (it goes now, or when it can).
  Future<String> upload(XFile file, Map<String, dynamic> meta) => queue.add(file, meta);

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
    _netSub?.cancel();
    queue.dispose();
    _poll?.cancel();
    super.dispose();
  }
}
