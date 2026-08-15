import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../stores/app_state.dart';
import '../../app_info.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'app_update_dialog.dart';
import 'settings_dialog.dart';

/// 左侧导航：品牌区 + 工作区列表 + 全局管理入口 + 服务状态
class AppSidebar extends StatelessWidget {
  final AppState appState;
  final VoidCallback onCreateWorkspace;

  const AppSidebar({
    super.key,
    required this.appState,
    required this.onCreateWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        border: Border(right: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(appState: appState),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupLabel(
                    label: '工作区',
                    trailing: AppIconButton(
                      icon: BootstrapIcons.plus,
                      tooltip: '新建工作区',
                      onPressed: onCreateWorkspace,
                    ),
                  ),
                  ..._workspaceItems(),
                  const Gap(AppSpacing.lg),
                  const _GroupLabel(label: '全局'),
                  _NavItem(
                    icon: BootstrapIcons.puzzle,
                    label: 'Skills',
                    badge: _enabledSkillCount,
                    active: _isActive(AppPage.skills),
                    onPressed: () => appState.setCurrentPage(AppPage.skills),
                  ),
                  _NavItem(
                    icon: BootstrapIcons.hddRack,
                    label: '下游 MCP',
                    badge: _enabledMcpCount,
                    active: _isActive(AppPage.mcpManage),
                    onPressed: () => appState.setCurrentPage(AppPage.mcpManage),
                  ),
                  _NavItem(
                    icon: BootstrapIcons.gear,
                    label: '全局设置',
                    active: false,
                    onPressed: () => SettingsDialog.show(context, appState),
                  ),
                  _NavItem(
                    icon: BootstrapIcons.activity,
                    label: '环境检查',
                    active: _isActive(AppPage.doctor),
                    onPressed: () => appState.setCurrentPage(AppPage.doctor),
                  ),
                ],
              ),
            ),
          ),
          _ServiceFooter(appState: appState),
        ],
      ),
    );
  }

  String? get _enabledSkillCount {
    final count = appState.skills.where((skill) => skill.enabled).length;
    return count == 0 ? null : '$count';
  }

  String? get _enabledMcpCount {
    final count = appState.mcps.where((mcp) => mcp.enabled).length;
    return count == 0 ? null : '$count';
  }

  bool _isActive(AppPage page) {
    return appState.selectedWorkspaceUuid == null &&
        appState.currentPage == page;
  }

  List<Widget> _workspaceItems() {
    if (appState.workspaces.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Builder(
            builder: (context) => Text(
              '还没有工作区',
              style: AppTones.muted(Theme.of(context), size: 11),
            ),
          ),
        ),
      ];
    }

    return appState.workspaces.map((workspace) {
      final live = appState.isWorkspaceLive(workspace.uuid);
      final activeTool = appState.activeTool(workspace.uuid);
      final latestTool = appState.latestTool(workspace.uuid);
      final processing =
          live && (activeTool != null || (latestTool?.pending ?? false));
      final caption = !live
          ? '已停止'
          : activeTool != null
          ? '正在执行 ${activeTool.purpose ?? activeTool.title}'
          : latestTool?.pending == true && latestTool?.toolName == 'summary'
          ? '正在整理本轮结果'
          : latestTool?.toolName == 'summary' && latestTool?.pending == false
          ? '本轮已完成'
          : '等待调用';
      return _NavItem(
        leading: AppStatusDot(
          tone: live ? AppStatusTone.live : AppStatusTone.idle,
          size: 7,
          glow: processing,
        ),
        label: workspace.name,
        caption: caption,
        active: appState.selectedWorkspaceUuid == workspace.uuid,
        onPressed: () => appState.selectWorkspace(workspace.uuid),
      );
    }).toList();
  }
}

class _BrandHeader extends StatelessWidget {
  final AppState appState;

