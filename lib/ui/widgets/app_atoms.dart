import 'package:flutter/material.dart' show AdaptiveTextSelectionToolbar;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_spacing.dart';
import 'app_toast.dart';

enum AppStatusTone { live, idle, error, warn }

class AppStatusDot extends StatelessWidget {
  final AppStatusTone tone;
  final double size;

  const AppStatusDot({super.key, required this.tone, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      AppStatusTone.live => AppTones.success,
      AppStatusTone.warn => AppTones.warning,
      AppStatusTone.error => theme.colorScheme.destructive,
      AppStatusTone.idle => theme.colorScheme.mutedForeground,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: tone == AppStatusTone.idle
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
      ),
    );
  }
}

/// 图标放进与首行文字相同的行高，避免顶对齐时看起来比文字偏上。
class AppLineIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double lineHeight;

  const AppLineIcon(
    this.icon, {
    super.key,
    this.color,
    this.size = 14,
    required this.lineHeight,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: lineHeight,
      child: Align(
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

/// 轻量标签，用于来源、传输方式、状态等短文本
class AppTag extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const AppTag({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            AppLineIcon(icon!, color: tone, size: 10, lineHeight: 12),
            const Gap(AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.typography.sans.copyWith(
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一使用中文文案的文本选择右键菜单。
Widget buildAppTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final buttonItems = editableTextState.contextMenuButtonItems
      .map((item) {
        final label = switch (item.type) {
          ContextMenuButtonType.cut => '剪切',
          ContextMenuButtonType.copy => '复制',
          ContextMenuButtonType.paste => '粘贴',
          ContextMenuButtonType.selectAll => '全选',
          ContextMenuButtonType.delete => '删除',
          ContextMenuButtonType.lookUp => '查询',
          ContextMenuButtonType.searchWeb => '网页搜索',
          ContextMenuButtonType.share => '分享',
          ContextMenuButtonType.liveTextInput => '实况文本',
          ContextMenuButtonType.custom => item.label,
        };
        return label == null ? item : item.copyWith(label: label);
      })
      .toList(growable: false);

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: buttonItems,
  );
}

class AppMonoText extends StatelessWidget {
  final String data;
  final double size;
  final Color? color;
  final bool selectable;
  final int? maxLines;

  const AppMonoText(
    this.data, {
    super.key,
    this.size = 11,
    this.color,
    this.selectable = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTones.mono(theme, size: size, color: color);
    if (selectable) {
      return SelectableText(
        data,
        style: style,
        maxLines: maxLines,
        contextMenuBuilder: buildAppTextContextMenu,
      );
    }
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 图标 + 数值的一行统计信息
class AppStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;

  const AppStat({
    super.key,
    required this.icon,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppLineIcon(icon, color: tone, size: 12, lineHeight: 13.2),
        const Gap(AppSpacing.xs),
        Text(
          value,
          style: AppTones.muted(theme, size: 11).copyWith(color: tone, height: 1.2),
        ),
      ],
    );
  }
}

/// 可复制的地址条
class AppCopyField extends StatelessWidget {
  final String value;
  final IconData icon;
  final bool selectable;
  final int maxLines;
  final bool compact;

  const AppCopyField({
    super.key,
    required this.value,
    this.icon = BootstrapIcons.link45deg,
    this.selectable = false,
    this.maxLines = 1,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = AppMonoText(
      value,
      size: 11,
      selectable: selectable,
      maxLines: maxLines,
    );
    final field = Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 5, AppSpacing.xs, 5),
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppLineIcon(
            icon,
            size: 12,
            lineHeight: 16.5,
            color: theme.colorScheme.mutedForeground,
          ),
          const Gap(AppSpacing.sm),
          if (compact)
            Flexible(child: valueText)
          else
            Expanded(child: valueText),
          const Gap(AppSpacing.xs),
          AppIconButton(
            icon: BootstrapIcons.clipboard,
            tooltip: '复制',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              AppToast.success(context, '已复制到剪贴板');
            },
          ),
        ],
      ),
    );

    if (!compact) return field;
    return Align(alignment: Alignment.centerLeft, child: field);
  }
}

/// 统一气泡 Tooltip：深色背景 + 主题字体 + 箭头指针
class AppTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final AlignmentGeometry alignment;
  final AlignmentGeometry anchorAlignment;

  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.anchorAlignment = Alignment.bottomCenter,
  });

  @override
  Widget build(BuildContext context) {
    // alignment=topCenter 时，气泡实际落在元素下方；bottomCenter 时在上方。
    // side 表示气泡相对元素的位置，决定箭头朝向：上方→箭头朝下，下方→箭头朝上。
    final side = alignment == Alignment.bottomCenter
        ? _AppTooltipSide.top
        : _AppTooltipSide.bottom;
    return Tooltip(
      alignment: alignment,
      anchorAlignment: anchorAlignment,
      tooltip: (context) => _AppTooltipBubble(message: message, side: side),
      child: child,
    );
  }
}

enum _AppTooltipSide { top, bottom }

class _AppTooltipBubble extends StatelessWidget {
  final String message;
  final _AppTooltipSide side;

