// Settings: compact, row-based controls over the existing preferences.

import 'dart:async';

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/app/play_update_service.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final _privacyPolicyUri = Uri.parse(
  'https://erkanalcin-ai.github.io/Codar/privacy.html',
);
const _appChannel = MethodChannel('codar/app');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _deleteFileDefault;
  bool? _enrichOnline;
  String? _appVersion;
  bool _updateAvailable = false;
  bool _updateBusy = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadAppVersion());
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final available = await PlayUpdateService.isUpdateAvailable();
    if (!mounted) return;
    setState(() => _updateAvailable = available);
  }

  Future<void> _startUpdate() async {
    if (_updateBusy) return;
    setState(() => _updateBusy = true);
    try {
      await PlayUpdateService.startUpdate();
    } catch (_) {
      // Play can reject an update request when this install is not eligible.
    } finally {
      if (mounted) {
        setState(() => _updateBusy = false);
        unawaited(_checkForUpdate());
      }
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final version = await _appChannel.invokeMapMethod<String, String>(
        'getAppVersion',
      );
      final name = version?['name'];
      final code = version?['code'];
      if (!mounted || name == null || code == null) return;
      setState(() => _appVersion = '$name ($code)');
    } catch (_) {}
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
          appBar: AppBar(title: Text(tr(locale, 'settings'))),
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
                    const SizedBox(height: 12),
                    _SettingsGroup(
                      title: tr(locale, 'privacyPolicy'),
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.privacy_tip_outlined,
                            color: CodarColors.gold,
                          ),
                          title: Text(tr(locale, 'privacyPolicy')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openPrivacyPolicy(locale),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CodarLogo(height: 240, onDarkBackground: true),
                    if (_appVersion != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${tr(locale, 'appVersion')} $_appVersion',
                            style: const TextStyle(
                              color: CodarColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_updateAvailable) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _updateBusy ? null : _startUpdate,
                              style: TextButton.styleFrom(
                                foregroundColor: CodarColors.gold,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: _updateBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.system_update_alt,
                                      size: 16,
                                    ),
                              label: Text(tr(locale, 'update')),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _openPrivacyPolicy(String locale) async {
    final opened = await launchUrl(
      _privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(locale, 'privacyPolicyOpenFailed'))),
      );
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
