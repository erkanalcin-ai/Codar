import 'dart:io';

import 'package:in_app_update/in_app_update.dart';

class PlayUpdateService {
  PlayUpdateService._();

  static int? _promptedUpdateVersionCode;
  static bool _promptCheckInProgress = false;

  static Future<AppUpdateInfo?> _check() async {
    if (!Platform.isAndroid) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (_) {
      // The Play API is unavailable for sideloaded, debug, or ineligible installs.
      return null;
    }
  }

  static bool _available(AppUpdateInfo? info) {
    if (info == null) return false;
    return info.updateAvailability == UpdateAvailability.updateAvailable &&
        (info.immediateUpdateAllowed || info.flexibleUpdateAllowed);
  }

  static Future<bool> isUpdateAvailable() async => _available(await _check());

  static Future<void> promptOnStartup() async {
    if (!Platform.isAndroid || _promptCheckInProgress) return;
    _promptCheckInProgress = true;
    try {
      await _checkAndPrompt();
    } finally {
      _promptCheckInProgress = false;
    }
  }

  static Future<void> _checkAndPrompt() async {
    final info = await _check();
    if (info == null) {
      _promptedUpdateVersionCode = null;
      return;
    }

    try {
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
      } else if (_available(info)) {
        if (_promptedUpdateVersionCode == info.availableVersionCode) return;
        _promptedUpdateVersionCode = info.availableVersionCode;
        await _start(info);
      } else {
        _promptedUpdateVersionCode = null;
      }
    } catch (_) {
      // The Settings action remains available when the user cancels or Play
      // cannot complete the update flow at startup.
    }
  }

  static Future<void> startUpdate() async {
    final info = await _check();
    if (!_available(info)) return;
    await _start(info!);
  }

  static Future<void> _start(AppUpdateInfo info) async {
    if (info.immediateUpdateAllowed) {
      await InAppUpdate.performImmediateUpdate();
    } else if (info.flexibleUpdateAllowed) {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        await InAppUpdate.completeFlexibleUpdate();
      }
    }
  }
}
