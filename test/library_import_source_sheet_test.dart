import 'package:codar/src/presentation/library/library_import_source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import sheet presents only file and folder actions', (
    tester,
  ) async {
    final selected = <LibraryImportMode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryImportSourceSheet(
            filesLabel: 'Dosya Seç',
            folderLabel: 'Klasör Seç',
            onSelected: selected.add,
          ),
        ),
      ),
    );

    expect(find.text('Klasör ekleme yöntemi'), findsNothing);
    expect(find.text('Dosya Seç'), findsOneWidget);
    expect(find.text('Klasör Seç'), findsOneWidget);
    await tester.tap(find.text('Dosya Seç'));
    await tester.tap(find.text('Klasör Seç'));
    expect(selected, [LibraryImportMode.files, LibraryImportMode.folder]);
  });
}
