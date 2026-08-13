import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layla_level/main.dart';

void main() {
  testWidgets('LaylaHome smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LaylaHome(),
      ),
    );

    expect(find.textContaining('LAYLA'), findsOneWidget);
  });
}