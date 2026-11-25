import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/cache.dart';
import 'net.dart';

/// Where one clip is in the queue (canvas: Uploads).
enum UploadStatus {
  waitingWifi, // "48 MB · waiting for Wi-Fi"
  waitingOnline, // offline: goes when you're back
  waitingGuardian, // under 18: goes once your guardian says yes
  uploading,
  failed, // "Stopped: the connection dropped" (or the server said no)
  done, // "Uploaded · Pep is watching it"
}

class UploadItem {
  UploadItem({
    required this.id,
    required this.path,
    required this.name,
    required this.bytes,
    required this.meta,
    required this.createdAt,
    this.status = UploadStatus.waitingOnline,
    this.progress = 0,
    this.error,
    this.retryable = true,
    this.mobileOk = false,
    this.videoId,
  });

  final String id; // also sent as clientId, so a retry never makes two clips
  final String path; // where the clip is on the phone (image_picker's copy)
  final String name;
  final int bytes;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  UploadStatus status;
  double progress;
  String? error;
  bool retryable; // a dropped connection is; "this file is empty" isn't
  bool mobileOk; // "Use mobile data instead" for this one clip
  String? videoId;

  String get title => (meta['title'] as String? ?? '').isEmpty ? 'Clip' : meta['title'] as String;
  String get size => '${(bytes / 1e6).toStringAsFixed(bytes < 10e6 ? 1 : 0)} MB';

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'bytes': bytes,
        'meta': meta,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'error': error,
        'retryable': retryable,
        'mobileOk': mobileOk,
        'videoId': videoId,
      };

  factory UploadItem.fromJson(Map<String, dynamic> j) => UploadItem(
        id: j['id'] as String,
        path: j['path'] as String,
        name: j['name'] as String? ?? 'clip.mp4',
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        status: UploadStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => UploadStatus.waitingOnline),
        error: j['error'] as String?,
        retryable: j['retryable'] as bool? ?? true,
        mobileOk: j['mobileOk'] as bool? ?? false,
        videoId: j['videoId'] as String?,
      );
}

typedef Uploader = Future<String> Function(XFile file, Map<String, dynamic> meta, void Function(double) onProgress);

