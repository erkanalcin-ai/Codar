// Codar — offline-first personal ebook library (Phase 2 product shell).

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/app/router.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: CodarApp()));
}

class CodarApp extends ConsumerStatefulWidget {
  const CodarApp({super.key});

  @override
  ConsumerState<CodarApp> createState() => _CodarAppState();
}

class _CodarAppState extends ConsumerState<CodarApp> {
  @override
  void initState() {
    super.initState();
    // Load persisted locale + reader settings once the database is ready.
    ref.listenManual(
      databaseProvider,
      (prev, next) {
        next.whenData((_) async {
          final settings = ref.read(settingsRepoProvider);
          final locale = await settings.appValue('locale', 'tr');
          if (mounted) ref.read(localeProvider.notifier).set(locale);
          final rs = await settings.readerSettings();
          if (mounted) {
            ref.read(readerSettingsProvider.notifier).set(rs);
          }
        });
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: tr(locale, 'appTitle'),
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme:
          ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true, brightness: Brightness.dark),
      routerConfig: appRouter,
    );
  }
}
