import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('library cover placeholder shows only icon and format', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookCoverFallback(
            title: 'The real book title',
            author: 'Example Author',
            format: 'pdf',
            width: 120,
            height: 160,
            showTitle: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('The real book title'), findsNothing);
    expect(find.text('Example Author'), findsNothing);
  });
}
