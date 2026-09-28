// Codar — offline-first personal ebook library (Phase 2 product shell).

import 'dart:async';

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/app/play_update_service.dart';
import 'package:codar/src/app/router.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/reader/locator_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: CodarApp()));
}

class CodarApp extends ConsumerStatefulWidget {
  const CodarApp({super.key});

  @override
  ConsumerState<CodarApp> createState() => _CodarAppState();
}

class _CodarAppState extends ConsumerState<CodarApp>
    with WidgetsBindingObserver {
  bool _showSplash = true;
  bool _bundledBookSeedStarted = false;
  Future<void> _externalOpenTail = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const MethodChannel('codar/open_with').setMethodCallHandler((call) async {
      if (call.method == 'openWithFile' && call.arguments is Map) {
        _queueExternalOpen(Map<String, Object?>.from(call.arguments as Map));
      }
    });
    // Keep the branded hand-off visible for a short, bounded interval while
    // the first frame and the local database are becoming ready.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
      unawaited(PlayUpdateService.promptOnStartup());
    });
    // Load persisted locale + reader settings once the database is ready.
    ref.listenManual(databaseProvider, (prev, next) {
      next.whenData((_) async {
        // Startup/dispose race: the DB or scope may be gone by the time
        // this lands (fast restart, tests). Defaults are already in
        // place, so a late load must never crash the launch.
        try {
          if (!_bundledBookSeedStarted) {
            _bundledBookSeedStarted = true;
            unawaited(_seedBundledSampleBook());
          }
          final settings = ref.read(settingsRepoProvider);
          final locale = await settings.appValue('locale', 'tr');
          if (!mounted) return;
          ref.read(localeProvider.notifier).set(locale);
          final rs = await settings.readerSettings();
          if (!mounted) return;
          ref.read(readerSettingsProvider.notifier).loadPersisted(rs);
          unawaited(_takePendingOpenWithFiles());
        } catch (_) {}
      });
    }, fireImmediately: true);
  }

  Future<void> _takePendingOpenWithFiles() async {
    try {
      final pending = await const MethodChannel('codar/open_with')
          .invokeMethod<List<dynamic>>('takePendingOpenWithFiles');
      for (final item in pending ?? const []) {
        if (item is Map) {
          _queueExternalOpen(Map<String, Object?>.from(item));
        }
      }
    } catch (_) {}
  }

  void _queueExternalOpen(Map<String, Object?> file) {
    final next = _externalOpenTail.then((_) => _importExternalOpen(file));
    _externalOpenTail = next.then((_) {}, onError: (_) {});
  }

  Future<void> _importExternalOpen(Map<String, Object?> file) async {
    if (!mounted) return;
    final uri = file['uri']?.toString() ?? '';
    if (uri.isEmpty) return;
    try {
      await ref.read(databaseProvider.future);
      final result = await ref
          .read(importServiceProvider)
          .importExternalUri(
            displayName: file['displayName']?.toString() ?? '',
            sourceUri: uri,
            sourceSize: (file['size'] as num?)?.toInt() ?? -1,
            mimeType: file['mimeType']?.toString() ?? '',
          );
      if (!mounted) return;
      ref.read(libraryRefreshProvider.notifier).bump();
      appRouter.go(readerRouteFor(result.bookId));
    } catch (_) {
      debugPrint('Unable to import external ebook document.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PlayUpdateService.promptOnStartup());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _seedBundledSampleBook() async {
    const settingKey = 'bundled_book_kurk_mantolu_madonna_v1';
    try {
      final settings = ref.read(settingsRepoProvider);
      if (await settings.appValue(settingKey, '0') == '1') return;

      final reader = ref.read(readerServiceProvider);
      await reader.init();
      final data = await rootBundle.load(
        'assets/books/kurk_mantolu_madonna.epub',
      );
      final result = await ref
          .read(importServiceProvider)
          .importBytes(
            displayName: 'Kürk_Mantolu_Madonna.epub',
            bytes: data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
          );
      await ref
          .read(booksRepoProvider)
          .setMetadata(result.bookId, 'bundled_sample', '1');
      await settings.setAppValue(settingKey, '1');
      if (mounted) ref.read(libraryRefreshProvider.notifier).bump();
    } catch (error) {
      debugPrint('Bundled sample book import failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: tr(locale, 'appTitle'),
      theme: CodarColors.light(),
      darkTheme: CodarColors.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          if (_showSplash) const _CodarSplashOverlay(),
        ],
      ),
    );
  }
}

class _CodarSplashOverlay extends StatefulWidget {
  const _CodarSplashOverlay();

  @override
  State<_CodarSplashOverlay> createState() => _CodarSplashOverlayState();
}

class _CodarSplashOverlayState extends State<_CodarSplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.16, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/brand/codar_splash_background.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB8111E2B), Color(0xD916202D)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => child!,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CodarLogo(height: 240, onDarkBackground: true),
                const SizedBox(height: 24),
                SizedBox(
                  width: 164,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _controller.value,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          CodarColors.gold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
