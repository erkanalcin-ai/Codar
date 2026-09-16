// Shared book widgets: cover tile with graceful fallback.

import 'dart:io';

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookCover extends ConsumerWidget {
  const BookCover({super.key, required this.book, this.width = 96, this.height = 144});

  final BookRecord book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.watch(booksRepoProvider).coverPath(book.bookId),
      builder: (context, snap) {
        final path = snap.data;
        if (path != null && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(path),
                width: width, height: height, fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _fallback(context)),
          );
        }
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            book.title.isEmpty ? '—' : book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
