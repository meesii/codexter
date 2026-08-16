import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_atoms.dart';
import 'app_spacing.dart';

enum AppToastTone { info, success, warning, error }

/// 统一 toast 工具，封装 shadcn_flutter 的 showToast，
/// 提供与 AppNotice 一致的四种语义色调
class AppToast {
  const AppToast._();

  static void info(BuildContext context, String message) {
    _show(context, message, AppToastTone.info);
  }

  static void success(BuildContext context, String message) {
    _show(context, message, AppToastTone.success);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, AppToastTone.warning);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, AppToastTone.error);
  }

  static void _show(BuildContext context, String message, AppToastTone tone) {
    showToast(
      context: context,
      builder: (toastContext, overlay) =>
          _ToastCard(message: message, tone: tone, onClose: overlay.close),
      location: ToastLocation.bottomRight,
      showDuration: const Duration(seconds: 3),
    );
  }
}

class _ToastCard extends StatelessWidget {
  final String message;
  final AppToastTone tone;
  final VoidCallback onClose;

  const _ToastCard({required this.message, required this.tone, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      AppToastTone.info => AppTones.info,
      AppToastTone.success => AppTones.success,
      AppToastTone.warning => AppTones.warning,
      AppToastTone.error => theme.colorScheme.destructive,
    };
    final icon = switch (tone) {
      AppToastTone.info => BootstrapIcons.infoCircle,
      AppToastTone.success => BootstrapIcons.checkCircle,
      AppToastTone.warning => BootstrapIcons.exclamationTriangle,
      AppToastTone.error => BootstrapIcons.xCircle,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.popover,
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          AppLineIcon(icon, size: 14, lineHeight: 15, color: color),
          const Gap(AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTones.body(
                theme,
                size: 12,
              ).copyWith(fontWeight: FontWeight.w500, height: 1.25),
            ),
          ),
          const Gap(AppSpacing.xs),
          AppIconButton(
            icon: BootstrapIcons.x,
            color: theme.colorScheme.mutedForeground,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