/// The upload queue: clips wait on the phone until they can go, and go one at a time.
///
/// Why a queue (handbook chapter 09): in Ghana a 50 MB clip on mobile data costs
/// real money and connections drop. So a clip is SAVED FIRST and SENT LATER:
///   - "Upload on Wi-Fi only" holds it until Wi-Fi (or the player says "use mobile data");
///   - offline, it waits, and goes by itself when the connection comes back;
///   - a dropped upload is retried, and its `clientId` lets the server spot the retry
///     so it never makes the same clip twice (an *idempotency key*);
///   - the list is saved, so closing the app loses nothing.
/// Under 18, clips wait until the guardian says yes.
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required this.upload,
    required this.net,
    required this.store,
    required this.wifiOnly,
    required this.needsGuardian,
    this.onUploaded,
    this.exists,
  }) {
    _sub = net.changes.listen((_) => pump(retryFailed: true));
  }

  final Uploader upload;
  final NetCheck net;
  final ResponseCache store;
  final bool Function() wifiOnly;
  final bool Function() needsGuardian;
  final void Function(String videoId)? onUploaded;

  /// Is the clip still on the phone? (The OS can clear image_picker's copies.)
  final Future<bool> Function(String path)? exists;

  final List<UploadItem> items = [];
  StreamSubscription<Net>? _sub;
  static const _key = 'upload_queue';

  List<UploadItem> get active => items.where((i) => i.status != UploadStatus.done).toList();

  Future<void> load() async {
    final raw = await store.get(_key);
    items.clear();
    if (raw != null) {
      for (final j in jsonDecode(raw) as List) {
        final it = UploadItem.fromJson(j as Map<String, dynamic>);
        if (it.status == UploadStatus.done && DateTime.now().difference(it.createdAt).inDays >= 1) continue;
        if (it.status == UploadStatus.uploading) it.status = UploadStatus.waitingOnline; // the app closed mid-upload
        items.add(it);
      }
    }
    notifyListeners();
    unawaited(pump(retryFailed: true));
  }

  Future<void> _save() => store.put(_key, jsonEncode([for (final i in items) i.toJson()]));

  /// Add a clip and try to send it. Returns its queue id.
  Future<String> add(XFile file, Map<String, dynamic> meta) async {
    final id = 'q${DateTime.now().microsecondsSinceEpoch}';
    items.add(UploadItem(
      id: id,
      path: file.path,
      name: file.name.isEmpty ? 'clip.mp4' : file.name,
      bytes: await file.length(),
      meta: {...meta, 'clientId': id},
      createdAt: DateTime.now(),
    ));
    await _save();
    notifyListeners();
    unawaited(pump());
    return id;
  }

  Future<void> useMobileData(String id) async {
    items.firstWhere((i) => i.id == id).mobileOk = true;
    await _save();
    await pump();
  }

  Future<void> retry(String id) async {
    final it = items.firstWhere((i) => i.id == id);
    it
      ..status = UploadStatus.waitingOnline
      ..error = null
      ..retryable = true;
    await _save();
    notifyListeners();
    await pump();
  }

  Future<void> remove(String id) async {
    items.removeWhere((i) => i.id == id);
    await _save();
    notifyListeners();
  }

  /// Why this clip can't go right now, or null if it can.
  Future<UploadStatus?> _blocked(UploadItem it) async {
    final n = await net.now();
    if (n == Net.offline) return UploadStatus.waitingOnline;
    if (needsGuardian()) return UploadStatus.waitingGuardian;
    if (wifiOnly() && n == Net.mobile && !it.mobileOk) return UploadStatus.waitingWifi;
    return null;
  }

  /// Send whatever can go, one clip at a time. Safe to call often: a call while
  /// a round is running waits for that round (and asks for one more after it).
  Future<void> pump({bool retryFailed = false}) {
    final running = _running;
    if (running != null) {
      _again = true;
      _againRetry |= retryFailed;
      return running;
    }
    final round = _round(retryFailed);
    _running = round;
    return round.whenComplete(() {
      _running = null;
      if (_again) {
        final r = _againRetry;
        _again = _againRetry = false;
        unawaited(pump(retryFailed: r));
      }
    });
  }

  Future<void>? _running;
  bool _again = false;
  bool _againRetry = false;

  Future<void> _round(bool retryFailed) async {
    final tried = <String>{}; // each clip at most once per round, so a failing one can't loop
    try {
      while (true) {
        final waiting = items.where((i) =>
            !tried.contains(i.id) &&
            i.status != UploadStatus.done &&
            i.status != UploadStatus.uploading &&
            (i.status != UploadStatus.failed || (retryFailed && i.retryable)));
        UploadItem? next;
        for (final it in waiting) {
          final why = await _blocked(it);
          if (why == null) {
            next = it;
            break;
          }
          if (it.status != UploadStatus.failed) it.status = why;
        }
        notifyListeners();
        if (next == null) break;
        tried.add(next.id);
        await _send(next);
      }
    } finally {
      await _save();
      notifyListeners();
    }
  }

  Future<void> _send(UploadItem it) async {
    if (exists != null && !await exists!(it.path)) {
      it
        ..status = UploadStatus.failed
        ..retryable = false
        ..error = "This clip isn't on your phone any more. Pick it again.";
      return;
    }
    it
      ..status = UploadStatus.uploading
      ..progress = 0
      ..error = null;
    notifyListeners();
    try {
      final videoId = await upload(XFile(it.path, name: it.name), it.meta, (p) {
        it.progress = p;
        notifyListeners();
      });
      it
        ..status = UploadStatus.done
        ..videoId = videoId
        ..progress = 1;
      onUploaded?.call(videoId);
    } on ApiError catch (e) {
      it
        ..status = UploadStatus.failed
        ..retryable = e.status == 0 || e.status >= 500
        ..error = e.status == 0 ? 'Stopped: the connection dropped' : e.message;
    } catch (_) {
      it
        ..status = UploadStatus.failed
        ..retryable = true
        ..error = 'Stopped: the connection dropped';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
