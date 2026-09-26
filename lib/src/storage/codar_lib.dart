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

  Future<List<CodarLibFile>> listCodarLib() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listCodarLib');
    if (raw == null) throw StateError('listCodarLib returned null');
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
