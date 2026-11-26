import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';

void main() {
  test('a notification reads its group, link and read state', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'kind': 'reviews',
      'group': 'pep',
      'title': "Pep's read on Sunday match is ready",
      'body': '3 tips, starting at 12:40',
      'link': {'screen': 'video', 'id': 'v1'},
      'createdAt': '2026-11-25T10:00:00+00:00',
      'read': false,
    });
    expect(n.group, 'pep');
    expect(n.link!['id'], 'v1');
    expect(n.read, isFalse);
  });

  test('notification settings default to on, quiet hours on', () {
    final s = AppSettings.fromJson({'notifications': {'respect': false}});
    expect(s.notifications['respect'], isFalse);
    expect(s.notifications['reviews'] ?? true, isTrue);
    expect(s.quietHours, isTrue);
  });
}
