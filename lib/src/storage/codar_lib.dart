// MediaStore-backed Downloads/CodarLib access, with explicit SAF enumeration
// when the user selects the verified CodarLib root. No broad storage permission.

import 'package:flutter/services.dart';

class CodarLibFile {
  CodarLibFile({required this.name, required this.uri, required this.size});
  final String name;
  final String uri;
  final int size;
}

class CodarTreeFile {
  CodarTreeFile({required this.name, required this.uri, required this.size});

  factory CodarTreeFile.fromMap(Map<dynamic, dynamic> map) {
    return CodarTreeFile(
      name: map['name'] as String? ?? '',
      uri: map['uri'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? -1,
    );
  }

  final String name;
  final String uri;
  final int size;
}

enum ManagedFileState { managedPresent, managedMissing, external, unknown }

ManagedFileState managedFileStateFromValue(Object? value) => switch (value) {
  'managed_present' => ManagedFileState.managedPresent,
  'managed_missing' => ManagedFileState.managedMissing,
  'external' => ManagedFileState.external,
  _ => ManagedFileState.unknown,
};

class CodarLibStorage {
  static const MethodChannel _ch = MethodChannel('codar/storage');

  Future<String> importFile({
    required String name,
    required Uint8List bytes,
    required String mime,
  }) async {
    final uri = await _ch.invokeMethod<String>('importFile', {
      'name': name,
      'bytes': bytes,
      'mime': mime,
    });
    if (uri == null) throw StateError('importFile returned null');
    return uri;
  }

  /// Copies a selected file into CodarLib. The source remains until its
  /// database record has been committed successfully.
  Future<String> copyPickedFile({
    required String name,
    required String mime,
    required String sourceUri,
    required int size,
  }) async {
    final uri = await _ch.invokeMethod<String>('copyPickedFile', {
      'name': name,
      'mime': mime,
      'sourceUri': sourceUri,
      'size': size,
    });
    if (uri == null) throw StateError('copyPickedFile returned null');
    return uri;
  }

  Future<bool> deletePickedSource(String sourceUri) async =>
      await _ch.invokeMethod<bool>('deletePickedSource', {
        'sourceUri': sourceUri,
      }) ??
      false;

  Future<Uint8List> readFile(String uri, {required int maxBytes}) async {
    final bytes = await _ch.invokeMethod<Uint8List>('readFile', {
      'uri': uri,
      'maxBytes': maxBytes,
    });
    if (bytes == null) throw StateError('readFile returned null');
    return bytes;
  }

  Future<bool> copyFileToPath({
    required String uri,
    required String path,
    required int size,
  }) async =>
      await _ch.invokeMethod<bool>('copyFileToPath', {
        'uri': uri,
        'path': path,
        'size': size,
      }) ??
      false;

  Future<bool> copyExternalToPath({
    required String uri,
    required String path,
    required int maxBytes,
  }) async =>
      await _ch.invokeMethod<bool>('copyExternalToPath', {
        'uri': uri,
        'path': path,
        'maxBytes': maxBytes,
      }) ??
      false;

  Future<List<CodarLibFile>> listCodarLib() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listCodarLib');
    if (raw == null) throw StateError('listCodarLib returned null');
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(
          (m) =>
              CodarLibFile(
                name: m['name'] as String,
                uri: m['uri'] as String,
                size: (m['size'] as num?)?.toInt() ?? -1,
              ),
        )
        .toList();
  }

  /// Enumerates a user-selected, verified CodarLib SAF tree. Native storage
  /// returns stable managed URIs where possible and persisted tree child URIs
  /// for existing files whose MediaStore ownership metadata is unavailable.
  Future<List<CodarLibFile>> listCodarLibFromTree(String treeUri) async {
    final raw = await _ch.invokeMethod<List<dynamic>>(
      'listCodarLibFromTree',
      {'treeUri': treeUri},
    );
    if (raw == null) throw StateError('listCodarLibFromTree returned null');
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(
          (m) => CodarLibFile(
            name: m['name'] as String,
            uri: m['uri'] as String,
            size: (m['size'] as num?)?.toInt() ?? -1,
          ),
        )
        .toList();
  }

  Future<List<CodarTreeFile>> listTreeFiles(String treeUri) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listTreeFiles', {
      'treeUri': treeUri,
    });
    if (raw == null) return [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(CodarTreeFile.fromMap)
        .toList();
  }

  /// True only when [location] identifies the exact Android storage root
  /// managed by this app, as defined by MainActivity's write destination.
  Future<bool> isCodarLibRoot(String location) async {
    try {
      return await _ch.invokeMethod<bool>('isCodarLibRoot', {
            'location': location,
          }) ??
          false;
    } on PlatformException {
      // An unrecognized SAF provider remains an ordinary external folder.
      return false;
    } on MissingPluginException {
      // Non-Android builds do not expose Android's managed storage root.
      return false;
    }
  }

  /// Identifies whether a stored URI still names a file in Codar's managed
  /// library. Unknown results must never be treated as a confirmed deletion.
  Future<ManagedFileState> managedFileState(String uri) async {
    try {
      final value = await _ch.invokeMethod<String>('managedFileState', {
        'uri': uri,
      });
      return managedFileStateFromValue(value);
    } on PlatformException {
      return ManagedFileState.unknown;
    } on MissingPluginException {
      return ManagedFileState.unknown;
    }
  }

  Future<bool> deleteFile(String uri) async {
    final ok = await _ch.invokeMethod<bool>('deleteFile', {'uri': uri});
    return ok ?? false;
  }
}
