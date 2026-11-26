import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config.dart';

/// Sends the app's crashes to Tracka's own API, so a broken screen gets fixed.
///
/// WHY OUR OWN API AND NOT A CRASH SDK: most players are children. A crash SDK
/// sends data from the phone straight to another company and has to be listed
/// in the store privacy forms. Here the report goes to `POST /v1/app-errors`
/// (pep/players/app_errors.py), which hides emails and phone numbers and only
/// then, if staff switched it on, forwards it to the error tracker.
///
/// What is sent: the error, the stack trace, the app version and the platform.
/// Never what the player typed, their clips or their name.
///
/// Two places catch errors in Flutter (handbook chapter 10, "Observability"):
///  - [FlutterError.onError]: errors while building or drawing a screen;
///  - [PlatformDispatcher.onError]: everything else, like a failed `await`
///    nobody caught.
/// Each different error is sent once per session, and at most [maxPerSession],
/// so a crash that repeats every frame doesn't flood anyone.
class CrashReport {
  CrashReport._();

  static const maxPerSession = 10;
  static final _sent = <String>{};
  static ApiClient? _api;

  /// Hook into Flutter's error handlers. Debug builds only print, as before.
  static void install(ApiClient api) {
    _api = api;
    if (!kReleaseMode) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      send(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      send(error, stack);
      return true; // handled: keep the app running
    };
  }

  /// Report one error. Safe to call from anywhere; never throws.
  static void send(Object error, StackTrace? stack) {
    final api = _api;
    if (api == null || _sent.length >= maxPerSession) return;
    final message = '$error';
    final top = (stack?.toString() ?? '').split('\n').take(3).join('\n');
    if (!_sent.add('$message\n$top')) return;
    unawaited(api
        .reportError(
          message: message.length > 2000 ? message.substring(0, 2000) : message,
          stack: stack?.toString(),
          appVersion: AppConfig.version,
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        )
        .catchError((_) {}));
  }

  @visibleForTesting
  static void reset() => _sent.clear();
}
