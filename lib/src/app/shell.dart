import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final destinations = [(Icons.home_outlined, Icons.home_rounded, tr(locale, 'home')), (Icons.menu_book_outlined, Icons.menu_book_rounded, tr(locale, 'library')), (Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded, tr(locale, 'collections')), (Icons.settings_outlined, Icons.settings_rounded, tr(locale, 'settings'))];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 800;
      const overlay = SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark, systemNavigationBarColor: CodarColors.background, systemNavigationBarIconBrightness: Brightness.light);
      WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) { SystemChrome.setSystemUIOverlayStyle(overlay); const MethodChannel('codar/storage').invokeMethod<void>('setSystemUi', <String, Object>{'lightStatusBar': false}); } });
      return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: Scaffold(backgroundColor: CodarColors.background, body: wide ? Row(children: [NavigationRail(selectedIndex: shell.currentIndex, onDestinationSelected: shell.goBranch, leading: Padding(padding: const EdgeInsets.only(top: 18, bottom: 30), child: const CodarLogo(height: 38, onDarkBackground: true)), destinations: [for (final d in destinations) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))]), const VerticalDivider(width: 1), Expanded(child: shell)]) : shell, bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: shell.currentIndex, onDestinationSelected: shell.goBranch, destinations: [for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)])));
    });
  }
}
