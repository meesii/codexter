import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../theme/app_theme.dart';
import 'app_spacing.dart';

export 'app_atoms.dart';

/// 页面骨架：顶部标题栏 + 内容区，所有页面共用同一套留白与分割线
class AppPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;

  const AppPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.titleTrailing,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            title: title,
            subtitle: subtitle,
            titleTrailing: titleTrailing,
            leading: leading,
            actions: actions,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final Widget? leading;
  final List<Widget> actions;

  const _TopBar({
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppSpacing.topBarHeight,
      padding: AppSpacing.topBarPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const Gap(AppSpacing.md)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: AppTones.title(theme, size: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (titleTrailing != null) ...[const Gap(AppSpacing.sm), titleTrailing!],
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTones.mono(theme, size: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          ...actions,
        ],
      ),
    );
  }
}

/// 悬停有细微描边反馈的卡片容器
class AppCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final bool selected;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = AppSpacing.cardPadding,
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
    this.selected = false,
    this.borderColor,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interactiveHover = _hovered && widget.onTap != null;
    final surface = widget.selected
        ? AppTones.surfaceRaised(theme)
        : interactiveHover
        ? AppTones.surfaceHover(theme)
        : theme.colorScheme.card;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(
          color: widget.selected
              ? theme.colorScheme.ring.withValues(alpha: 0.52)
              : interactiveHover
              ? AppTones.borderSubtle(theme)
              : widget.borderColor ?? AppTones.borderSubtle(theme),
        ),
      ),
      child: widget.child,
    );

    return Padding(
      padding: widget.margin,
      child: MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(onTap: widget.onTap, child: card),
      ),
    );
  }
}

/// 分区小标题，带可选右侧动作
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? trailing;

  const AppSectionHeader({super.key, required this.title, this.caption, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: AppTones.title(theme, size: 13)),
          if (caption != null) ...[
            const Gap(AppSpacing.sm),
            Expanded(child: Text(caption!, style: AppTones.muted(theme, size: 11))),
          ] else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTones.surfaceSunken(theme),
                borderRadius: BorderRadius.circular(theme.radiusLg),
                border: Border.all(color: theme.colorScheme.border),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.mutedForeground),
            ),
            const Gap(AppSpacing.lg),
            Text(title, style: AppTones.title(theme, size: 14)),
            if (subtitle != null) ...[
              const Gap(AppSpacing.sm),
              Text(subtitle!, textAlign: TextAlign.center, style: AppTones.muted(theme)),
            ],
            if (action != null) ...[const Gap(AppSpacing.xl), action!],
          ],
        ),
      ),
    );
  }
}
