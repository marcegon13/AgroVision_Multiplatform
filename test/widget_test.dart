// This is a basic Flutter widget test for AgroVisionApp.
import 'package:flutter_test/flutter_test.dart';
import 'package:agrovision_multiplatform/main.dart';

void main() {
  testWidgets('AgroVision app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AgroVisionApp());

    // Verify that the title 'AgroVision' is present.
    expect(find.text('AgroVision'), findsOneWidget);
  });
}
