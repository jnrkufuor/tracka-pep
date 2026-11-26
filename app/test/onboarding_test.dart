import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/theme/theme.dart';
import 'package:tracka/widgets/pitch_picker.dart';
import 'package:tracka/widgets/profile_fields.dart';

void main() {
  test('shirt name is suggested from the name, and the draft sends v2 fields', () {
    final d = ProfileDraft()
      ..firstName = 'Kwame'
      ..lastName = 'Asante'
      ..birthDate = DateTime(2010, 3, 14)
      ..sex = 'male'
      ..goal = 'academy'
      ..level = 'club'
      ..positionOrder = ['CM', 'CDM']
      ..weakFoot = 3
      ..guardianPhone = '24 123 4567';
    expect(d.suggestedShirtName, 'K. ASANTE');
    final j = d.toJsonV2();
    expect(j['displayName'], 'Kwame Asante');
    expect(j['shirtName'], 'K. ASANTE');
    expect(j['positions'], ['CM', 'CDM']);
    expect(j['birthDate'], '2010-03-14');
    expect(j['guardianRelation'], 'parent'); // under 18
  });

  testWidgets('pitch picker: first tap is main, tapping an extra makes it main', (tester) async {
    var picked = <String>[];
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: trackaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => PitchPicker(positions: picked, onChanged: (v) => setState(() => picked = v)),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('CM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DM'));
    await tester.pumpAndSettle();
    expect(picked, ['CM', 'CDM']);
    await tester.tap(find.text('DM'));
    await tester.pumpAndSettle();
    expect(picked, ['CDM', 'CM']);
    expect(find.text('Main · Defensive midfielder'), findsOneWidget);
  });
}
