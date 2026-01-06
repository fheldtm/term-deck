import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:term_deck/main.dart';

void main() {
  testWidgets('App builds successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: SSHTerminalApp(),
      ),
    );

    // Verify app loads
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
