// Basic Flutter widget test for CollBus app.

import 'package:flutter_test/flutter_test.dart';

import 'package:collbus/main.dart';

void main() {
  testWidgets('App loads and shows login screen with CollBus branding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const CollBusApp());

    expect(find.text('CollBus'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
