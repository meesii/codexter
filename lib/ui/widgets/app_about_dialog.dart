import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../app_info.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_update_dialog.dart';

class AppAboutDialog {
  const AppAboutDialog._();

  static Future<void> show(BuildContext context, AppState appState) async {
    final packageInfo = await AppRuntimeInfo.packageInfo;
    if (!context.mounted) return;

    await AppDialog.show<void>(
      context: context,
      title: '关于 $appName',
      maxWidth: 400,
      content: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(appLogoAsset, width: 52, height: 52),
              const Gap(AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appName, style: AppTones.title(theme, size: 17)),
                    const Gap(AppSpacing.xs),
                    Text(
                      '版本 ${packageInfo.version}  ·  Build ${packageInfo.buildNumber}',
                      style: AppTones.muted(theme, size: 12),
                    ),
                    const Gap(AppSpacing.md),
                    Text('本地 MCP 工作区与工具管理客户端', style: AppTones.body(theme, size: 12)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Future<void>.microtask(() {
              if (context.mounted) {
                AppUpdateDialog.checkAndShow(context, appState);
              }
            });
          },
          child: const Text('检查更新'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
