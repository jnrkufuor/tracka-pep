// Runs before every test file (a Flutter test convention).
import 'dart:async';

import 'package:tracka/widgets/pep.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PepFace.breathing = false; // Pep's breath loops forever; tests wait for animations to end
  await testMain();
}
