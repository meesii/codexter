import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';

class CloseWindowDecision {
  final bool minimizeToTray;
  final bool remember;

  const CloseWindowDecision({required this.minimizeToTray, required this.remember});
}

class CloseWindowDialog {
  const CloseWindowDialog._();

  static Future<CloseWindowDecision?> show(BuildContext context) {
    var remember = false;
    return AppDialog.show<CloseWindowDecision>(
      context: context,
      title: '关闭 Codexter',
      description: '关闭窗口后，你希望 Codexter 如何处理？',
      maxWidth: 420,
      barrierDismissible: false,
      content: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChoiceHint(
                icon: BootstrapIcons.windowStack,
                title: '最小化到托盘',
                description: '继续运行 MCP、Tunnel 和后台任务，可从系统托盘重新打开。',
              ),
              const Gap(AppSpacing.sm),
              _ChoiceHint(
                icon: BootstrapIcons.power,
                title: '退出应用',
                description: '停止服务和后台进程，并完全退出 Codexter。',
              ),
              const Gap(AppSpacing.lg),
              Checkbox(
                state: remember ? CheckboxState.checked : CheckboxState.unchecked,
                onChanged: (_) => setState(() => remember = !remember),
                trailing: const Text('记住我的选择，下次不再询问'),
              ),
            ],
          );
        },
      ),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(CloseWindowDecision(minimizeToTray: false, remember: remember)),
          child: const Text('退出应用'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(CloseWindowDecision(minimizeToTray: true, remember: remember)),
          child: const Text('最小化到托盘'),
        ),
      ],
    );
  }
}

class _ChoiceHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ChoiceHint({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: theme.colorScheme.mutedForeground),
        ),
        const Gap(AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTones.body(theme).copyWith(fontWeight: FontWeight.w600)),
              const Gap(2),
              Text(description, style: AppTones.muted(theme, size: 11)),
            ],
          ),
        ),
      ],
    );
  }
}
