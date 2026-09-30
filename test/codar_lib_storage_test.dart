import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('codar/storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('managed CodarLib listing carries canonical URI and file size', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'listCodarLib');
          return [
            {
              'name': 'Example.pdf',
              'uri': 'content://media/external/downloads/42',
              'size': 8192,
            },
          ];
        });

    final files = await CodarLibStorage().listCodarLib();

    expect(files, hasLength(1));
    expect(files.single.name, 'Example.pdf');
    expect(files.single.uri, 'content://media/external/downloads/42');
    expect(files.single.size, 8192);
  });

  test('selected CodarLib tree listing preserves URI and unknown size', () async {
    const treeUri =
        'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FCodarLib';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'listCodarLibFromTree');
          expect(call.arguments, {'treeUri': treeUri});
          return [
            {
              'name': 'Legacy.epub',
              'uri': '$treeUri/document/primary%3ADownload%2FCodarLib%2FLegacy.epub',
              'size': -1,
            },
          ];
        });

    final files = await CodarLibStorage().listCodarLibFromTree(treeUri);

    expect(files, hasLength(1));
    expect(files.single.name, 'Legacy.epub');
    expect(files.single.uri, contains('Legacy.epub'));
    expect(files.single.size, -1);
  });

  test('external copy sends an explicit streaming size limit', () async {
    const maxBytes = 200 * 1024 * 1024;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'copyExternalToPath');
          expect(call.arguments, {
            'uri': 'content://provider/document/1',
            'path': '/tmp/import.epub',
            'maxBytes': maxBytes,
          });
          return true;
        });

    final copied = await CodarLibStorage().copyExternalToPath(
      uri: 'content://provider/document/1',
      path: '/tmp/import.epub',
      maxBytes: maxBytes,
    );

    expect(copied, isTrue);
  });
}
