// Riverpod providers: database, repositories, services, UI state.

import 'package:codar/src/db/database.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/backup_service.dart';
import 'package:codar/src/library/enrichment_service.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/library/reconcile_service.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final databaseProvider = FutureProvider<CodarDatabase>((ref) async {
  final db = await CodarDatabase.open();
  ref.onDispose(() => db.close());
  return db;
});

final booksRepoProvider = Provider<BooksRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return BooksRepository(db);
});

final progressRepoProvider = Provider<ProgressRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return ProgressRepository(db);
});

final annotationsRepoProvider = Provider<AnnotationsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return AnnotationsRepository(db);
});

final libraryRepoProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return LibraryRepository(db);
});

final settingsRepoProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SettingsRepository(db);
});

final readerServiceProvider = Provider<CodarReaderService>((ref) {
  final svc = CodarReaderService();
  svc.init();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(
    reader: ref.watch(readerServiceProvider),
    books: ref.watch(booksRepoProvider),
    storage: CodarLibStorage(),
  );
});

final enrichmentServiceProvider = Provider<EnrichmentService>((ref) {
  return EnrichmentService(books: ref.watch(booksRepoProvider));
});

final backupServiceProvider = Provider<BackupService>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return BackupService(db);
});

/// One-shot silent reconcile of externally deleted CodarLib files.
/// Watched by Home/Library so it runs once per launch; failures are
/// swallowed (never block the UI, never purge on uncertain data).
final reconcileProvider = FutureProvider<int>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final books = BooksRepository(db);
  final reader = ref.watch(readerServiceProvider);
  final import = ImportService(
      reader: reader, books: books, storage: CodarLibStorage());
  final purged = await reconcileExternalDeletions(
      books: books, import: import, storage: CodarLibStorage());
  if (purged > 0) ref.read(libraryRefreshProvider.notifier).bump();
  return purged;
});

/// Active locale code ('tr' default). Persisted in app_settings.
class LocaleNotifier extends Notifier<String> {
  @override
  String build() => 'tr';

  void set(String value) => state = value;
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

/// Reader typography/theme. Loaded once, updated through settings screen.
class ReaderSettingsNotifier extends Notifier<ReaderSettingsData> {
  @override
  ReaderSettingsData build() => ReaderSettingsData.fromMap({});

  void set(ReaderSettingsData value) => state = value;
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettingsData>(
        ReaderSettingsNotifier.new);

/// Library list state.
class LibraryQuery {
  const LibraryQuery(
      {this.text = '',
      this.order = 'recent',
      this.grid = true,
      this.onlyFavorites = false});
  final String text;
  final String order;
  final bool grid;
  final bool onlyFavorites;

  LibraryQuery copyWith(
          {String? text, String? order, bool? grid, bool? onlyFavorites}) =>
      LibraryQuery(
        text: text ?? this.text,
        order: order ?? this.order,
        grid: grid ?? this.grid,
        onlyFavorites: onlyFavorites ?? this.onlyFavorites,
      );
}

class LibraryQueryNotifier extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void set(LibraryQuery value) => state = value;
}

final libraryQueryProvider =
    NotifierProvider<LibraryQueryNotifier, LibraryQuery>(
        LibraryQueryNotifier.new);

final booksListProvider = FutureProvider<List<BookRecord>>((ref) async {
  ref.watch(libraryRefreshProvider);
  final q = ref.watch(libraryQueryProvider);
  final repo = ref.watch(booksRepoProvider);
  return repo.listBooks(
      query: q.text, order: q.order, onlyFavorites: q.onlyFavorites);
});

/// Bump to refresh library lists after import/delete/favorite changes.
class LibraryRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final libraryRefreshProvider =
    NotifierProvider<LibraryRefreshNotifier, int>(LibraryRefreshNotifier.new);
