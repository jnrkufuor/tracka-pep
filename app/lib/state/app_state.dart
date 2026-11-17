import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';

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

  void _signedOut() {
    _poll?.cancel();
    me = null;
    videos = [];
    coach = null;
    stage = Stage.signedOut;
    notifyListeners();
  }

  Future<void> saveProfile(Map<String, dynamic> changes) async {
    me = await api.updateMe(changes);
    if (stage == Stage.onboarding && me!.profileComplete) {
      stage = Stage.ready;
      notifyListeners();
      await refresh();
    }
    notifyListeners();
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
