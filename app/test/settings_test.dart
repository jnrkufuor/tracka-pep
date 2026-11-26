import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';

void main() {
  test('text size and Pep voice settings have safe defaults', () {
    final s = AppSettings.fromJson({});
    expect(s.textSize, 'm');
    expect(s.textScale, 1.0);
    expect(s.pepVoice, 'coach');
    expect(AppSettings.fromJson({'textSize': 'xl'}).textScale, greaterThan(1.2));
    expect(s.highContrast, isFalse);
    expect(AppSettings.fromJson({'highContrast': true}).highContrast, isTrue);
  });
}
