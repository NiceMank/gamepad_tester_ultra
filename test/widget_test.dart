import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad_tester_ultra/main.dart';

void main() {
  testWidgets('Gamepad Tester Ultra smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GamepadTesterUltraApp());
    expect(find.textContaining('MODÈLE 3D INTERACTIF'), findsOneWidget);
  });
}
