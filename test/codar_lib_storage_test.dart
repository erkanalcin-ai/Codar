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
}
