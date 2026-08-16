import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/downstream_mcp_entry.dart';
import '../../services/capability_manager.dart';
import '../../services/downstream_client.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_spacing.dart';
import '../widgets/json_view.dart';
import '../widgets/app_toast.dart';

/// 下游 MCP 全局管理：导入 / 添加 / 启停 / 重连，并显示真实连接状态
class McpManagePage extends StatefulWidget {
  final AppState appState;

  const McpManagePage({super.key, required this.appState});

  @override
  State<McpManagePage> createState() => _McpManagePageState();
}

class _McpManagePageState extends State<McpManagePage> {
  final _capabilityManager = CapabilityManager();
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final mcps = widget.appState.mcps;
    final enabledCount = mcps.where((mcp) => mcp.enabled).length;

    return AppPageScaffold(
      title: '下游 MCP',
      subtitle: mcps.isEmpty ? null : '共 ${mcps.length} 个，$enabledCount 个启用',
      actions: [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: _importing ? null : _importFromCodex,
          child: AppButtonLabel(
            icon: _importing ? BootstrapIcons.hourglassSplit : BootstrapIcons.download,
            label: _importing ? '导入中…' : '从 Codex 导入',
          ),
        ),
        const Gap(AppSpacing.sm),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () => _openEditor(context),
          child: const AppButtonLabel(icon: BootstrapIcons.plus, label: '添加'),
        ),
      ],
      child: mcps.isEmpty ? _buildEmpty() : _buildList(context, mcps),
    );
  }

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: BootstrapIcons.hddRack,
      title: '暂无下游 MCP',
      subtitle: '启用后 ChatGPT 可以通过 mcp_call 调用这些服务器的工具。',
      action: Button(
        style: ButtonStyle.outline(size: ButtonSize.normal),
        onPressed: _importing ? null : _importFromCodex,
        child: const AppButtonLabel(icon: BootstrapIcons.download, label: '从 Codex 导入'),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<DownstreamMcpEntry> mcps) {
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: mcps.length,
      itemBuilder: (context, index) {
        final mcp = mcps[index];
        return _McpTile(
          entry: mcp,
          client: widget.appState.capabilities.clientOf(mcp.name),
          onToggle: (value) => widget.appState.toggleMcp(mcp.name, value),
          onReconnect: () async {
            AppToast.info(context, '正在重连 ${mcp.name}…');
            try {
              await widget.appState.reconnectMcp(mcp.name);
            } catch (error) {
              if (!context.mounted) return;
              AppToast.error(context, '重连失败：$error');
            }
          },
          onDetails: () => _openDetails(
            context,
            entry: mcp,
            client: widget.appState.capabilities.clientOf(mcp.name),
          ),
          onEdit: () => _openEditor(context, entry: mcp),
          onDelete: () => _confirmDelete(context, mcp),
        );
      },
    );
  }

  Future<void> _importFromCodex() async {
    setState(() => _importing = true);

    try {
      final scanned = await _capabilityManager.scanCodexMcps();
      var imported = 0;
      for (final item in scanned) {
        final existing = widget.appState.mcps.firstWhereOrNull((mcp) => mcp.name == item.name);
        if (existing != null) continue;
        await widget.appState.saveMcp(
          DownstreamMcpEntry(
            name: item.name,
            transportJson: jsonEncode(item.transport),
            enabled: item.enabled,
            source: 'codex_import',
            startupTimeoutMs: item.startupTimeoutMs,
            toolTimeoutMs: item.toolTimeoutMs,
          ),
        );
        imported++;
      }
      if (mounted) {
        AppToast.success(context, '扫描到 ${scanned.length} 个，新导入 $imported 个');
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, '导入失败：$error');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, DownstreamMcpEntry entry) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '删除下游 MCP',
      message: '确定删除「${entry.name}」吗？连接会立即断开。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!context.mounted) return;
    if (confirmed) {
      await widget.appState.deleteMcp(entry.name);
      if (!context.mounted) return;
      AppToast.success(context, '下游 MCP 已删除');
    }
  }

  Future<void> _openDetails(
    BuildContext context, {
    required DownstreamMcpEntry entry,
    required DownstreamClient? client,
  }) async {
    final searchController = TextEditingController();
    var query = '';

    await AppDialog.show<void>(
      context: context,
      title: entry.name,
      description: 'MCP 连接与工具',
      maxWidth: 620,
      maxHeight: 620,
      content: StatefulBuilder(
        builder: (context, setLocalState) {
          final allTools = client?.tools ?? const <Map<String, dynamic>>[];
          final normalized = query.trim().toLowerCase();
          final tools = normalized.isEmpty
              ? allTools
              : allTools.where((tool) {
                  final name = '${tool['name'] ?? ''}'.toLowerCase();
                  final description = '${tool['description'] ?? ''}'.toLowerCase();
                  return name.contains(normalized) || description.contains(normalized);
                }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _McpSummaryPanel(entry: entry, client: client),
              const Gap(AppSpacing.lg),
              Row(
                children: [
                  Expanded(child: Text('工具', style: AppTones.title(Theme.of(context), size: 13))),
                  Text(
                    '${tools.length}/${allTools.length}',
                    style: AppTones.muted(Theme.of(context), size: 11),
                  ),
                  if (allTools.isNotEmpty) ...[
                    const Gap(AppSpacing.md),
                    SizedBox(
                      width: 200,
                      child: AppInputFocusTheme(
                        child: TextField(
                          controller: searchController,
                          placeholder: const Text('搜索工具…'),
                          features: const [
                            InputFeature.leading(Icon(BootstrapIcons.search, size: 12)),
                          ],
                          onChanged: (value) => setLocalState(() => query = value),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Gap(AppSpacing.md),
              if (allTools.isEmpty)
                Text(
                  client?.isConnected == true ? '此 MCP 未暴露工具' : '连接后显示工具详情',
                  style: AppTones.muted(Theme.of(context), size: 12),
                )
              else if (tools.isEmpty)
                Text('没有匹配的工具', style: AppTones.muted(Theme.of(context), size: 12))
              else
                ...tools.map(
                  (tool) => _McpToolItem(tool: tool, onTap: () => _openToolDetails(context, tool)),
                ),
            ],
          );
        },
      ),
    );

    searchController.dispose();
  }

  Future<void> _openToolDetails(BuildContext context, Map<String, dynamic> tool) async {
    final name = '${tool['name'] ?? '未命名工具'}';
    final description = '${tool['description'] ?? ''}'.trim();
    await AppDialog.show<void>(
      context: context,
      title: name,
      description: description.isEmpty ? '工具定义' : description,
      maxWidth: 560,
      maxHeight: 520,
      content: JsonView(label: 'TOOL DEFINITION', data: tool, maxHeight: 340),
    );
  }

  Future<void> _openEditor(BuildContext context, {DownstreamMcpEntry? entry}) async {
    final nameController = TextEditingController(text: entry?.name ?? '');
    final commandController = TextEditingController(text: entry?.command ?? '');
    final argsController = TextEditingController(text: entry?.args.join(' ') ?? '');
    final urlController = TextEditingController(text: entry?.url ?? '');
    var useStdio = entry?.isUrl != true;

    await AppDialog.show<void>(
      context: context,
      title: entry == null ? '添加下游 MCP' : '编辑下游 MCP',
      description: '支持 STDIO 子进程与 streamable HTTP 两种传输',
      maxWidth: 520,
      content: StatefulBuilder(
        builder: (context, setLocalState) => AppDialogFields(
          children: [
            AppField(label: '名称', controller: nameController, placeholder: 'my-mcp'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('传输方式', style: AppTones.label(Theme.of(context))),
                const Gap(AppSpacing.sm),
                ButtonGroup(
                  children: [
                    SelectedButton(
                      value: useStdio,
                      onChanged: (selected) {
                        if (selected) {
                          setLocalState(() => useStdio = true);
                        }
                      },
                      style: const ButtonStyle.outline(),
                      selectedStyle: const ButtonStyle.primary(),
                      disableTransition: true,
                      child: const Text('STDIO'),
                    ),
                    SelectedButton(
                      value: !useStdio,
                      onChanged: (selected) {
                        if (selected) {
                          setLocalState(() => useStdio = false);
                        }
                      },
                      style: const ButtonStyle.outline(),
                      selectedStyle: const ButtonStyle.primary(),
                      disableTransition: true,
                      child: const Text('HTTP'),
                    ),
                  ],
                ),
              ],
            ),
            if (useStdio) ...[
              AppField(label: '启动命令', controller: commandController, placeholder: 'node'),
              AppField(
                label: '参数（空格分隔）',
                controller: argsController,
                placeholder: 'server.js --port 3000',
              ),
            ] else
              AppField(
                label: 'URL',
                controller: urlController,
                placeholder: 'https://api.example.com/mcp',
              ),
          ],
        ),
      ),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () async {
            final name = nameController.text.trim();
            if (name.isEmpty) return;

            final transportJson = useStdio
                ? DownstreamMcpEntry.buildStdioJson(
                    command: commandController.text.trim(),
                    args: argsController.text
                        .trim()
                        .split(RegExp(r'\s+'))
                        .where((part) => part.isNotEmpty)
                        .toList(),
                  )
                : DownstreamMcpEntry.buildUrlJson(url: urlController.text.trim());

            await widget.appState.saveMcp(
              DownstreamMcpEntry(
                name: name,
                transportJson: transportJson,
                enabled: entry?.enabled ?? true,
                source: entry?.source ?? 'manual',
                startupTimeoutMs: entry?.startupTimeoutMs,
                toolTimeoutMs: entry?.toolTimeoutMs,
              ),
            );
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            AppToast.success(dialogContext, entry == null ? '下游 MCP 已添加' : '下游 MCP 已保存');
          },
          child: Text(entry == null ? '添加' : '保存'),
        ),
      ],
    );
  }
}

class _McpSummaryPanel extends StatelessWidget {
  final DownstreamMcpEntry entry;
  final DownstreamClient? client;

  const _McpSummaryPanel({required this.entry, required this.client});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = client?.state;
    final tone = switch (state) {
      DownstreamState.connected => AppStatusTone.live,
      DownstreamState.connecting => AppStatusTone.warn,
      DownstreamState.failed => AppStatusTone.error,
      _ => AppStatusTone.idle,
    };
    final stateText = switch (state) {
      DownstreamState.connected => '已连接',
      DownstreamState.connecting => '连接中',
      DownstreamState.failed => '连接失败',
      DownstreamState.closed => '已断开',
      _ => entry.enabled ? '等待连接' : '已关闭',
    };
    final target = entry.isStdio
        ? ([entry.command ?? '', ...entry.args].where((part) => part.isNotEmpty).join(' '))
        : (entry.url ?? '');
    final serverInfo = client?.serverInfo;
    final serverName = '${serverInfo?['name'] ?? ''}'.trim();
    final serverVersion = '${serverInfo?['version'] ?? ''}'.trim();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppStatusDot(tone: tone, size: 7),
              const Gap(AppSpacing.sm),
              Text(stateText, style: AppTones.body(theme, size: 12)),
              const Gap(AppSpacing.sm),
              AppTag(label: entry.isStdio ? 'STDIO' : 'HTTP'),
              const Gap(AppSpacing.xs),
              AppTag(label: entry.isCodexImport ? 'Codex 导入' : '手动添加'),
              const Spacer(),
              if (serverName.isNotEmpty)
                Text(
                  serverVersion.isEmpty ? serverName : '$serverName · $serverVersion',
                  style: AppTones.muted(theme, size: 11),
                ),
            ],
          ),
          if (target.isNotEmpty) ...[
            const Gap(AppSpacing.md),
            Row(
              children: [
                Icon(
                  entry.isStdio ? BootstrapIcons.terminal : BootstrapIcons.link45deg,
                  size: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
                const Gap(AppSpacing.sm),
                Expanded(child: AppMonoText(target, size: 11)),
              ],
            ),
          ],
          const Gap(AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              _McpSummaryMeta(
                label: '启动',
                value:
                    '${(client?.startupTimeoutMs ?? entry.startupTimeoutMs ?? defaultStartupTimeoutMs) ~/ 1000}s',
              ),
              _McpSummaryMeta(
                label: '工具',
                value:
                    '${(client?.toolTimeoutMs ?? entry.toolTimeoutMs ?? defaultToolTimeoutMs) ~/ 1000}s',
              ),
              if (entry.cwd != null && entry.cwd!.isNotEmpty)
                _McpSummaryMeta(label: 'cwd', value: entry.cwd!),
              if (entry.env.isNotEmpty)
                _McpSummaryMeta(label: 'env', value: '${entry.env.length} 项'),
              if (entry.headers.isNotEmpty)
                _McpSummaryMeta(label: 'headers', value: '${entry.headers.length} 项'),
            ],
          ),
          if (client?.lastError != null) ...[
            const Gap(AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.destructive.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(theme.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    BootstrapIcons.exclamationCircle,
                    size: 12,
                    color: theme.colorScheme.destructive,
                  ),
                  const Gap(AppSpacing.sm),
                  Text(
                    '最近错误',
                    style: AppTones.body(theme, size: 11, color: theme.colorScheme.destructive),
                  ),
                  const Gap(AppSpacing.sm),
                  Expanded(
                    child: AppMonoText(
                      client!.lastError!,
                      size: 10,
                      color: theme.colorScheme.destructive,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _McpSummaryMeta extends StatelessWidget {
  final String label;
  final String value;

  const _McpSummaryMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: AppTones.muted(theme, size: 10)),
        AppMonoText(value, size: 10),
      ],
    );
  }
}

