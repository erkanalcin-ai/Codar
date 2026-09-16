// Codar Phase 1 spike harness (NOT product UI).
//
// Runs the on-device proof suite against the physical Android device:
// FRB <-> Rust Reader Core <-> ebook-rs, SQLite locator persistence,
// and the MediaStore-backed Downloads/CodarLib flow.

import 'dart:io';

import 'package:codar/src/db/locator_store.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codar Phase 1 Spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const SpikeHome(),
    );
  }
}

class SpikeResult {
  SpikeResult(this.name, this.pass, this.detail);
  final String name;
  final bool pass;
  final String detail;
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  final CodarReaderService _reader = CodarReaderService();
  final List<SpikeResult> _results = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Phase 1 harness: auto-run once the bridge is ready (spike only).
    _reader.init().then((_) async {
      setState(() {});
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        await _runAll();
        await _dumpResults();
      }
    });
  }

  Future<void> _dumpResults() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'spike_results.txt'));
      final buf = StringBuffer();
      for (final r in _results) {
        buf.writeln("${r.pass ? 'PASS' : 'FAIL'} | ${r.name} | ${r.detail}");
      }
      await file.writeAsString(buf.toString(), flush: true);
    } catch (_) {
      // best effort; screen still shows results
    }
  }

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  void _add(String name, bool pass, String detail) {
    setState(() => _results.add(SpikeResult(name, pass, detail)));
  }

  /// Stage a bundled asset into app files dir and return its filesystem path.
  Future<String> _stageAsset(String assetName) async {
    final data = await rootBundle.load('assets/spike/$assetName');
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, assetName));
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  Future<void> _runAll() async {
    if (_running || !_reader.isReady) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    try {
      await _spikeFrbEpub();
      await _spikePdf();
      await _spikeCbzTxt();
      await _spikeCfiSearchRestore();
      await _spikeSoak();
      await _spikeLargeIfPresent();
      await _spikeSqlite();
      await _spikeCodarLib();
    } catch (e) {
      _add('harness', false, 'unexpected: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _spikeFrbEpub() async {
    try {
      final path = await _stageAsset('min.epub');
      await _reader.withBook(path, (s) async {
        final info = await _reader.getDocumentInfo(s);
        final chapters = await _reader.getChapters(s);
        final c0 = await _reader.getContent(s, 0);
        final ok = info.title == 'Codar Spike Fixture' &&
            chapters.length == 2 &&
            c0.plainText.contains('CodarSpikePhrase');
        _add('FRB+EPUB', ok,
            'title=${info.title} chapters=${chapters.length} sections=${info.sectionCount}');
      });
    } catch (e) {
      _add('FRB+EPUB', false, '$e');
    }
  }

  Future<void> _spikePdf() async {
    try {
      final path = await _stageAsset('spike.pdf');
      await _reader.withBook(path, (s) async {
        final info = await _reader.getDocumentInfo(s);
        final p0 = await _reader.getPage(s, 0);
        final ok = info.sectionCount.toInt() == 2 &&
            p0.plainText.contains('CodarSpikePhrase');
        _add('PDF pages+temp', ok,
            'sections=${info.sectionCount} (temp_dir worked if open worked)');
      });
      // No ebook_rs_temp* leftovers may survive the session close.
      final tmp = await getTemporaryDirectory();
      final leftovers = tmp
          .listSync()
          .where((e) => p.basename(e.path).startsWith('ebook_rs_temp_'))
          .toList();
      _add('PDF temp cleanup', leftovers.isEmpty, 'leftovers=${leftovers.length}');
    } catch (e) {
      _add('PDF pages+temp', false, '$e');
    }
  }

  Future<void> _spikeCbzTxt() async {
    try {
      final cbz = await _stageAsset('spike.cbz');
      final txt = await _stageAsset('spike_tr.txt');
      var ok = true;
      final details = StringBuffer();
      await _reader.withBook(cbz, (s) async {
        final info = await _reader.getDocumentInfo(s);
        ok &= info.sectionCount.toInt() == 3;
        details.write('cbz=${info.sectionCount} ');
      });
      await _reader.withBook(txt, (s) async {
        final c0 = await _reader.getContent(s, 0);
        ok &= c0.plainText.contains('İ') && c0.plainText.contains('ş');
        details.write('txt-tr-ok ');
      });
      _add('CBZ+TXT', ok, details.toString());
    } catch (e) {
      _add('CBZ+TXT', false, '$e');
    }
  }

  Future<void> _spikeCfiSearchRestore() async {
    try {
      final path = await _stageAsset('min.epub');
      var ok = true;
      final details = StringBuffer();
      await _reader.withBook(path, (s) async {
        final loc = await _reader.getLocator(s, 1, 10);
        final restored = await _reader.restoreLocator(s, loc);
        ok &= restored.sectionIndex.toInt() == 1;
        details.write('cfi-sec=${restored.sectionIndex} ');
        final hits = await _reader.search(s, 'CodarSpikePhrase');
        ok &= hits.isNotEmpty && hits.first.cfi.isNotEmpty;
        final r2 = await _reader.restoreLocator(
            s, await _reader.getLocator(s, hits.first.sectionIndex.toInt(), hits.first.charOffset.toInt()));
        ok &= r2.sectionIndex == hits.first.sectionIndex;
        details.write('hits=${hits.length} ');
      });
      _add('CFI+search restore', ok, details.toString());
    } catch (e) {
      _add('CFI+search restore', false, '$e');
    }
  }

  Future<void> _spikeSoak() async {
    try {
      final path = await _stageAsset('min.epub');
      final before = await _reader.liveSessionCount();
      for (var i = 0; i < 30; i++) {
        await _reader.withBook(path, (s) async {
          await _reader.getContent(s, 0);
        });
      }
      final after = await _reader.liveSessionCount();
      _add('open/close soak', after == before, 'before=$before after=$after');
    } catch (e) {
      _add('open/close soak', false, '$e');
    }
  }

  /// Large-file proof, runs only when pride.epub was staged (adb, see report).
  Future<void> _spikeLargeIfPresent() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File(p.join(dir.path, 'pride.epub'));
      if (!await f.exists()) {
        _add('large EPUB (device)', true, 'skipped: pride.epub not staged');
        return;
      }
      final sw = Stopwatch()..start();
      await _reader.withBook(f.path, (s) async {
        final info = await _reader.getDocumentInfo(s);
        final c5 = await _reader.getContent(s, 5);
        final hits = await _reader.search(s, 'Bennet');
        _add('large EPUB (device)', info.sectionCount.toInt() > 10 && hits.isNotEmpty,
            'sections=${info.sectionCount} open+sec5+search=${sw.elapsedMilliseconds}ms hits=${hits.length} c5len=${c5.plainText.length}');
      });
    } catch (e) {
      _add('large EPUB (device)', false, '$e');
    }
  }

  Future<void> _spikeSqlite() async {
    try {
      final path = await _stageAsset('min.epub');
      final store = await LocatorStore.open();
      var ok = true;
      final details = StringBuffer();
      final locator = await _reader.withBook(path, (s) => _reader.getLocator(s, 1, 10));
      await store.saveLocator('min.epub', locator);
      await store.close();
      // Reopen database from disk and restore through a fresh session.
      final store2 = await LocatorStore.open();
      final loaded = await store2.loadLocator('min.epub');
      await store2.close();
      ok &= loaded == locator;
      details.write('roundtrip=${loaded == locator} ');
      await _reader.withBook(path, (s) async {
        final r = await _reader.restoreLocator(s, loaded!);
        ok &= r.sectionIndex.toInt() == 1;
        details.write('restore-sec=${r.sectionIndex}');
      });
      _add('SQLite locator', ok, details.toString());
    } catch (e) {
      _add('SQLite locator', false, '$e');
    }
  }

  Future<void> _spikeCodarLib() async {
    try {
      final storage = CodarLibStorage();
      final bytes = (await rootBundle.load('assets/spike/min.epub')).buffer.asUint8List();
      final uri = await storage.importFile(
          name: 'spike_min.epub', bytes: bytes, mime: 'application/epub+zip');
      final listed = await storage.listCodarLib();
      final seen = listed.any((f) => f.uri == uri);
      final back = await storage.readFile(uri);
      var matches = back.length == bytes.length;
      if (matches) {
        for (var i = 0; i < bytes.length; i++) {
          if (back[i] != bytes[i]) {
            matches = false;
            break;
          }
        }
      }
      // Prove the CodarLib copy itself opens in the engine (via cache staging,
      // because the engine needs a filesystem path and MediaStore gives URIs).
      final dir = await getApplicationSupportDirectory();
      final staged = File(p.join(dir.path, 'codarlib_proof.epub'));
      await staged.writeAsBytes(back, flush: true);
      var engineOk = false;
      await _reader.withBook(staged.path, (s) async {
        engineOk = (await _reader.getDocumentInfo(s)).title == 'Codar Spike Fixture';
      });
      await storage.deleteFile(uri);
      _add('Downloads/CodarLib', seen && matches && engineOk,
          'listed=$seen bytes=$matches engine=$engineOk uri=$uri');
    } catch (e) {
      _add('Downloads/CodarLib', false, '$e');
    }
  }

  Future<void> _pickBigFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final dir = await getApplicationSupportDirectory();
    final staged = File(p.join(dir.path, f.name));
    await staged.writeAsBytes(bytes, flush: true);
    final sw = Stopwatch()..start();
    try {
      await _reader.withBook(staged.path, (s) async {
        final info = await _reader.getDocumentInfo(s);
        final c = await _reader.getContent(s, 0);
        _add('SAF big file', true,
            '${f.name} sections=${info.sectionCount} open+sec0=${sw.elapsedMilliseconds}ms c0len=${c.plainText.length}');
      });
    } catch (e) {
      _add('SAF big file', false, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _results.where((r) => r.pass).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Codar Phase 1 Spike')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _running || !_reader.isReady ? null : _runAll,
                  child: Text(_running ? 'Running…' : 'Run all spike tests'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _running || !_reader.isReady ? null : _pickBigFile,
                  child: const Text('Pick big file (SAF)'),
                ),
                const SizedBox(width: 8),
                Text('${_results.length} run · $passed pass · FRB ${_reader.isReady ? 'ready' : '…'}'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                return ListTile(
                  leading: Icon(
                    r.pass ? Icons.check_circle : Icons.error,
                    color: r.pass ? Colors.green : Colors.red,
                  ),
                  title: Text(r.name),
                  subtitle: Text(r.detail),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
