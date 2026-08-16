import 'dart:async';
import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app_info.dart';
import '../../services/update_service.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';

class AppUpdateDialog {
  const AppUpdateDialog._();

  static Future<void> checkAndShow(
    BuildContext context,
    AppState appState,
  ) async {
    AppToast.info(context, '正在检查更新…');
    try {
      final result = await appState.checkForUpdates();
      if (!context.mounted) return;
      if (!result.hasUpdate) {
        AppToast.success(context, '当前已是最新版本 v${result.currentVersion}');
        return;
      }

      await _showPrompt(
        context,
        appState,
        currentVersion: result.currentVersion,
        update: result.latest,
      );
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, _friendlyError(error));
    }
  }

  static Future<void> showAvailable(
    BuildContext context,
    AppState appState,
  ) async {
    final update = appState.availableUpdate;
    if (update == null) {
      await checkAndShow(context, appState);
      return;
    }
    final currentVersion = await AppRuntimeInfo.version;
    if (!context.mounted) return;
    await _showPrompt(
      context,
      appState,
      currentVersion: currentVersion,
      update: update,
    );
  }

  static Future<void> _showPrompt(
    BuildContext context,
    AppState appState, {
    required String currentVersion,
    required AppUpdateInfo update,
  }) {
    return AppDialog.show<void>(
      context: context,
      title: '发现新版本',
      maxWidth: 420,
      content: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Codexter v${update.version}',
                style: AppTones.title(theme, size: 16),
              ),
              const Gap(AppSpacing.sm),
              Text(
                '当前版本 v$currentVersion，下载完成后将打开安装程序，并关闭 Codexter。请按安装向导完成升级。',
                style: AppTones.muted(theme, size: 12),
              ),
            ],
          );
        },
      ),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('稍后'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Future<void>.microtask(() {
              if (context.mounted) {
                _showDownload(context, appState, update);
              }
            });
          },
          child: const Text('立即更新'),
        ),
      ],
    );
  }

  static Future<void> _showDownload(
    BuildContext context,
    AppState appState,
    AppUpdateInfo update,
  ) {
    return AppDialog.show<void>(
      context: context,
      title: '正在更新 Codexter',
      maxWidth: 420,
      barrierDismissible: false,
      scrollContent: false,
      showCloseButton: false,
      content: _UpdateDownloadContent(
        service: appState.updateService,
        appState: appState,
        update: update,
      ),
    );
  }

  static String _friendlyError(Object error) {
    final text = '$error';
    if (text.contains('HTTP 404')) {
      return '更新源不可访问；如果源码仓库是私有仓库，需要配置独立的公开更新源';
    }
    return text.replaceFirst('Exception: ', '');
  }
}

class _UpdateDownloadContent extends StatefulWidget {
  final AppUpdateService service;
  final AppState appState;
  final AppUpdateInfo update;

  const _UpdateDownloadContent({
    required this.service,
    required this.appState,
    required this.update,
  });

  @override
  State<_UpdateDownloadContent> createState() => _UpdateDownloadContentState();
}

class _UpdateDownloadContentState extends State<_UpdateDownloadContent> {
  double? _progress = 0;
  String _status = '准备下载…';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      setState(() => _status = '正在下载安装包…');
      final installer = await widget.service.downloadInstaller(
        widget.update,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _progress = 1;
        _status = '校验完成，正在打开安装程序…';
      });
      await widget.service.launchInstaller(installer);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await widget.appState.shutdown();
      exit(0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _status = '更新失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error == null) ...[
          Progress(progress: _progress),
          const Gap(AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(_status, style: AppTones.body(theme, size: 12)),
              ),
              if (_progress != null)
                Text(
                  '${(_progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: AppTones.mono(theme, size: 11),
                ),
            ],
          ),
        ] else ...[
          Text(
            _error!,
            style: AppTones.body(
              theme,
              size: 12,
              color: theme.colorScheme.destructive,
            ),
          ),
          const Gap(AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: Button(
              style: ButtonStyle.outline(size: ButtonSize.normal),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ),
        ],
      ],
    );
  }
}
