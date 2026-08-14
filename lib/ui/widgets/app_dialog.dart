import 'dart:ui' as ui;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_spacing.dart';

/// 应用统一弹窗：统一提供轻量遮罩、背景模糊与 AlertDialog 内容样式。
/// 标题区始终提供右上角关闭入口，业务操作放在底部 actions。
class AppDialog {
    const AppDialog._();

    static Future<T?> show<T>({
        required BuildContext context,
        required String title,
        String? description,
        required Widget content,
        List<Widget> Function(BuildContext dialogContext)? actions,
        double maxWidth = 440,
        double? maxHeight,
        bool barrierDismissible = true,
    }) {
        final bodyMaxWidth = maxWidth > 48 ? maxWidth - 48 : maxWidth;
        final bodyMaxHeight = maxHeight == null
            ? double.infinity
            : (maxHeight > 156 ? maxHeight - 156 : maxHeight);

        return showGeneralDialog<T>(
            context: context,
            barrierDismissible: barrierDismissible,
            barrierLabel: '关闭弹窗',
            barrierColor: Colors.transparent,
            transitionDuration: const Duration(milliseconds: 160),
            pageBuilder: (dialogContext, animation, secondaryAnimation) {
                final theme = Theme.of(dialogContext);
                final dark = theme.colorScheme.brightness == Brightness.dark;
                final backdropAnimation = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                    reverseCurve: Curves.easeIn,
                );
                final dialogScale = Tween<double>(begin: 0.96, end: 1).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                );
                final scrimColor = Colors.black.withValues(alpha: dark ? 0.30 : 0.18);

                return Stack(
                    fit: StackFit.expand,
                    children: [
                        Positioned.fill(
                            child: IgnorePointer(
                                child: FadeTransition(
                                    opacity: backdropAnimation,
                                    child: ClipRect(
                                        child: BackdropFilter(
                                            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                            child: ColoredBox(color: scrimColor),
                                        ),
                                    ),
                                ),
                            ),
                        ),
                        SafeArea(
                            child: Center(
                                child: FadeTransition(
                                    opacity: backdropAnimation,
                                    child: ScaleTransition(
                                        scale: dialogScale,
                                        child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                                AlertDialog(
                                                    // 全屏遮罩由上面的 blur + scrim 统一绘制，
                                                    // 避免组件默认 80% 黑色 barrier 叠加导致背景过暗。
                                                    barrierColor: Colors.transparent,
                                                    title: Padding(
                                                        padding: const EdgeInsets.only(right: 36),
                                                        child: Text(title),
                                                    ),
                                                    content: ConstrainedBox(
                                                        constraints: BoxConstraints(
                                                            maxWidth: bodyMaxWidth,
                                                            maxHeight: bodyMaxHeight,
                                                        ),
                                                        child: ClipRect(
                                                            child: SingleChildScrollView(
                                                                // 为 3px 外扩的 focus ring 预留完整绘制空间，
                                                                // 同时继续由 ClipRect 限制正文不覆盖固定标题区。
                                                                padding: const EdgeInsets.all(AppSpacing.xs),
                                                                child: Column(
                                                                    mainAxisSize: MainAxisSize.min,
                                                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                                                    children: [
                                                                        if (description != null) ...[
                                                                            Text(
                                                                                description,
                                                                                style: AppTones.muted(
                                                                                    Theme.of(dialogContext),
                                                                                    size: 12,
                                                                                ),
                                                                            ),
                                                                            const Gap(AppSpacing.lg),
                                                                        ],
                                                                        content,
                                                                    ],
                                                                ),
                                                            ),
                                                        ),
                                                    ),
                                                    actions: actions?.call(dialogContext),
                                                ),
                                                Positioned(
                                                    top: AppSpacing.lg,
                                                    right: AppSpacing.lg,
                                                    child: Button(
                                                        style: ButtonStyle.outline(
                                                            density: ButtonDensity.icon,
                                                            size: ButtonSize.small,
                                                        ),
                                                        onPressed: () => Navigator.of(dialogContext).pop(),
                                                        child: const Icon(BootstrapIcons.x, size: 13),
                                                    ),
                                                ),
                                            ],
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ],
                );
            },
            transitionBuilder: (context, animation, secondaryAnimation, child) => child,
        );
    }

    static Future<bool> confirm({
        required BuildContext context,
        required String title,
        required String message,
        String confirmLabel = '确定',
        bool destructive = false,
    }) async {
        final result = await show<bool>(
            context: context,
            title: title,
            content: Builder(
                builder: (context) => Text(message, style: AppTones.body(Theme.of(context))),
            ),
            maxWidth: 380,
            actions: (dialogContext) => [
                Button(
                    style: ButtonStyle.outline(size: ButtonSize.normal),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                ),
                Button(
                    style: destructive
                        ? ButtonStyle.destructive(size: ButtonSize.normal)
                        : ButtonStyle.primary(size: ButtonSize.normal),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(confirmLabel),
                ),
            ],
        );
        return result ?? false;
    }
}

/// 表单类对话框的字段间距
class AppDialogFields extends StatelessWidget {
    final List<Widget> children;

    const AppDialogFields({super.key, required this.children});

    @override
    Widget build(BuildContext context) {
        final spaced = <Widget>[];
        for (var index = 0; index < children.length; index++) {
            if (index > 0) spaced.add(const Gap(AppSpacing.lg));
            spaced.add(children[index]);
        }
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced,
        );
    }
}
