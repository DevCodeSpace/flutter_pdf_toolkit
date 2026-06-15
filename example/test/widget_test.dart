import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('loads the PDF demo shell', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfProExampleApp());

    expect(find.text('Flutter PDF Pro'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });
}
