import 'dart:math';

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/widgets/app_components.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _HomeQuote {
  const _HomeQuote(this.tr, this.en, this.author);
  final String tr;
  final String en;
  final String author;
}

const _homeQuotes = <_HomeQuote>[
  _HomeQuote('İnsan ne ile yaşar?', 'What do people live by?', 'Leo Tolstoy'),
  _HomeQuote(
    'Bütün mutlu aileler birbirine benzer.',
    'All happy families are alike.',
    'Leo Tolstoy',
  ),
  _HomeQuote(
    'Okumak, kadınlar için yazılmış bir özgürlük biçimidir.',
    'Reading is a form of freedom.',
    'Virginia Woolf',
  ),
  _HomeQuote(
    'Dünyayı değiştirmek için kitaplardan daha güçlü bir araç yoktur.',
    'There is no friend as loyal as a book.',
    'Ernest Hemingway',
  ),
  _HomeQuote(
    'Bir kitabın sayfaları arasında başka bir hayat buluruz.',
    'A reader lives a thousand lives before he dies.',
    'George R. R. Martin',
  ),
  _HomeQuote(
    'Bütün büyük kitaplar, bizi kendimize geri getirir.',
    'All great books bring us back to ourselves.',
    'James Baldwin',
  ),
  _HomeQuote(
    'Bir kitap, cebinizde taşıdığınız bir bahçedir.',
    'A book is a garden carried in the pocket.',
    'Chinese Proverb',
  ),
  _HomeQuote(
    'Kitaplar, insanın en sessiz ve en kalıcı dostlarıdır.',
    'Books are the quietest and most constant of friends.',
    'Charles William Eliot',
  ),
  _HomeQuote(
    'Bir kitap kadar sadık dost yoktur.',
    'There is no friend as loyal as a book.',
    'Ernest Hemingway',
  ),
  _HomeQuote(
    'Kitap okumak, başkalarının zihinleriyle konuşmaktır.',
    'Reading is a conversation with the minds of others.',
    'Plato',
  ),
  _HomeQuote(
    'Bir kitap, dünyaya açılan bir penceredir.',
    'A book is a window into the world.',
    'Anne Frank',
  ),
  _HomeQuote(
    'Kitaplar, insanlığın ortak hafızasıdır.',
    'Books are humanity’s shared memory.',
    'Umberto Eco',
  ),
  _HomeQuote(
    'Sonsuzluk, bir kitabın içinde saklı olabilir.',
    'Infinity may be hidden inside a book.',
    'Jorge Luis Borges',
  ),
  _HomeQuote(
    'Bir hikâye, başkasının gözleriyle görmeyi öğretir.',
    'A story teaches us to see through another’s eyes.',
    'Madeleine L’Engle',
  ),
  _HomeQuote(
    'İyi bir kitap, son sayfasından sonra da yaşamaya devam eder.',
    'A good book lives on after its last page.',
    'J. K. Rowling',
  ),
  _HomeQuote(
    'Okumak, zihni besleyen düşünceli bir yolculuktur.',
    'Reading is a thoughtful journey that nourishes the mind.',
    'Marcus Tullius Cicero',
  ),
  _HomeQuote(
    'Kitaplar, zamanın içinden bize uzanan ellerdir.',
    'Books are hands reaching to us through time.',
    'Carl Sagan',
  ),
  _HomeQuote(
    'Bir kitap bazen hayatın yönünü değiştirir.',
    'A book can sometimes change the direction of a life.',
    'Oprah Winfrey',
  ),
  _HomeQuote(
    'Hikâyeler, yalnız olmadığımızı hatırlatır.',
    'Stories remind us that we are not alone.',
    'C. S. Lewis',
  ),
  _HomeQuote(
    'Okumak, hayatı daha derinden yaşamaktır.',
    'Reading is living life more deeply.',
    'Gustave Flaubert',
  ),
  _HomeQuote(
    'Kitaplar, ruhun sessiz dostlarıdır.',
    'Books are the quiet friends of the soul.',
    'William Wordsworth',
  ),
  _HomeQuote(
    'Bir cümle, uzun bir düşüncenin kapısını açabilir.',
    'A sentence can open the door to a long thought.',
    'Ralph Waldo Emerson',
  ),
  _HomeQuote(
    'İyi kitaplar bizi merakla baş başa bırakır.',
    'Good books leave us face to face with curiosity.',
    'Albert Einstein',
  ),
  _HomeQuote(
    'Okumak, dünyayı yeniden adlandırmaktır.',
    'Reading is naming the world anew.',
    'Toni Morrison',
  ),
  _HomeQuote(
    'Her kitap, yeni bir bakış açısı armağan eder.',
    'Every book offers a new point of view.',
    'Henry David Thoreau',
  ),
  _HomeQuote(
    'Bir kitap, zihnin kendisiyle yaptığı sohbettir.',
    'A book is a conversation the mind has with itself.',
    'Plutarch',
  ),
  _HomeQuote(
    'İyi bir hikâye, gerçeği daha görünür kılar.',
    'A good story makes truth more visible.',
    'John Steinbeck',
  ),
  _HomeQuote(
    'Kitaplar, unutulmuş soruları yeniden uyandırır.',
    'Books awaken forgotten questions.',
    'Franz Kafka',
  ),
  _HomeQuote(
    'Okur, her sayfada kendinden bir iz bulur.',
    'A reader finds a trace of themselves on every page.',
    'Marcel Proust',
  ),
  _HomeQuote(
    'Hayal gücü, bilgiden daha önemlidir.',
    'Imagination is more important than knowledge.',
    'Albert Einstein',
  ),
  _HomeQuote(
    'Bir kitap, yalnız geçirilen zamanı anlamlı kılar.',
    'A book gives meaning to time spent alone.',
    'Sylvia Plath',
  ),
  _HomeQuote(
    'Düşünmeden okumak, sindirmeden yemeye benzer.',
    'Reading without reflection is like eating without digesting.',
    'Edmund Burke',
  ),
  _HomeQuote(
    'Kitaplar, hayatın kısa yol haritalarıdır.',
    'Books are short maps of life.',
    'Francis Bacon',
  ),
  _HomeQuote(
    'Okumak, başkasının deneyiminden bilgelik devşirmektir.',
    'Reading is gathering wisdom from another life.',
    'Ralph Waldo Emerson',
  ),
  _HomeQuote(
    'Her hikâyede kendimizi biraz daha tanırız.',
    'In every story, we come to know ourselves a little better.',
    'Hermann Hesse',
  ),
  _HomeQuote(
    'Bir kitapla geçirilen akşam, boşa geçmiş sayılmaz.',
    'An evening spent with a book is never wasted.',
    'Charles Dickens',
  ),
  _HomeQuote(
    'Kitaplar geçmişi taşır, geleceği hayal ettirir.',
    'Books carry the past and let us imagine the future.',
    'Ray Bradbury',
  ),
  _HomeQuote(
    'Merak, bütün iyi okumaların ilk cümlesidir.',
    'Curiosity is the first sentence of every good reading.',
    'Neil Gaiman',
  ),
  _HomeQuote(
    'İyi bir hikâye biter; yankısı kalır.',
    'A good story ends; its echo remains.',
    'William Shakespeare',
  ),
  _HomeQuote(
    'Okumaya ayrılan zaman, hayata eklenir.',
    'Time given to reading is added to life.',
    'Mason Cooley',
  ),
  _HomeQuote(
    'Kitap kadar sadık bir dost yoktur.',
    'There is no frigate like a book.',
    'Emily Dickinson',
  ),
  _HomeQuote(
    'Bir sayfa, bazen yeni bir başlangıçtır.',
    'A page can sometimes be a new beginning.',
    'Louisa May Alcott',
  ),
];

