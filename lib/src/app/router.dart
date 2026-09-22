// GoRouter setup: home, library, book detail, reader, records, settings.

import 'package:codar/src/presentation/book_detail/book_detail_screen.dart';
import 'package:codar/src/presentation/collections/collections_screen.dart';
import 'package:codar/src/presentation/home/home_screen.dart';
import 'package:codar/src/presentation/library/library_screen.dart';
import 'package:codar/src/presentation/reader/reader_screen.dart';
import 'package:codar/src/presentation/records/records_screen.dart';
import 'package:codar/src/presentation/settings/settings_screen.dart';
import 'package:codar/src/reader/locator_nav.dart';
import 'package:go_router/go_router.dart';

import 'shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/collections',
              builder: (c, s) => const CollectionsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (c, s) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/book/:id',
      builder: (c, s) => BookDetailScreen(bookId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/reader/:id',
      builder: (c, s) {
        final target = ReaderTarget.parse(s.uri.queryParameters);
        return ReaderScreen(
          bookId: s.pathParameters['id']!,
          initialSection: target.section,
          initialOffset: target.offset,
          initialCfi: target.cfi,
        );
      },
    ),
    GoRoute(path: '/records', builder: (c, s) => const RecordsScreen()),
  ],
);