class _McpToolItem extends StatelessWidget {
  final Map<String, dynamic> tool;
  final VoidCallback onTap;

  const _McpToolItem({required this.tool, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = '${tool['name'] ?? '未命名工具'}';
    final description = '${tool['description'] ?? ''}'.trim();
    final schema = tool['inputSchema'];
    final properties = schema is Map && schema['properties'] is Map
        ? (schema['properties'] as Map).length
        : 0;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Icon(BootstrapIcons.tools, size: 13, color: theme.colorScheme.mutedForeground),
              const Gap(AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppMonoText(name, size: 12),
                    const Gap(2),
                    Text(
                      description.isEmpty ? '暂无描述' : description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTones.muted(theme, size: 11),
                    ),
                  ],
                ),
              ),
              const Gap(AppSpacing.md),
              AppTag(label: '$properties 参数'),
              const Gap(AppSpacing.sm),
              Icon(BootstrapIcons.chevronRight, size: 12, color: theme.colorScheme.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _McpTile extends StatelessWidget {
  final DownstreamMcpEntry entry;
  final DownstreamClient? client;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReconnect;
  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _McpTile({
    required this.entry,
    required this.client,
    required this.onToggle,
    required this.onReconnect,
    required this.onDetails,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = client?.state;
    final tone = switch (state) {
      DownstreamState.connected => AppStatusTone.live,
      DownstreamState.connecting => AppStatusTone.warn,
      DownstreamState.failed => AppStatusTone.error,
      _ => AppStatusTone.idle,
    };
    return AppCard(
      padding: AppSpacing.tilePadding,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      onTap: onDetails,
      child: Row(
        children: [
          Switch(value: entry.enabled, onChanged: onToggle),
          const Gap(AppSpacing.md),
          AppStatusDot(tone: tone, size: 7),
          const Gap(AppSpacing.sm),
          Text(entry.name, style: AppTones.title(theme, size: 13)),
          const Gap(AppSpacing.sm),
          AppTag(label: entry.isStdio ? 'STDIO' : 'HTTP'),
          const Spacer(),
          if (client != null && client!.tools.isNotEmpty) ...[
            AppStat(icon: BootstrapIcons.tools, value: '${client!.tools.length} 个工具'),
            const Gap(AppSpacing.md),
          ],
          AppIconButton(
            icon: BootstrapIcons.arrowRepeat,
            tooltip: '重新连接',
            onPressed: entry.enabled ? onReconnect : null,
          ),
          const Gap(AppSpacing.sm),
          AppIconButton(icon: BootstrapIcons.pencil, tooltip: '编辑', onPressed: onEdit),
          const Gap(AppSpacing.sm),
          AppIconButton(
            icon: BootstrapIcons.trash,
            tooltip: '删除',
            color: theme.colorScheme.destructive,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
