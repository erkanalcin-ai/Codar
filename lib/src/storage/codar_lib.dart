// MediaStore-backed Downloads/CodarLib/ access.
// No MANAGE_EXTERNAL_STORAGE. Only the app's own entries are visible.

import 'package:flutter/services.dart';

class CodarLibFile {
  CodarLibFile({required this.name, required this.uri});
  final String name;
  final String uri;
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

  /// Moves a user-selected local file into CodarLib.
  ///
  /// The Android side streams from the original SAF/file URI into the
  /// CodarLib destination and deletes the source only after the stream has
  /// completed and its size matches. This avoids a persistent duplicate.
  Future<String> movePickedFile({
    required String name,
    required String mime,
    required String sourceUri,
    required int size,
  }) async {
    final uri = await _ch.invokeMethod<String>('movePickedFile', {
      'name': name,
      'mime': mime,
      'sourceUri': sourceUri,
      'size': size,
    });
    if (uri == null) throw StateError('movePickedFile returned null');
    return uri;
  }

  Future<Uint8List> readFile(String uri) async {
    final bytes = await _ch.invokeMethod<Uint8List>('readFile', {'uri': uri});
    if (bytes == null) throw StateError('readFile returned null');
    return bytes;
  }

  Future<List<CodarLibFile>> listCodarLib() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listCodarLib');
    if (raw == null) return [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(
          (m) =>
              CodarLibFile(name: m['name'] as String, uri: m['uri'] as String),
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

  Future<bool> deleteFile(String uri) async {
    final ok = await _ch.invokeMethod<bool>('deleteFile', {'uri': uri});
    return ok ?? false;
  }
}
