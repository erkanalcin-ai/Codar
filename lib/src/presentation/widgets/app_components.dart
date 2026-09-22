import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/library/book_actions.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({super.key, required this.hint, required this.onChanged, this.value = '', this.onClear});
  final String hint; final String value; final ValueChanged<String> onChanged; final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => TextField(onChanged: onChanged, style: const TextStyle(color: CodarColors.primaryText), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: CodarColors.muted), prefixIcon: const Icon(Icons.search_rounded, color: CodarColors.secondaryText), suffixIcon: value.isEmpty ? null : IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded))));
}

class AppChip extends StatelessWidget {
  const AppChip({super.key, required this.label, required this.selected, required this.onSelected});
  final String label; final bool selected; final ValueChanged<bool> onSelected;
  @override
  Widget build(BuildContext context) => FilterChip(label: Text(label), selected: selected, onSelected: onSelected, checkmarkColor: CodarColors.brightGold, labelStyle: TextStyle(color: selected ? CodarColors.brightGold : CodarColors.secondaryText));
}

class ProgressIndicatorLine extends StatelessWidget {
  const ProgressIndicatorLine({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 4, color: CodarColors.gold, backgroundColor: CodarColors.divider));
}

class BookCard extends ConsumerWidget {
  const BookCard({super.key, required this.book, this.variant = BookCardVariant.grid, this.onTap});
  final BookRecord book; final BookCardVariant variant; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = onTap ?? () => context.push('/book/${Uri.encodeComponent(book.bookId)}');
    return Semantics(button: true, label: '${book.title}, ${book.author}', child: InkWell(borderRadius: BorderRadius.circular(14), onTap: action, onLongPress: () => showBookActionsSheet(context, ref, book), child: switch (variant) {
      BookCardVariant.horizontal => _horizontal(context),
      BookCardVariant.grid => _grid(context),
    }));
  }
  Widget _grid(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: BookCover(book: book, width: double.infinity, height: double.infinity)), const SizedBox(height: 8), Text(book.title.isEmpty ? '—' : book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.titleSmall), if (book.author.isNotEmpty) Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.bodySmall)]);
  Widget _horizontal(BuildContext c) => Row(children: [BookCover(book: book, width: 86, height: 124), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(book.title.isEmpty ? '—' : book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.titleMedium), if (book.author.isNotEmpty) Text(book.author, style: Theme.of(c).textTheme.bodyMedium), const SizedBox(height: 14), const ProgressIndicatorLine(value: .42)]))]);
}

enum BookCardVariant { horizontal, grid }
