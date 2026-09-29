// Shared book widgets: cover tile with graceful fallback.

import 'dart:io';

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookCover extends ConsumerWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 96,
    this.height = 144,
    this.showTitleFallback = true,
  });

  final BookRecord book;
  final double width;
  final double height;
  final bool showTitleFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.watch(booksRepoProvider).coverPath(book.bookId),
      builder: (context, snap) {
        final path = snap.data;
        if (path != null && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(path),
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _fallback(context),
            ),
          );
        }
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    return BookCoverFallback(
      title: book.title,
      author: book.author,
      format: book.format,
      width: width,
      height: height,
      showTitle: showTitleFallback,
    );
  }
}

class BookCoverFallback extends StatelessWidget {
  const BookCoverFallback({
    super.key,
    required this.title,
    required this.author,
    required this.format,
    required this.width,
    required this.height,
    this.showTitle = true,
  });

  final String title;
  final String author;
  final String format;
  final double width;
  final double height;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              CodarColors.navy,
              scheme.brightness == Brightness.dark
                  ? CodarColors.navyDeep
                  : CodarColors.charcoal,
            ],
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              color: CodarColors.gold,
              size: width < 60 ? 20 : 28,
            ),
            const SizedBox(height: 8),
            if (showTitle) ...[
              Text(
                title.isEmpty ? '—' : title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (author.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                ),
              ],
            ] else
              Text(
                format.isEmpty ? 'BOOK' : format.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String formatDate(int millis, String locale) {
  if (millis <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}
