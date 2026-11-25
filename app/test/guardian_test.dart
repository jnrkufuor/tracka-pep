import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';

void main() {
  test('guardian state reads pending requests and permissions', () {
    final g = GuardianState.fromJson({
      'needed': true,
      'status': 'approved',
      'name': 'Ama',
      'phone': '+233 24 ••• 4567',
      'permissions': {'account': true, 'post': false, 'shareCard': true, 'search': false},
      'requests': [
        {'id': '1', 'kind': 'post', 'status': 'pending'},
        {'id': '2', 'kind': 'share_card', 'status': 'yes'},
      ],
      'textsLive': false,
      'selfConfirm': true,
    });
    expect(g.who, 'Ama');
    expect(g.can('shareCard'), isTrue);
    expect(g.can('post'), isFalse);
    expect(g.pendingKinds, ['post']);
    expect(GuardianState.fromJson({'status': 'none'}).who, 'your guardian');
  });

  test('meta says whether texts are live', () {
    final m = Meta.fromJson({'positions': ['CM'], 'regions': ['Ashanti'], 'drills': {}, 'textsLive': false, 'guardianSelfConfirm': true});
    expect(m.textsLive, isFalse);
    expect(m.guardianSelfConfirm, isTrue);
  });
}