  const _AppTooltipBubble({required this.message, required this.side});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.primary.withValues(alpha: 0.92);
    const arrowSize = Size(10, 5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (side == _AppTooltipSide.bottom)
          CustomPaint(
            size: arrowSize,
            painter: _AppTooltipArrowPainter(color: background, side: side),
          ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(theme.radiusSm),
          ),
          child: Text(
            message,
            style: theme.typography.sans.copyWith(
              fontSize: 11,
              height: 1.4,
              color: theme.colorScheme.primaryForeground,
            ),
          ),
        ),
        if (side == _AppTooltipSide.top)
          CustomPaint(
            size: arrowSize,
            painter: _AppTooltipArrowPainter(color: background, side: side),
          ),
      ],
    );
  }
}

class _AppTooltipArrowPainter extends CustomPainter {
  final Color color;
  final _AppTooltipSide side;

  const _AppTooltipArrowPainter({required this.color, required this.side});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (side == _AppTooltipSide.top) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width / 2, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AppTooltipArrowPainter old) {
    return old.color != color || old.side != side;
  }
}

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final button = Button(
      style: ButtonStyle.outline(
        density: ButtonDensity.icon,
        size: ButtonSize.small,
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 13, color: color),
    );
    if (tooltip == null) return button;
    return AppTooltip(message: tooltip!, child: button);
  }
}

/// 带图标的文字按钮内容，避免每处重复写 Row
class AppButtonLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const AppButtonLabel({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLineIcon(icon, size: 13, lineHeight: 16),
        const Gap(AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Button(
      style: ButtonStyle.outline(
        density: ButtonDensity.icon,
        size: ButtonSize.small,
      ),
      onPressed: onPressed,
      child: const Icon(BootstrapIcons.arrowLeft, size: 13),
    );
  }
}

enum AppNoticeTone { info, success, warning, danger }

/// 页面级提示条。长日志应放 [footer] 或弹窗，避免 [detail] 撑满版面。
class AppNotice extends StatelessWidget {
  final AppNoticeTone tone;
  final String message;
  final String? detail;
  final int? detailMaxLines;
  final Widget? action;
  final Widget? footer;
  final VoidCallback? onDismiss;

  const AppNotice({
    super.key,
    required this.message,
    this.tone = AppNoticeTone.info,
    this.detail,
    this.detailMaxLines,
    this.action,
    this.footer,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      AppNoticeTone.info => AppTones.info,
      AppNoticeTone.success => AppTones.success,
      AppNoticeTone.warning => AppTones.warning,
      AppNoticeTone.danger => theme.colorScheme.destructive,
    };
    final icon = switch (tone) {
      AppNoticeTone.info => BootstrapIcons.infoCircle,
      AppNoticeTone.success => BootstrapIcons.checkCircle,
      AppNoticeTone.warning => BootstrapIcons.exclamationTriangle,
      AppNoticeTone.danger => BootstrapIcons.xCircle,
    };

    final titleStyle = AppTones.body(
      theme,
      size: 12,
    ).copyWith(fontWeight: FontWeight.w500, color: color, height: 1.25);
    final titleLine = 12.0 * 1.25;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppLineIcon(icon, size: 14, lineHeight: titleLine, color: color),
          const Gap(AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: titleStyle),
                if (detail != null) ...[
                  const Gap(AppSpacing.xs),
                  Text(
                    detail!,
                    style: AppTones.muted(theme, size: 11).copyWith(height: 1.4),
                    maxLines: detailMaxLines,
                    overflow: detailMaxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                ],
                if (footer != null) ...[const Gap(AppSpacing.sm), footer!],
              ],
            ),
          ),
          if (action != null) ...[const Gap(AppSpacing.sm), action!],
          if (onDismiss != null) ...[
            const Gap(AppSpacing.xs),
            Button(
              style: ButtonStyle.outline(
                density: ButtonDensity.icon,
                size: ButtonSize.small,
              ),
              onPressed: onDismiss,
              child: Icon(BootstrapIcons.x, size: 13, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

/// 输入框聚焦描边：保持 shadcn 的 3px ring 结构，但降低颜色强度。
class AppInputFocusTheme extends StatelessWidget {
  final Widget child;

  const AppInputFocusTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ComponentTheme<FocusOutlineTheme>(
      data: FocusOutlineTheme(
        align: 3,
        border: Border.all(
          color: theme.colorScheme.ring.withValues(alpha: 0.22),
          width: 3,
        ),
      ),
      child: child,
    );
  }
}

/// 带标签的表单字段
class AppField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? placeholder;
  final TextEditingController controller;
  final int? maxLines;
  final Widget? trailing;
  final bool obscure;

  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.placeholder,
    this.maxLines = 1,
    this.trailing,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = AppInputFocusTheme(
      child: ComponentTheme<TextFieldTheme>(
        data: TextFieldTheme(
          border: Border.all(
            color: theme.colorScheme.border.withValues(alpha: 0.68),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(theme.radiusMd),
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          obscureText: obscure,
          placeholder: placeholder == null ? null : Text(placeholder!),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTones.label(theme)),
        const Gap(AppSpacing.sm),
        if (trailing == null)
          field
        else
          Row(
            children: [
              Expanded(child: field),
              const Gap(AppSpacing.sm),
              trailing!,
            ],
          ),
        if (hint != null) ...[
          const Gap(AppSpacing.sm),
          Text(hint!, style: AppTones.muted(theme, size: 11)),
        ],
      ],
    );
  }
}

/// 可点击的外部链接文字
class AppLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const AppLink({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Text(
          label,
          style: AppTones.body(theme, size: 12).copyWith(
            color: AppTones.info,
            decoration: TextDecoration.underline,
            decorationColor: AppTones.info.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
