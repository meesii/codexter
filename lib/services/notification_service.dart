import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../app_info.dart';
import '../models/summary_notice.dart';

/// 收到 summary 后发送系统通知。平台差异统一收敛在这里。
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || (!Platform.isWindows && !Platform.isMacOS)) return;

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final windowsIcon = p.join(
      executableDir,
      'data',
      'flutter_assets',
      'assets',
      'brand',
      'logo.png',
    );
    final settings = InitializationSettings(
      macOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: appName,
        appUserModelId: 'MeeSii.Codexter.Desktop.1',
        guid: 'd5cf51e5-2c8a-4e67-a9e2-9c57e36f4195',
        iconPath: await File(windowsIcon).exists() ? windowsIcon : null,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) => _showMainWindow(),
    );
    _initialized = true;
  }

  Future<bool> requestPermissions({required bool sound}) async {
    await initialize();
    if (!Platform.isMacOS) return true;
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: sound, badge: false);
    return granted ?? false;
  }

  Future<String?> showSummary(
    SummaryNotice notice, {
    required bool sound,
  }) async {
    try {
      await initialize();
      if (!_initialized) return '当前平台不支持系统通知';
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        title: notice.title,
        body: notice.summary,
        payload: notice.workspaceUuid,
        notificationDetails: _details(
          sound: sound,
          workspaceName: notice.workspaceName,
        ),
      );
      return null;
    } catch (error) {
      debugPrint('发送系统通知失败: $error');
      return '$error';
    }
  }

  Future<String?> showTest({required bool sound}) {
    return showSummary(
      SummaryNotice(
        workspaceUuid: 'test',
        workspaceName: appName,
        title: '通知测试',
        summary: '系统通知工作正常，之后收到 summary 时会在这里提醒你。',
        endedAt: DateTime.now(),
      ),
      sound: sound,
    );
  }

  NotificationDetails _details({
    required bool sound,
    required String workspaceName,
  }) {
    return NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: sound,
        subtitle: workspaceName,
      ),
      windows: WindowsNotificationDetails(
        subtitle: workspaceName,
        audio: sound
            ? WindowsNotificationAudio.preset(
                sound: WindowsNotificationSound.defaultSound,
              )
            : WindowsNotificationAudio.silent(),
      ),
    );
  }

  Future<void> _showMainWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }
}
