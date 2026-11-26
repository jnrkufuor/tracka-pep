// Crash reports: each different error is sent once, with no personal fields.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tracka/api/api_client.dart';
import 'package:tracka/api/cache.dart';
import 'package:tracka/state/crash_report.dart';

void main() {
  test('the same crash is sent once per session, and only the error travels', () async {
    final sent = <Map<String, dynamic>>[];
    final api = ApiClient(
      cache: MemoryCache(),
      client: MockClient((req) async {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"kept": true}', 202);
      }),
    );
    CrashReport.reset();
    CrashReport.install(api); // tests aren't release builds: hooks stay off, send() still works
    final stack = StackTrace.current;
    for (var i = 0; i < 5; i++) {
      CrashReport.send(StateError('boom'), stack);
    }
    CrashReport.send(ArgumentError('other'), stack);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent.length, 2);
    expect(sent.first.keys.toSet(), {'message', 'stack', 'appVersion', 'platform'});
    expect(sent.first['message'], contains('boom'));
  });
}
