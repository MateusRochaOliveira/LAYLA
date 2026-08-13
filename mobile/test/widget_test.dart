import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('LAYLA app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LaylaApp());

    // Verify that the title appears on screen.
    expect(find.text('LAYLA'), findsOneWidget);
  });
}