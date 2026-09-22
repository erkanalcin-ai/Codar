// Settings: compact, row-based controls over the existing preferences.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _deleteFileDefault;
  bool? _enrichOnline;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = ref.read(settingsRepoProvider);
      final deleteDefault =
          await settings.appValue('delete_file_default', '1') == '1';
      final enrich = await settings.appValue('enrich_online', '0') == '1';
      if (!mounted) return;
      setState(() {
        _deleteFileDefault = deleteDefault;
        _enrichOnline = enrich;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    return Theme(
      data: CodarColors.dark(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: CodarColors.navyDeep,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: CodarColors.background,
          appBar: AppBar(
            title: Text(tr(locale, 'settings')),
            actions: [
              IconButton(
                tooltip: tr(locale, 'readerSettings'),
                icon: const Icon(Icons.text_fields_rounded),
                onPressed: () => _showReaderSettings(locale, readerSettings),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    _SettingsGroup(
                      title: tr(locale, 'appLanguage'),
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.language_rounded,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'appLanguage')),
                          subtitle: Text(locale == 'tr' ? 'Türkçe' : 'English'),
                          trailing: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: locale,
                              icon: const Icon(Icons.expand_more_rounded),
                              items: const [
                                DropdownMenuItem(
                                  value: 'tr',
                                  child: Text('Türkçe'),
                                ),
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                ref.read(localeProvider.notifier).set(value);
                                await ref
                                    .read(settingsRepoProvider)
                                    .setAppValue('locale', value);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      title: tr(locale, 'readerSettings'),
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.auto_stories_rounded,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'readerSettings')),
                          subtitle: Text(
                            '${tr(locale, 'fontSize')}: ${readerSettings.fontSizePx} · '
                            '${_themeLabel(locale, readerSettings.theme)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              _showReaderSettings(locale, readerSettings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      title: tr(locale, 'storageSettings'),
                      children: [
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.delete_sweep_outlined,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'deleteFileDefault')),
                          value: _deleteFileDefault ?? true,
                          onChanged: _deleteFileDefault == null
                              ? null
                              : (value) async {
                                  setState(() => _deleteFileDefault = value);
                                  await ref
                                      .read(settingsRepoProvider)
                                      .setAppValue(
                                        'delete_file_default',
                                        value ? '1' : '0',
                                      );
                                },
                        ),
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.image_search_outlined,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'enrichOnline')),
                          subtitle: Text(tr(locale, 'enrichHint')),
                          value: _enrichOnline ?? false,
                          onChanged: _enrichOnline == null
                              ? null
                              : (value) async {
                                  setState(() => _enrichOnline = value);
                                  await ref
                                      .read(settingsRepoProvider)
                                      .setAppValue(
                                        'enrich_online',
                                        value ? '1' : '0',
                                      );
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      title: tr(locale, 'backupSettings'),
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.backup_outlined,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'backupSettings')),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: tr(locale, 'backupExport'),
                                icon: const Icon(Icons.upload_outlined),
                                onPressed: _busy
                                    ? null
                                    : () => _exportBackup(locale),
                              ),
                              IconButton(
                                tooltip: tr(locale, 'backupImport'),
                                icon: const Icon(Icons.download_outlined),
                                onPressed: _busy
                                    ? null
                                    : () => _importBackup(locale),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: CodarLogo(height: 240, onDarkBackground: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cap(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static String _themeLabel(String locale, String theme) =>
      tr(locale, 'theme${_cap(theme)}');

  Future<void> _showReaderSettings(
    String locale,
    ReaderSettingsData initial,
  ) async {
    var draft = initial;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(ReaderSettingsData next) {
            draft = next;
            setSheetState(() {});
            _update(ref, next);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(locale, 'readerSettings'),
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  _Row(
                    label: tr(locale, 'fontFamily'),
                    child: DropdownButton<String>(
                      value: draft.fontFamily,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: const ['System', 'Serif', 'Monospace']
                          .map(
                            (font) => DropdownMenuItem(
                              value: font,
                              child: Text(font),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          update(draft.copyWith(fontFamily: value ?? 'System')),
                    ),
                  ),
                  _SliderRow(
                    label: tr(locale, 'fontSize'),
                    value: draft.fontSizePx.toDouble(),
                    min: 12,
                    max: 32,
                    divisions: 20,
                    display: '${draft.fontSizePx}',
                    onChanged: (value) =>
                        update(draft.copyWith(fontSizePx: value.round())),
                  ),
                  _SliderRow(
                    label: tr(locale, 'lineHeight'),
                    value: draft.lineHeight,
                    min: 1,
                    max: 2.2,
                    divisions: 12,
                    display: draft.lineHeight.toStringAsFixed(2),
                    onChanged: (value) =>
                        update(draft.copyWith(lineHeight: value)),
                  ),
                  _SliderRow(
                    label: tr(locale, 'margin'),
                    value: draft.marginPx.toDouble(),
                    min: 8,
                    max: 96,
                    divisions: 11,
                    display: '${draft.marginPx}',
                    onChanged: (value) =>
                        update(draft.copyWith(marginPx: value.round())),
                  ),
                  _Row(
                    label: tr(locale, 'alignment'),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'start',
                            label: Text(tr(locale, 'alignStart')),
                          ),
                          ButtonSegment(
                            value: 'center',
                            label: Text(tr(locale, 'alignCenter')),
                          ),
                          ButtonSegment(
                            value: 'justify',
                            label: Text(tr(locale, 'alignJustify')),
                          ),
                        ],
                        selected: {draft.alignment},
                        onSelectionChanged: (value) =>
                            update(draft.copyWith(alignment: value.first)),
                      ),
                    ),
                  ),
                  _Row(
                    label: tr(locale, 'theme'),
                    child: DropdownButton<String>(
                      value: draft.theme,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final theme in [
                          'light',
                          'dark',
                          'sepia',
                          'warm',
                          'black',
                        ])
                          DropdownMenuItem(
                            value: theme,
                            child: Text(tr(locale, 'theme${_cap(theme)}')),
                          ),
                      ],
                      onChanged: (value) =>
                          update(draft.copyWith(theme: value ?? 'light')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _update(WidgetRef ref, ReaderSettingsData next) async {
    ref.read(readerSettingsProvider.notifier).set(next);
    await ref.read(settingsRepoProvider).saveReaderSettings(next);
  }

  Future<void> _exportBackup(String locale) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(backupServiceProvider).exportBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(locale, saved ? 'backupOk' : 'cancel'))),
      );
    } on BackupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(locale, 'backupFailed')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup(String locale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(tr(locale, 'restoreConfirmQ')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(locale, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(locale, 'backupImport')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final counts = await ref.read(backupServiceProvider).importBackup();
      ref.read(libraryRefreshProvider.notifier).bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            counts.isEmpty ? tr(locale, 'cancel') : tr(locale, 'restoreOk'),
          ),
        ),
      );
    } on BackupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(locale, 'restoreFailed')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CodarColors.gold,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ColoredBox(
            color: CodarColors.surface,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension ReaderSettingsCopy on ReaderSettingsData {
  ReaderSettingsData copyWith({
    String? fontFamily,
    int? fontSizePx,
    double? lineHeight,
    int? marginPx,
    String? alignment,
    String? theme,
  }) => ReaderSettingsData(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSizePx: fontSizePx ?? this.fontSizePx,
    lineHeight: lineHeight ?? this.lineHeight,
    marginPx: marginPx ?? this.marginPx,
    alignment: alignment ?? this.alignment,
    theme: theme ?? this.theme,
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 112, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 44, child: Text(display)),
        ],
      ),
    );
  }
}
