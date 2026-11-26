import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracka/api/api_client.dart';
import 'package:tracka/api/cache.dart';
import 'package:tracka/state/net.dart';
import 'package:tracka/state/upload_queue.dart';

void main() {
  late FakeNet net;
  late MemoryCache store;
  late List<Map<String, dynamic>> sent;
  var wifiOnly = true;
  var guardian = false;
  var failNext = 0;

  UploadQueue make() => UploadQueue(
        upload: (file, meta, onProgress) async {
          if (failNext > 0) {
            failNext--;
            throw ApiError(0, 'dropped');
          }
          onProgress(1);
          sent.add(meta);
          return 'v${sent.length}';
        },
        net: net,
        store: store,
        wifiOnly: () => wifiOnly,
        needsGuardian: () => guardian,
        exists: (_) async => true,
      );

  XFile clip() => XFile.fromData(Uint8List(2000000), name: 'clip.mp4', path: '/tmp/clip.mp4');

  setUp(() {
    net = FakeNet(Net.wifi);
    store = MemoryCache();
    sent = [];
    wifiOnly = true;
    guardian = false;
    failNext = 0;
  });

  test('on Wi-Fi a clip goes at once, with a client id', () async {
    final q = make();
    final id = await q.add(clip(), {'title': 'Sunday'});
    await q.pump();
    expect(q.items.single.status, UploadStatus.done);
    expect(sent.single['clientId'], id);
  });

  test('on mobile data it waits for Wi-Fi unless you say use mobile data', () async {
    net.set(Net.mobile);
    final q = make();
    final id = await q.add(clip(), {'title': 'Wall passes'});
    await q.pump();
    expect(q.items.single.status, UploadStatus.waitingWifi);
    await q.useMobileData(id);
    expect(q.items.single.status, UploadStatus.done);
  });

  test('a dropped upload is retried with the same id, and survives a restart', () async {
    failNext = 1;
    final q = make();
    await q.add(clip(), {'title': 'Sprint'});
    await q.pump();
    expect(q.items.single.status, UploadStatus.failed);
    expect(q.items.single.error, 'Stopped: the connection dropped');

    final again = make(); // the app was closed and opened
    await again.load();
    await again.pump(retryFailed: true);
    expect(again.items.single.status, UploadStatus.done);
    expect(sent.single['clientId'], q.items.single.id);
  });

  test('offline and waiting for a guardian hold clips', () async {
    guardian = true;
    final q = make();
    await q.add(clip(), {});
    await q.pump();
    expect(q.items.single.status, UploadStatus.waitingGuardian);
    net.set(Net.offline);
    await q.pump();
    expect(q.items.single.status, UploadStatus.waitingOnline);
    expect(sent, isEmpty);
  });

  test('saved answers are used when the network is down', () async {
    final c = MemoryCache();
    await c.put('/v1/meta', '{"positions": ["CM"], "regions": ["Ashanti"], "drills": {}}');
    final api = ApiClient(client: MockClient((_) async => throw http.ClientException('down')), cache: c);
    final meta = await api.meta();
    expect(meta.positions, ['CM']);
    expect(api.offline.value, isTrue);
    await expectLater(api.tips(), throwsA(isA<ApiError>())); // nothing saved for it
  });
}