final _homeQuoteProvider = Provider<_HomeQuote>((ref) {
  return _homeQuotes[Random().nextInt(_homeQuotes.length)];
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final quote = ref.watch(_homeQuoteProvider);
    final db = ref.watch(databaseProvider);
    ref.watch(reconcileProvider);
    return Scaffold(
      backgroundColor: CodarColors.background,
      body: db.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: CodarColors.gold),
        ),
        error: (e, _) =>
            Center(child: Text('${tr(locale, 'errorPrefix')}: $e')),
        data: (_) => RefreshIndicator(
          color: CodarColors.gold,
          backgroundColor: CodarColors.surface,
          onRefresh: () async {
            ref.invalidate(_homeDataProvider);
            ref.read(libraryRefreshProvider.notifier).bump();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _HomeHeroBanner(locale: locale)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      locale == 'tr' ? '“${quote.tr}”' : '“${quote.en}”',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CodarColors.brightGold,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      quote.author,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CodarColors.gold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _ContinueSection(locale: locale),
                    const SizedBox(height: 34),
                    _HomeShelf(
                      title: tr(locale, 'recentlyAdded'),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _homeDataProvider = FutureProvider<void>((ref) async {
  ref.watch(libraryRefreshProvider);
});

class _ContinueBookData {
  const _ContinueBookData({
    required this.book,
    required this.progress,
    required this.quote,
  });

  final BookRecord book;
  final double progress;
  final String quote;
}

final _homeContinueProvider = FutureProvider<List<_ContinueBookData>>((
  ref,
) async {
  ref.watch(libraryRefreshProvider);
  final books = await ref.watch(booksRepoProvider).continueReading(limit: 10);
  final progressRepo = ref.watch(progressRepoProvider);
  final annotations = ref.watch(annotationsRepoProvider);

  return Future.wait(
    books.map((book) async {
      final progress = await progressRepo.loadProgress(book.bookId);
      final highlights = await annotations.allHighlights(book.bookId);
      final quote = highlights
          .map((highlight) => highlight.quotedText.trim())
          .firstWhere((text) => text.isNotEmpty, orElse: () => '');
      final noteQuotes = quote.isEmpty
          ? await annotations.allNotes(book.bookId)
          : const <NoteRecord>[];
      final resolvedQuote = quote.isNotEmpty
          ? quote
          : noteQuotes
                .map((note) => note.quotedText.trim())
                .firstWhere((text) => text.isNotEmpty, orElse: () => '');
      return _ContinueBookData(
        book: book,
        progress: (progress?.progression ?? 0).clamp(0.0, 1.0).toDouble(),
        quote: resolvedQuote,
      );
    }),
  );
});

class _ContinueSection extends ConsumerStatefulWidget {
  const _ContinueSection({required this.locale});
  final String locale;

  @override
  ConsumerState<_ContinueSection> createState() => _ContinueSectionState();
}

class _ContinueSectionState extends ConsumerState<_ContinueSection> {
  final _controller = PageController(viewportFraction: 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_homeDataProvider);
    final continueBooks = ref.watch(_homeContinueProvider);
    return continueBooks.when(
      loading: () => const SizedBox(
        height: 240,
        child: Center(
          child: CircularProgressIndicator(color: CodarColors.gold),
        ),
      ),
      error: (error, _) => Text('$error'),
      data: (items) {
        if (items.isEmpty) return _EmptyContinue(locale: widget.locale);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HomeSectionHeader(title: 'OKUMAYA DEVAM ET'),
            const SizedBox(height: 14),
            Transform.translate(
              offset: const Offset(-12, 0),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width - 16,
                height: 194,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: items.length,
                  itemBuilder: (c, i) => _ContinueBookCard(
                    item: items[i],
                    onContinue: () => context.push(
                      '/reader/${Uri.encodeComponent(items[i].book.bookId)}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ContinueBookCard extends StatelessWidget {
  const _ContinueBookCard({required this.item, required this.onContinue});

  final _ContinueBookData item;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final book = item.book;
    final theme = Theme.of(context);
    final progressLabel = '${(item.progress * 100).round()}% tamamlandı';
    final quote = item.quote.isEmpty
        ? 'Bu kitaptan seçtiğin alıntılar burada görünecek.'
        : '“${item.quote}”';

    return Material(
      color: CodarColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onContinue,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              BookCover(book: book, width: 82, height: 172),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title.isEmpty ? '—' : book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: CodarColors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (book.author.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: CodarColors.secondaryText,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        progressLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: CodarColors.brightGold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      ProgressIndicatorLine(value: item.progress),
                      const Spacer(),
                      Text(
                        quote,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: item.quote.isEmpty
                              ? CodarColors.muted
                              : CodarColors.secondaryText,
                          fontStyle: FontStyle.italic,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                          ),
                          label: const Text('DEVAM ET'),
                          style: TextButton.styleFrom(
                            foregroundColor: CodarColors.brightGold,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: CodarColors.primaryText,
              fontWeight: FontWeight.w700,
              letterSpacing: .35,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: CodarColors.brightGold,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(action!),
          ),
      ],
    );
  }
}

class _HomeHeroBanner extends StatelessWidget {
  const _HomeHeroBanner({required this.locale});

  final String locale;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Codar',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/brand/codar_home_hero_background.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xEC080A0D),
                      Color(0x9A080A0D),
                      Color(0x18080A0D),
                    ],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9080A0D)],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 18,
                child: const CodarLogo(height: 120, onDarkBackground: true),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr(locale, 'library'),
                      onPressed: () => context.go('/library'),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: tr(locale, 'settings'),
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyContinue extends StatelessWidget {
  const _EmptyContinue({required this.locale});
  final String locale;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.go('/library'),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CodarColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            color: CodarColors.gold,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              tr(locale, 'emptyFavorites'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: CodarColors.secondaryText,
          ),
        ],
      ),
    ),
  );
}

class _HomeShelf extends ConsumerWidget {
  const _HomeShelf({required this.title});
  final String title;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_homeDataProvider);
    final repo = ref.watch(booksRepoProvider);
    final future = repo.recentlyAdded(limit: 10);
    return FutureBuilder<List<BookRecord>>(
      future: future,
      builder: (context, snap) {
        final books = (snap.data ?? const <BookRecord>[]).take(10).toList();
        if (books.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HomeSectionHeader(
              title: title,
              action: 'TÜMÜ',
              onAction: () => context.go('/library'),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = ((constraints.maxWidth - 24) / 3).clamp(
                  88.0,
                  150.0,
                );
                final height = width * 1.48;
                return SizedBox(
                  height: height,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: books.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (c, i) => Semantics(
                      button: true,
                      label: '${books[i].title}, ${books[i].author}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push(
                          '/book/${Uri.encodeComponent(books[i].bookId)}',
                        ),
                        child: BookCover(
                          book: books[i],
                          width: width,
                          height: height,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
