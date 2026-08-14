import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';
import '../widgets/create_workspace_dialog.dart';
import '../widgets/log_timeline.dart';
import '../widgets/terminal_panel.dart';

/// 工作区详情：连接信息 + 实时日志 / 运行终端
class WorkspaceDetailPage extends StatefulWidget {
  final AppState appState;

  const WorkspaceDetailPage({super.key, required this.appState});

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final workspace = appState.selectedWorkspace;
    if (workspace == null) {
      return const AppEmptyState(icon: BootstrapIcons.folder, title: '未选择工作区');
    }

    final live = appState.isWorkspaceLive(workspace.uuid);
    final handler = appState.mcpServer.handlerOf(workspace.uuid);
    final stats = appState.workspaceStats(workspace.uuid);

    return AppPageScaffold(
      leading: AppBackButton(onPressed: appState.backToHome),
      title: workspace.name,
      subtitle: workspace.projectRoot,
      titleTrailing: _WorkspaceStatus(live: live),
      actions: [
        _WorkspaceHeaderActions(
          live: live,
          onToggle: () {
            final enable = !workspace.enabled;
            appState.toggleWorkspace(workspace.uuid, enable);
            AppToast.success(context, enable ? '工作区已启动' : '工作区已停止');
          },
          onEdit: () =>
              CreateWorkspaceDialog.showEdit(context, appState, workspace),
          onCopy: () {
            Clipboard.setData(
              ClipboardData(text: appState.workspaceUrl(workspace.uuid)),
            );
            AppToast.success(context, 'MCP 地址已复制');
          },
        ),
      ],
      child: _tabIndex == 0
          ? LogTimeline(
              entries: appState.workspaceLogs(workspace.uuid),
              toolCalls: stats.toolCalls,
              toolCount: handler?.tools.count ?? 0,
              processCount: appState.runningProcessCount(workspace.uuid),
              tabIndex: _tabIndex,
              onTabChanged: (index) => setState(() => _tabIndex = index),
              onClear: () {
                appState.clearWorkspaceLogs(workspace.uuid);
                AppToast.success(context, '日志已清除');
              },
            )
          : TerminalPanel(
              processManager: handler?.processManager,
              toolCalls: stats.toolCalls,
              toolCount: handler?.tools.count ?? 0,
              logCount: appState.workspaceLogs(workspace.uuid).length,
              processCount: appState.runningProcessCount(workspace.uuid),
              tabIndex: _tabIndex,
              onTabChanged: (index) => setState(() => _tabIndex = index),
            ),
    );
  }
}

class _WorkspaceStatus extends StatelessWidget {
  final bool live;

  const _WorkspaceStatus({required this.live});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = live ? AppTones.success : theme.colorScheme.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStatusDot(
          tone: live ? AppStatusTone.live : AppStatusTone.idle,
          size: 6,
        ),
        const Gap(AppSpacing.xs),
        Text(
          live ? '运行中' : '已停止',
          style: theme.typography.sans.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceHeaderActions extends StatelessWidget {
  static const _controlHeight = 36.0;

  final bool live;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  const _WorkspaceHeaderActions({
    required this.live,
    required this.onToggle,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppTooltip(
          message: live ? '停止工作区' : '启动工作区',
          child: SizedBox(
            width: _controlHeight,
            height: _controlHeight,
            child: Button(
              style: live
                  ? ButtonStyle.outline(
                      density: ButtonDensity.icon,
                      size: ButtonSize.normal,
                    )
                  : ButtonStyle.primary(
                      density: ButtonDensity.icon,
                      size: ButtonSize.normal,
                    ),
              onPressed: onToggle,
              child: Icon(
                live ? BootstrapIcons.stopFill : BootstrapIcons.playFill,
                size: 13,
              ),
            ),
          ),
        ),
        const Gap(AppSpacing.sm),
        AppTooltip(
          message: '修改工作区',
          child: SizedBox(
            width: _controlHeight,
            height: _controlHeight,
            child: Button(
              style: ButtonStyle.outline(
                density: ButtonDensity.icon,
                size: ButtonSize.normal,
              ),
              onPressed: onEdit,
              child: const Icon(BootstrapIcons.pencil, size: 13),
            ),
          ),
        ),
        const Gap(AppSpacing.sm),
        AppTooltip(
          message: '复制 MCP URL',
          child: SizedBox(
            width: _controlHeight,
            height: _controlHeight,
            child: Button(
              style: ButtonStyle.outline(
                density: ButtonDensity.icon,
                size: ButtonSize.normal,
              ),
              onPressed: onCopy,
              child: const Icon(BootstrapIcons.link45deg, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}
