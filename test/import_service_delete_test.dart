import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verified managed files are deleted only after the library record',
    () async {
      final events = <String>[];
      final retained = await deleteBookEntryWithSafeFileHandling(
        fileUri: 'content://media/external_primary/downloads/10',
        deleteFile: true,
        inspectFile: (uri) async {
          events.add('inspect:$uri');
          return ManagedFileState.managedPresent;
        },
        deleteManagedFile: (uri) async {
          events.add('delete:$uri');
          return true;
        },
        deleteRecord: () async => events.add('record'),
      );

      expect(retained, isFalse);
      expect(events, [
        'inspect:content://media/external_primary/downloads/10',
        'record',
        'delete:content://media/external_primary/downloads/10',
      ]);
    },
  );

  test('external or unknown files are preserved while the library record is removed', () async {
    for (final state in [ManagedFileState.external, ManagedFileState.unknown]) {
      var recordDeleted = false;
      var physicalDeleteCalled = false;
      final retained = await deleteBookEntryWithSafeFileHandling(
        fileUri: 'content://provider/document/42',
        deleteFile: true,
        inspectFile: (_) async => state,
        deleteManagedFile: (_) async {
          physicalDeleteCalled = true;
          return true;
        },
        deleteRecord: () async => recordDeleted = true,
      );

      expect(recordDeleted, isTrue);
      expect(physicalDeleteCalled, isFalse);
      expect(retained, isTrue);
    }
  });

  test(
    'a provider deletion failure does not block the library removal',
    () async {
      var recordDeleted = false;
      final retained = await deleteBookEntryWithSafeFileHandling(
        fileUri: 'content://media/external_primary/downloads/11',
        deleteFile: true,
        inspectFile: (_) async => ManagedFileState.managedPresent,
        deleteManagedFile: (_) async => false,
        deleteRecord: () async => recordDeleted = true,
      );

      expect(recordDeleted, isTrue);
      expect(retained, isTrue);
    },
  );

  test('a database failure never deletes the managed physical file', () async {
    var physicalDeleteCalled = false;
    await expectLater(
      deleteBookEntryWithSafeFileHandling(
        fileUri: 'content://media/external_primary/downloads/12',
        deleteFile: true,
        inspectFile: (_) async => ManagedFileState.managedPresent,
        deleteManagedFile: (_) async {
          physicalDeleteCalled = true;
          return true;
        },
        deleteRecord: () async => throw StateError('database-failed'),
      ),
      throwsStateError,
    );

    expect(physicalDeleteCalled, isFalse);
  });

  test('keep-file choice deletes only the library record', () async {
    var inspected = false;
    var physicalDeleteCalled = false;
    var recordDeleted = false;
    final retained = await deleteBookEntryWithSafeFileHandling(
      fileUri: 'content://media/external_primary/downloads/13',
      deleteFile: false,
      inspectFile: (_) async {
        inspected = true;
        return ManagedFileState.managedPresent;
      },
      deleteManagedFile: (_) async {
        physicalDeleteCalled = true;
        return true;
      },
      deleteRecord: () async => recordDeleted = true,
    );

    expect(recordDeleted, isTrue);
    expect(inspected, isFalse);
    expect(physicalDeleteCalled, isFalse);
    expect(retained, isFalse);
  });
}