  const _BrandHeader({required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Row(
        children: [
          Image.asset(
            appLogoAsset,
            width: 24,
            height: 24,
            filterQuality: FilterQuality.medium,
          ),
          const Gap(AppSpacing.sm),
          Expanded(
            child: Row(
              children: [
                Text(appName, style: AppTones.title(theme, size: 13)),
                const Gap(AppSpacing.xs),
                Flexible(
                  child: FutureBuilder<String>(
                    future: AppRuntimeInfo.versionLabel,
                    builder: (context, snapshot) => Text(
                      snapshot.data ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTones.muted(theme, size: 9),
                    ),
                  ),
                ),
                if (appState.availableUpdate != null) ...[
                  const Gap(AppSpacing.xs),
                  _UpdateBadge(
                    version: appState.availableUpdate!.version,
                    onPressed: () =>
                        AppUpdateDialog.showAvailable(context, appState),
                  ),
                ],
              ],
            ),
          ),
          AppIconButton(
            icon: appState.darkMode ? BootstrapIcons.sun : BootstrapIcons.moon,
            tooltip: appState.darkMode ? '切换浅色' : '切换深色',
            onPressed: () {
              appState.toggleDarkMode();
              AppToast.info(
                context,
                appState.darkMode ? '已切换至深色模式' : '已切换至浅色模式',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UpdateBadge extends StatefulWidget {
  final String version;
  final VoidCallback onPressed;

  const _UpdateBadge({required this.version, required this.onPressed});

  @override
  State<_UpdateBadge> createState() => _UpdateBadgeState();
}

class _UpdateBadgeState extends State<_UpdateBadge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTones.interaction(theme);
    return AppTooltip(
      message: '发现 Codexter v${widget.version}，点击更新',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: _hovered ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(theme.radiusSm),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(BootstrapIcons.arrowUpCircle, size: 10, color: color),
                const Gap(3),
                Text(
                  '更新',
                  style: theme.typography.sans.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const _GroupLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        0,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.typography.sans.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final String? caption;
  final String? badge;
  final bool active;
  final VoidCallback onPressed;

  const _NavItem({
    required this.label,
    required this.active,
    required this.onPressed,
    this.icon,
    this.leading,
    this.caption,
    this.badge,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.active
        ? AppTones.interactionSurface(theme)
        : _hovered
        ? theme.colorScheme.foreground.withValues(alpha: 0.07)
        : Colors.transparent;
    final foreground = widget.active
        ? AppTones.interaction(theme)
        : _hovered
        ? theme.colorScheme.foreground
        : theme.colorScheme.mutedForeground;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      opaque: true,
      onEnter: (_) => _setHovered(true),
      onHover: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          height: widget.caption == null ? 38 : null,
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(theme.radiusMd),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Center(
                  child:
                      widget.leading ??
                      Icon(widget.icon, size: 14, color: foreground),
                ),
              ),
              const Gap(AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: widget.caption == null
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.sans.copyWith(
                        fontSize: 12.5,
                        fontWeight: widget.active
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: widget.active
                            ? theme.colorScheme.foreground
                            : theme.colorScheme.foreground.withValues(
                                alpha: 0.85,
                              ),
                      ),
                    ),
                    if (widget.caption != null)
                      Text(
                        widget.caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTones.muted(theme, size: 10),
                      ),
                  ],
                ),
              ),
              if (widget.badge != null) ...[
                const Gap(AppSpacing.xs),
                AppTag(label: widget.badge!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }
}

class _ServiceFooter extends StatelessWidget {
  final AppState appState;

  const _ServiceFooter({required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverTone = appState.serverRunning
        ? AppStatusTone.live
        : AppStatusTone.error;
    final tunnelTone = !appState.config.useCloudflared
        ? AppStatusTone.warn
        : appState.tunnelRunning
        ? AppStatusTone.live
        : AppStatusTone.error;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(
            tone: serverTone,
            icon: LucideIcons.server,
            label: '本地服务',
            value: appState.serverRunning
                ? '${appState.config.host}:${appState.config.port}'
                : '服务尚未启动',
          ),
          const Gap(AppSpacing.sm),
          _StatusCard(
            tone: tunnelTone,
            icon: LucideIcons.cloud,
            label: 'Tunnel',
            value: !appState.config.useCloudflared
                ? '公网访问已关闭'
                : appState.config.domain.isEmpty
                ? '尚未配置域名'
                : appState.config.domain,
            action: AppTooltip(
              message: '重启 Tunnel',
              alignment: Alignment.bottomCenter,
              anchorAlignment: Alignment.topCenter,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Button(
                  style: ButtonStyle.secondary(
                    density: ButtonDensity.icon,
                    size: ButtonSize.small,
                  ),
                  onPressed: appState.busy || !appState.config.useCloudflared
                      ? null
                      : () async {
                          await appState.restartTunnel();
                          if (!context.mounted) return;
                          if (appState.lastError == null) {
                            AppToast.success(context, 'Tunnel 已重启');
                          } else {
                            AppToast.error(
                              context,
                              '重启失败：${appState.lastErrorSummary}',
                            );
                          }
                        },
                  child: const Icon(BootstrapIcons.arrowRepeat, size: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatefulWidget {
  static const _height = 60.0;
  static const _iconSize = 32.0;

  final AppStatusTone tone;
  final IconData icon;
  final String label;
  final String value;
  final Widget? action;

  const _StatusCard({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    this.action,
  });

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColor = switch (widget.tone) {
      AppStatusTone.live => AppTones.success,
      AppStatusTone.warn => AppTones.warning,
      AppStatusTone.error => theme.colorScheme.destructive,
      AppStatusTone.idle => theme.colorScheme.mutedForeground,
    };
    final baseSurface = AppTones.serviceCardSurface(theme);
    final surface = Color.alphaBlend(
      theme.colorScheme.foreground.withValues(alpha: _hovered ? 0.025 : 0),
      baseSurface,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: _StatusCard._height,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(theme.radiusMd),
          border: Border.all(
            color: _hovered
                ? AppTones.borderSubtle(theme)
                : AppTones.borderFaint(theme),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _StatusCard._iconSize,
              height: _StatusCard._iconSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: _StatusCard._iconSize,
                    height: _StatusCard._iconSize,
                    decoration: BoxDecoration(
                      color: toneColor.withValues(
                        alpha: _hovered ? 0.13 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(theme.radiusMd),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 16,
                      color: toneColor.withValues(alpha: 0.94),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: surface,
                        shape: BoxShape.circle,
                      ),
                      child: AppStatusDot(tone: widget.tone, size: 6),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTones.body(
                      theme,
                      size: 11.5,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Gap(2),
                  AppTooltip(
                    message: widget.value,
                    alignment: Alignment.bottomCenter,
                    anchorAlignment: Alignment.topCenter,
                    child: AppMonoText(
                      widget.value,
                      size: 10.5,
                      maxLines: 1,
                      color: theme.colorScheme.foreground.withValues(
                        alpha: 0.72,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.action != null) ...[
              const Gap(AppSpacing.sm),
              Center(child: widget.action!),
            ],
          ],
        ),
      ),
    );
  }
}
