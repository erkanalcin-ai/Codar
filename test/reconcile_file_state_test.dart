import 'package:codar/src/library/reconcile_service.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'provider URI states fail closed unless managed file is confirmed missing',
    () {
      expect(
        managedFileStateFromValue('managed_present'),
        ManagedFileState.managedPresent,
      );
      expect(
        managedFileStateFromValue('managed_missing'),
        ManagedFileState.managedMissing,
      );
      expect(managedFileStateFromValue('external'), ManagedFileState.external);
      expect(
        managedFileStateFromValue('permission_denied'),
        ManagedFileState.unknown,
      );
      expect(
        shouldPurgeReconciledFile(
          uriListed: false,
          state: ManagedFileState.unknown,
        ),
        isFalse,
      );
      expect(
        shouldPurgeReconciledFile(
          uriListed: false,
          state: ManagedFileState.external,
        ),
        isFalse,
      );
      expect(
        shouldPurgeReconciledFile(
          uriListed: false,
          state: ManagedFileState.managedMissing,
        ),
        isTrue,
      );
      expect(
        shouldPurgeReconciledFile(
          uriListed: true,
          state: ManagedFileState.managedMissing,
        ),
        isFalse,
      );
    },
  );
}
