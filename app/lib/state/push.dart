import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// Firebase settings, passed at build time (never in git):
///   flutter build apk --dart-define=FCM_API_KEY=… --dart-define=FCM_APP_ID_ANDROID=…
///     --dart-define=FCM_SENDER_ID=… --dart-define=FCM_PROJECT_ID=…
/// Without them push is simply off and the bell still works. See docs/PUSH_SETUP.md.
class PushConfig {
  static const apiKey = String.fromEnvironment('FCM_API_KEY');
  static const appIdAndroid = String.fromEnvironment('FCM_APP_ID_ANDROID');
  static const appIdIos = String.fromEnvironment('FCM_APP_ID_IOS');
  static const senderId = String.fromEnvironment('FCM_SENDER_ID');
  static const projectId = String.fromEnvironment('FCM_PROJECT_ID');

  static String get appId => defaultTargetPlatform == TargetPlatform.iOS ? appIdIos : appIdAndroid;
  static bool get ready => !kIsWeb && apiKey.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty && appId.isNotEmpty;
}

/// Push notifications on the phone (the server side is pep/players/push.py).
///
/// 1. Start Firebase with the settings above (no google-services.json needed).
/// 2. Ask the player if Tracka may send notifications (Android 13+ and iOS ask).
/// 3. Send the phone's token to Tracka (PUT /v1/devices), and again when it changes.
/// 4. When a push is tapped, open what it's about ([onOpen] gets its data).
class Push {
  static String? _token;
  static StreamSubscription<String>? _refresh;
  static bool _started = false;

  static String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  static Future<void> start(ApiClient api, {required void Function(Map<String, dynamic>) onOpen, VoidCallback? onMessage}) async {
    if (!PushConfig.ready || _started) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: PushConfig.apiKey,
            appId: PushConfig.appId,
            messagingSenderId: PushConfig.senderId,
            projectId: PushConfig.projectId,
          ),
        );
      }
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      _token = await m.getToken();
      if (_token != null) await api.registerDevice(_token!, _platform);
      _refresh = m.onTokenRefresh.listen((t) {
        _token = t;
        api.registerDevice(t, _platform).catchError((_) {});
      });
      FirebaseMessaging.onMessage.listen((_) => onMessage?.call()); // app open: update the bell
      FirebaseMessaging.onMessageOpenedApp.listen((msg) => onOpen(msg.data));
      final first = await m.getInitialMessage(); // the app was opened by tapping a push
      if (first != null) onOpen(first.data);
    } catch (_) {
      // Push is an extra: the bell has everything.
    }
  }

  /// Log out: stop pushes to this phone for this player.
  static Future<void> stop(ApiClient api) async {
    final t = _token;
    _refresh?.cancel();
    _refresh = null;
    _started = false;
    _token = null;
    if (t != null) await api.unregisterDevice(t).catchError((_) {});
  }
}
