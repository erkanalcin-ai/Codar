import 'package:codar/src/brand/codar_brand.dart';
import 'package:flutter/material.dart';

enum LibraryImportMode { files, folder }

class LibraryImportSourceSheet extends StatelessWidget {
  const LibraryImportSourceSheet({
    super.key,
    required this.filesLabel,
    required this.folderLabel,
    required this.onSelected,
  });

  final String filesLabel;
  final String folderLabel;
  final ValueChanged<LibraryImportMode> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: CodarColors.gold,
                foregroundColor: CodarColors.background,
              ),
              onPressed: () => onSelected(LibraryImportMode.files),
              icon: const Icon(Icons.insert_drive_file_outlined),
              label: Text(filesLabel),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: CodarColors.gold,
                side: const BorderSide(color: CodarColors.gold),
              ),
              onPressed: () => onSelected(LibraryImportMode.folder),
              icon: const Icon(Icons.folder_outlined),
              label: Text(folderLabel),
            ),
          ),
        ],
      ),
    ),
  );
}
