import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/mcp_log_entry.dart';
import '../../models/workspace.dart';
import '../../stores/app_state.dart';
import '../../utils/fmt.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';
import '../widgets/create_workspace_dialog.dart';
import '../widgets/json_view.dart';

/// 主页：所有工作区的实时状态卡片
class HomePage extends StatelessWidget {
  final AppState appState;

  const HomePage({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final workspaceCount = appState.workspaces.length;
    final liveCount = appState.workspaces
        .where((workspace) => appState.isWorkspaceLive(workspace.uuid))
        .length;

    return AppPageScaffold(
      title: '工作区',
      subtitle: workspaceCount == 0 ? null : '$liveCount / $workspaceCount 运行中',
      actions: [
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () => CreateWorkspaceDialog.show(context, appState),
          child: const AppButtonLabel(
            icon: BootstrapIcons.plus,
            label: '新建工作区',
          ),
        ),
      ],
      child: workspaceCount == 0 ? _buildEmpty(context) : _buildList(context),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final empty = AppEmptyState(
      icon: BootstrapIcons.folder2Open,
      title: '还没有工作区',
      subtitle: '创建工作区后会得到一个不可猜测的 UUID 地址，把它填进 ChatGPT 的 MCP 设置即可使用。',
      action: Button(
        style: ButtonStyle.primary(size: ButtonSize.normal),
        onPressed: () => CreateWorkspaceDialog.show(context, appState),
        child: const AppButtonLabel(icon: BootstrapIcons.plus, label: '新建工作区'),
      ),
    );
    if (appState.lastError == null) return empty;
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [_buildErrorNotice(context), const Gap(AppSpacing.x3l), empty],
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount:
          appState.workspaces.length + (appState.lastError == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (appState.lastError != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: _buildErrorNotice(context),
          );
        }
        final offset = appState.lastError == null ? 0 : 1;
        final workspace = appState.workspaces[index - offset];
        return WorkspaceCard(appState: appState, workspace: workspace);
      },
    );
  }

  Widget _buildErrorNotice(BuildContext context) {
    return AppNotice(
      tone: AppNoticeTone.danger,
      message: appState.lastErrorIsTunnel ? 'Tunnel 未能连接' : '服务启动失败',
      detail: appState.lastErrorSummary,
      detailMaxLines: 2,
      onDismiss: appState.clearError,
      footer: Row(
        children: [
          Button(
            style: ButtonStyle.outline(size: ButtonSize.small),
            onPressed: () => _showTunnelLog(context),
            child: const Text('查看日志'),
          ),
          const Gap(AppSpacing.sm),
          Button(
            style: ButtonStyle.outline(size: ButtonSize.small),
            onPressed: appState.busy ? null : () => _retryStart(context),
            child: Text(appState.busy ? '重试中…' : '重试'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryStart(BuildContext context) async {
    await appState.restartServices();
    if (!context.mounted) return;
    if (appState.lastError == null) {
      AppToast.success(context, '服务已重启');
    } else {
      AppToast.error(context, '重启失败：${appState.lastErrorSummary}');
    }
  }

  void _showTunnelLog(BuildContext context) {
    AppDialog.show(
      context: context,
      title: 'Tunnel 日志',
      maxWidth: 720,
      maxHeight: 520,
      content: ConsoleView(
        text: appState.tunnelService.logTail,
        maxHeight: 360,
      ),
    );
  }
}

class WorkspaceCard extends StatelessWidget {
  final AppState appState;
  final Workspace workspace;

  const WorkspaceCard({
    super.key,
    required this.appState,
    required this.workspace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = appState.isWorkspaceLive(workspace.uuid);
    final stats = appState.workspaceStats(workspace.uuid);
    final toolLogs = appState
        .workspaceLogs(workspace.uuid)
        .where((entry) => entry.isToolCall)
        .toList(growable: false);
    final recent = toolLogs.length <= 4
        ? toolLogs
        : toolLogs.sublist(toolLogs.length - 4);
    final currentErrorCount = toolLogs
        .where((entry) => !entry.pending && !entry.success)
        .length;

    return AppCard(
      onTap: () => appState.selectWorkspace(workspace.uuid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: live
                        ? AppTones.success
                        : theme.colorScheme.mutedForeground,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Gap(AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(workspace.name, style: AppTones.title(theme)),
                      AppTooltip(
                        message: workspace.projectRoot,
                        child: AppMonoText(
                          workspace.projectRoot,
                          size: 11,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTag(
                      label: live ? '运行中' : '已停止',
                      color: live ? AppTones.success : null,
                    ),
                    const Gap(AppSpacing.md),
                    Switch(
                      value: workspace.enabled,
                      onChanged: (value) =>
                          appState.toggleWorkspace(workspace.uuid, value),
                    ),
                    const Gap(AppSpacing.md),
                    _WorkspaceMoreButton(
                      onEdit: () => CreateWorkspaceDialog.showEdit(
                        context,
                        appState,
                        workspace,
                      ),
                      onDelete: () => _confirmDelete(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.md),
          Row(
            children: [
              AppStat(
                icon: BootstrapIcons.lightning,
                value: '${stats.toolCalls} 次调用',
              ),
              const Gap(AppSpacing.lg),
              AppStat(
                icon: BootstrapIcons.terminal,
                value: '${appState.runningProcessCount(workspace.uuid)} 个进程',
              ),
              const Gap(AppSpacing.lg),
              AppStat(
                icon: BootstrapIcons.exclamationCircle,
                value: '$currentErrorCount 次异常',
                color: currentErrorCount > 0
                    ? theme.colorScheme.destructive
                    : null,
              ),
              if (stats.lastActiveAt != null) ...[
                const Gap(AppSpacing.lg),
                AppStat(
                  icon: BootstrapIcons.clock,
                  value: Fmt.clock(stats.lastActiveAt!),
                ),
              ],
            ],
          ),
          if (recent.isNotEmpty) ...[
            const Gap(AppSpacing.md),
            _RecentActivity(entries: recent),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '删除工作区',
      message: '确定删除「${workspace.name}」吗？运行中的进程会被停止，日志将被清空。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!context.mounted) return;
    if (confirmed) {
      await appState.deleteWorkspace(workspace.uuid);
      if (!context.mounted) return;
      AppToast.success(context, '工作区已删除');
    }
  }
}

class _WorkspaceMoreButton extends StatefulWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WorkspaceMoreButton({required this.onEdit, required this.onDelete});

  @override
  State<_WorkspaceMoreButton> createState() => _WorkspaceMoreButtonState();
}

class _WorkspaceMoreButtonState extends State<_WorkspaceMoreButton> {
  bool _menuOpen = false;

  Future<void> _showMenu() async {
    if (_menuOpen) return;
    setState(() => _menuOpen = true);
    final result = showDropdown<void>(
      context: context,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      builder: (_) => SizedBox(
        width: 148,
        child: DropdownMenu(
          surfaceOpacity: 0.98,
          surfaceBlur: 12,
          children: [
            MenuButton(
              onPressed: (_) => widget.onEdit(),
              child: const Row(
                children: [
                  Icon(BootstrapIcons.pencil, size: 13),
                  Gap(AppSpacing.sm),
                  Text('修改工作区'),
                ],
              ),
            ),
            const MenuDivider(),
            MenuButton(
              onPressed: (_) => widget.onDelete(),
              child: Row(
                children: [
                  Icon(
                    BootstrapIcons.trash,
                    size: 13,
                    color: Theme.of(context).colorScheme.destructive,
                  ),
                  const Gap(AppSpacing.sm),
                  Text(
                    '删除工作区',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.destructive,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    try {
      await result.future;
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: BootstrapIcons.threeDots,
      tooltip: '更多操作',
      onPressed: _showMenu,
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final List<McpLogEntry> entries;

  const _RecentActivity({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((entry) => _ActivityLine(entry: entry)).toList(),
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final McpLogEntry entry;

  const _ActivityLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = entry.purpose ?? entry.argsSummary;
    final rawArgs = entry.argsSummary;
    final activityText = entry.purpose != null
        ? Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTones.body(
              theme,
              size: 10,
              color: theme.colorScheme.mutedForeground,
            ),
          )
        : AppMonoText(displayText, size: 10);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          AppStatusDot(
            tone: entry.pending
                ? AppStatusTone.warn
                : entry.success
                ? AppStatusTone.live
                : AppStatusTone.error,
            size: 5,
          ),
          const Gap(AppSpacing.sm),
          SizedBox(width: 56, child: AppMonoText(entry.clockText, size: 10)),
          SizedBox(
            width: 104,
            child: AppMonoText(
              entry.title,
              size: 10,
              color: theme.colorScheme.foreground,
            ),
          ),
          Expanded(
            child: entry.purpose != null && rawArgs.isNotEmpty
                ? AppTooltip(message: rawArgs, child: activityText)
                : activityText,
          ),
          const Gap(AppSpacing.sm),
          AppMonoText(
            entry.pending ? '…' : entry.durationText,
            size: 10,
            color: entry.pending
                ? AppTones.warning
                : AppTones.metricText(theme),
          ),
        ],
      ),
    );
  }
}
