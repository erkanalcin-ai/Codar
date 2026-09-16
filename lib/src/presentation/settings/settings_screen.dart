// Settings: app language + reader typography/theme.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final rs = ref.watch(readerSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr(locale, 'settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr(locale, 'appLanguage'),
              style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'tr', label: Text('Türkçe')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {locale},
            onSelectionChanged: (s) async {
              ref.read(localeProvider.notifier).set(s.first);
              await ref
                  .read(settingsRepoProvider)
                  .setAppValue('locale', s.first);
            },
          ),
          const SizedBox(height: 24),
          Text(tr(locale, 'readerSettings'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(
            label: tr(locale, 'fontFamily'),
            child: DropdownButton<String>(
              value: rs.fontFamily,
              items: const ['System', 'Serif', 'Monospace']
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) =>
                  _update(ref, rs.copyWith(fontFamily: v ?? 'System')),
            ),
          ),
          _SliderRow(
            label: tr(locale, 'fontSize'),
            value: rs.fontSizePx.toDouble(),
            min: 12,
            max: 32,
            divisions: 20,
            display: '${rs.fontSizePx}',
            onChanged: (v) =>
                _update(ref, rs.copyWith(fontSizePx: v.round())),
          ),
          _SliderRow(
            label: tr(locale, 'lineHeight'),
            value: rs.lineHeight,
            min: 1.0,
            max: 2.2,
            divisions: 12,
            display: rs.lineHeight.toStringAsFixed(2),
            onChanged: (v) => _update(ref, rs.copyWith(lineHeight: v)),
          ),
          _SliderRow(
            label: tr(locale, 'margin'),
            value: rs.marginPx.toDouble(),
            min: 8,
            max: 96,
            divisions: 11,
            display: '${rs.marginPx}',
            onChanged: (v) =>
                _update(ref, rs.copyWith(marginPx: v.round())),
          ),
          _Row(
            label: tr(locale, 'alignment'),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'start', label: Text(tr(locale, 'alignStart'))),
                ButtonSegment(
                    value: 'center', label: Text(tr(locale, 'alignCenter'))),
                ButtonSegment(
                    value: 'justify', label: Text(tr(locale, 'alignJustify'))),
              ],
              selected: {rs.alignment},
              onSelectionChanged: (s) =>
                  _update(ref, rs.copyWith(alignment: s.first)),
            ),
          ),
          const SizedBox(height: 8),
          _Row(
            label: tr(locale, 'theme'),
            child: DropdownButton<String>(
              value: rs.theme,
              items: [
                for (final t in [
                  'light',
                  'dark',
                  'sepia',
                  'warm',
                  'black'
                ])
                  DropdownMenuItem(
                      value: t, child: Text(tr(locale, 'theme${_cap(t)}'))),
              ],
              onChanged: (v) =>
                  _update(ref, rs.copyWith(theme: v ?? 'light')),
            ),
          ),
        ],
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _update(WidgetRef ref, ReaderSettingsData next) async {
    ref.read(readerSettingsProvider.notifier).set(next);
    await ref.read(settingsRepoProvider).saveReaderSettings(next);
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
  }) =>
      ReaderSettingsData(
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
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label)),
          Expanded(child: child),
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
          SizedBox(width: 140, child: Text(label)),
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
          SizedBox(width: 48, child: Text(display)),
        ],
      ),
    );
  }
}
