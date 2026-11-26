import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tracka/widgets/pep.dart';

/// Pep moves like the design: his eye glances around over time, and he
/// stands still when motion is reduced.
void main() {
  testWidgets('Pep is alive: his layers move over time', (tester) async {
    PepFace.breathing = true;
    addTearDown(() => PepFace.breathing = false);
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: PepFace(PepMood.justHere, size: 100)),
    ));
    Matrix4 eye() => tester.widgetList<Transform>(find.byType(Transform)).last.transform.clone();
    await tester.pump(const Duration(milliseconds: 100));
    final a = eye();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(eye(), isNot(equals(a)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Pep stands still when motion is reduced', (tester) async {
    PepFace.breathing = true;
    addTearDown(() => PepFace.breathing = false);
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.ltr, child: PepFace(PepMood.excited)),
    ));
    expect(find.byType(Transform), findsNothing);
  });
}
