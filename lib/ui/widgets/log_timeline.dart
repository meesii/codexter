import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/mcp_log_entry.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'json_view.dart';

/// 滚动到底部判定容差（像素），小于该距离视为已贴底
const _bottomThresholdPx = 48.0;

/// 时间线式实时日志：折叠一行摘要，展开显示完整请求/响应 JSON。
/// 最新条目位于列表底部；贴底时自动跟随，离开底部后暂停跟随并弹出悬浮提示。
class LogTimeline extends StatefulWidget {
  final List<McpLogEntry> entries;
  final int toolCalls;
  final int errorCount;
  final int processCount;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback? onClear;

  const LogTimeline({
    super.key,
    required this.entries,
    required this.toolCalls,
    required this.errorCount,
    required this.processCount,
    required this.tabIndex,
    required this.onTabChanged,
    this.onClear,
  });

  @override
  State<LogTimeline> createState() => _LogTimelineState();
}

class _LogTimelineState extends State<LogTimeline> {
  final _filterController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hideProtocolRequests = true;
  bool _onlyErrors = false;
  String? _expandedId;

  bool _atBottom = true;
  bool _hasNewMsg = false;
  String? _lastEntryId;
  bool _firstLayoutDone = false;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() => setState(() {}));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final reached =
        position.pixels >= position.maxScrollExtent - _bottomThresholdPx;
    if (reached && !_atBottom) {
      setState(() {
        _atBottom = true;
        _hasNewMsg = false;
      });
    } else if (!reached && _atBottom) {
      setState(() => _atBottom = false);
    }
  }

  @override
  void didUpdateWidget(covariant LogTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entries = widget.entries;
    if (entries.isEmpty) {
      _lastEntryId = null;
      return;
    }
    final newestId = entries.last.id;
    if (newestId == _lastEntryId) return;

    final isFirstLoad = _lastEntryId == null;
    final shouldFollow = isFirstLoad || _atBottom;
    _lastEntryId = newestId;

    if (shouldFollow) {
      _scrollToBottom();
      return;
    }

    // 展开日志详情会临时增大列表高度并把 _atBottom 置为 false；详情收起后，
    // ScrollPosition 不一定再次发出滚动事件。等新条目真正完成布局后再判断：
    // 只有最新内容确实落在视口下方时才显示提示。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final reached =
          position.maxScrollExtent <= _bottomThresholdPx ||
          position.pixels >= position.maxScrollExtent - _bottomThresholdPx;
      if (reached) {
        if (!_atBottom || _hasNewMsg) {
          setState(() {
            _atBottom = true;
            _hasNewMsg = false;
          });
        }
      } else if (!_hasNewMsg) {
        setState(() {
          _atBottom = false;
          _hasNewMsg = true;
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _jumpToBottom() {
    _scrollToBottom();
    setState(() {
      _hasNewMsg = false;
      _atBottom = true;
    });
  }

  List<McpLogEntry> get _visibleEntries {
    final keyword = _filterController.text.trim().toLowerCase();
    return widget.entries.where((entry) {
      if (_onlyErrors) {
        if (entry.pending || entry.success) return false;
      } else if (_hideProtocolRequests && _isProtocolRequest(entry)) {
        return false;
      }
      if (keyword.isEmpty) return true;
      return entry.title.toLowerCase().contains(keyword) ||
          (entry.purpose?.toLowerCase().contains(keyword) ?? false) ||
          entry.argsSummary.toLowerCase().contains(keyword);
    }).toList();
  }

  /// ChatGPT / MCP 自身的协议流量，不属于用户主动触发的业务工具调用。
  /// 默认隐藏这些记录，让时间线聚焦真正的 Agent 行为；异常模式会重新显示失败项。
  static bool _isProtocolRequest(McpLogEntry entry) {
    switch (entry.method) {
      case 'initialize':
      case 'notifications/initialized':
      case 'notifications/cancelled':
      case 'server/discover':
      case 'ping':
      case 'tools/list':
      case 'resources/list':
      case 'resources/read':
      case 'prompts/list':
        return true;
      default:
        return false;
    }
  }

  void _clearLogs() {
    if (widget.entries.isEmpty || widget.onClear == null) return;
    setState(() {
      _expandedId = null;
      _hasNewMsg = false;
      _atBottom = true;
      _lastEntryId = null;
    });
    widget.onClear!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _visibleEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2l,
            AppSpacing.md,
            AppSpacing.x2l,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTones.borderSubtle(theme)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppSegmented(
                    labels: const ['实时日志', '运行终端'],
                    activeIndex: widget.tabIndex,
                    onChanged: widget.onTabChanged,
                  ),
                  const Gap(AppSpacing.lg),
                  Checkbox(
                    state: _onlyErrors
                        ? CheckboxState.checked
                        : CheckboxState.unchecked,
                    onChanged: (state) => setState(
                      () => _onlyErrors = state == CheckboxState.checked,
                    ),
                    trailing: const Text('仅看异常'),
                  ),
                  const Spacer(),
                  AppFilterField(
                    controller: _filterController,
                    placeholder: '按工具名或参数筛选',
                    width: 260,
                  ),
                  const Gap(AppSpacing.sm),
                  _LogOptionsButton(
                    hideProtocolRequests: _hideProtocolRequests,
                    canClear:
                        widget.entries.isNotEmpty && widget.onClear != null,
                    onHideProtocolRequestsChanged: (value) =>
                        setState(() => _hideProtocolRequests = value),
                    onClear: _clearLogs,
                  ),
                ],
              ),
              const Gap(AppSpacing.md),
              Row(
                children: [
                  AppStat(
                    icon: BootstrapIcons.lightning,
                    value: '${widget.toolCalls} 次调用',
                  ),
                  const Gap(AppSpacing.lg),
                  AppStat(
                    icon: BootstrapIcons.exclamationCircle,
                    value: '${widget.errorCount} 次异常',
                    color: widget.errorCount > 0
                        ? theme.colorScheme.destructive
                        : null,
                  ),
                  const Gap(AppSpacing.lg),
                  AppStat(
                    icon: BootstrapIcons.terminal,
                    value: '${widget.processCount} 个运行进程',
                  ),
                  if (entries.length != widget.entries.length) ...[
                    const Gap(AppSpacing.lg),
                    AppStat(
                      icon: BootstrapIcons.funnel,
                      value: '${entries.length} 条可见',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const AppEmptyState(
                  icon: BootstrapIcons.activity,
                  title: '暂无日志',
                  subtitle: '把工作区地址填入 ChatGPT 的 MCP 设置后，这里会实时显示每次调用。',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (!_firstLayoutDone) {
                      _firstLayoutDone = true;
                      _scrollToBottom();
                    }
                    return Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.x2l,
                            AppSpacing.md,
                            AppSpacing.x2l,
                            AppSpacing.x2l,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry.toolName == 'summary') {
                              return _SummaryLogPanel(entry: entry);
                            }
                            final expanded = _expandedId == entry.id;
                            void onToggle() => setState(() {
                              _expandedId = expanded ? null : entry.id;
                            });
                            return _LogTile(
                              entry: entry,
                              expanded: expanded,
                              onToggle: onToggle,
                            );
                          },
                        ),
                        if (_hasNewMsg)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: AppSpacing.lg,
                            child: Center(
                              child: _NewContentButton(onTap: _jumpToBottom),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LogOptionsButton extends StatefulWidget {
  final bool hideProtocolRequests;
  final bool canClear;
  final ValueChanged<bool> onHideProtocolRequestsChanged;
  final VoidCallback onClear;

  const _LogOptionsButton({
    required this.hideProtocolRequests,
    required this.canClear,
    required this.onHideProtocolRequestsChanged,
    required this.onClear,
  });

  @override
  State<_LogOptionsButton> createState() => _LogOptionsButtonState();
}

class _LogOptionsButtonState extends State<_LogOptionsButton> {
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
        width: 184,
        child: DropdownMenu(
          surfaceOpacity: 0.98,
          surfaceBlur: 12,
          children: [
            MenuCheckbox(
              value: widget.hideProtocolRequests,
              child: const Text('隐藏协议请求'),
              onChanged: (_, value) =>
                  widget.onHideProtocolRequestsChanged(value),
            ),
            const MenuDivider(),
            MenuButton(
              onPressed: widget.canClear ? (_) => widget.onClear() : null,
              child: const Text('清除日志'),
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
    return SizedBox(
      width: 36,
      height: 36,
      child: Button(
        style: ButtonStyle.outline(
          density: ButtonDensity.icon,
          size: ButtonSize.normal,
        ),
        onPressed: _showMenu,
        child: const Icon(BootstrapIcons.threeDots, size: 15),
      ),
    );
  }
}

/// 最新内容确实位于视口下方时显示的悬浮入口，点击回到底部。
/// 用“向下”表达内容所在方向，小圆点只负责表达“有新内容”，避免和聊天功能混淆。
class _NewContentButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewContentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      tooltip: const TooltipContainer(child: Text('有新日志，跳到最新')).call,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppTones.borderSubtle(theme)),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.foreground.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    BootstrapIcons.chevronDown,
                    size: 14,
                    color: theme.colorScheme.foreground,
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.background,
                        width: 1,
                      ),
                    ),
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

class _SummaryLogPanel extends StatelessWidget {
  final McpLogEntry entry;

  const _SummaryLogPanel({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = entry.executionArguments ?? const <String, dynamic>{};
    final output = entry.displayResponse ?? const <String, dynamic>{};
    final title =
        _text(output['title']) ??
        _text(input['title']) ??
        (entry.pending ? '正在生成本轮总结' : '本轮总结');
    final summary = _text(output['summary']) ?? _text(input['summary']) ?? '';
    final fileChanges = _RoundFileChangeData.tryParse(output['fileChanges']);
    final accent = entry.pending
        ? AppTones.warning
        : entry.success
        ? AppTones.success
        : theme.colorScheme.destructive;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppTones.surfaceRaised(theme),
          borderRadius: BorderRadius.circular(theme.radiusLg),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                  ),
                  child: Icon(
                    entry.pending
                        ? BootstrapIcons.hourglassSplit
                        : entry.success
                        ? BootstrapIcons.check2Circle
                        : BootstrapIcons.exclamationCircle,
                    size: 17,
                    color: accent,
                  ),
                ),
                const Gap(AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: entry.pending
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: AppTones.title(theme, size: 14),
                              ),
                              const Gap(3),
                              Text(
                                '正在整理本轮结果',
                                style: AppTones.muted(theme, size: 11),
                              ),
                            ],
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              style: AppTones.title(theme, size: 14),
                            ),
                          ),
                  ),
                ),
                const Gap(AppSpacing.md),
                Text(
                  entry.pending
                      ? entry.clockText
                      : '${entry.clockText} · ${entry.durationText}',
                  style: AppTones.mono(theme, size: 10),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const Gap(AppSpacing.lg),
              Text(summary, style: AppTones.body(theme, size: 13)),
            ],
            if (fileChanges != null && fileChanges.files.isNotEmpty) ...[
              const Gap(AppSpacing.md),
              _RoundFileChanges(data: fileChanges),
            ],
          ],
        ),
      ),
    );
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}

const _roundCopyColumnWidth = 28.0;
const _roundDiffColumnWidth = 38.0;

class _RoundFileChanges extends StatefulWidget {
  final _RoundFileChangeData data;

  const _RoundFileChanges({required this.data});

  @override
  State<_RoundFileChanges> createState() => _RoundFileChangesState();
}

class _RoundFileChangesState extends State<_RoundFileChanges> {
  static const _collapsedCount = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    final hasMore = data.files.length > _collapsedCount;
    final visible = _showAll || !hasMore
        ? data.files
        : data.files.take(_collapsedCount).toList(growable: false);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Text(
                  '已修改 ${data.files.length} 个文件',
                  style: AppTones.title(theme, size: 12),
                ),
                const Spacer(),
                const SizedBox(width: _roundCopyColumnWidth),
                SizedBox(
                  width: _roundDiffColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: data.additions > 0
                        ? Text(
                            '+${data.additions}',
                            style: AppTones.mono(
                              theme,
                              size: 11,
                              color: AppTones.success,
                              weight: FontWeight.w600,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                SizedBox(
                  width: _roundDiffColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: data.deletions > 0
                        ? Text(
                            '-${data.deletions}',
                            style: AppTones.mono(
                              theme,
                              size: 11,
                              color: theme.colorScheme.destructive,
                              weight: FontWeight.w600,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTones.borderSubtle(theme)),
          for (var index = 0; index < visible.length; index++) ...[
            _RoundFileChangeRow(item: visible[index]),
            if (index != visible.length - 1 || hasMore)
              Divider(height: 1, color: AppTones.borderSubtle(theme)),
          ],
          if (hasMore)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showAll = !_showAll),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      _showAll
                          ? '收起文件列表'
                          : '再显示 ${data.files.length - _collapsedCount} 个文件',
                      style: AppTones.muted(theme, size: 11),
                    ),
                    const Gap(4),
                    Icon(
                      _showAll
                          ? BootstrapIcons.chevronUp
                          : BootstrapIcons.chevronDown,
                      size: 10,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundFileChangeRow extends StatelessWidget {
  final _RoundFileChangeItem item;

  const _RoundFileChangeRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (item.status) {
      'added' => 'A',
      'deleted' => 'D',
      _ => 'M',
    };
    final statusColor = switch (item.status) {
      'added' => AppTones.success,
      'deleted' => theme.colorScheme.destructive,
      _ => AppTones.info,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              statusLabel,
              style: AppTones.mono(
                theme,
                size: 10,
                color: statusColor,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const Gap(AppSpacing.xs),
          Expanded(
            child: Text(
              item.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTones.mono(
                theme,
                size: 10,
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
          SizedBox(
            width: _roundCopyColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: AppTooltip(
                message: '复制文件路径',
                alignment: Alignment.bottomCenter,
                anchorAlignment: Alignment.topCenter,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.path));
                      AppToast.info(context, '已复制文件路径');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        BootstrapIcons.copy,
                        size: 10,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _roundDiffColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: item.additions > 0
                  ? Text(
                      '+${item.additions}',
                      style: AppTones.mono(
                        theme,
                        size: 10,
                        color: AppTones.success,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SizedBox(
            width: _roundDiffColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: item.deletions > 0
                  ? Text(
                      '-${item.deletions}',
                      style: AppTones.mono(
                        theme,
                        size: 10,
                        color: theme.colorScheme.destructive,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundFileChangeData {
  final int additions;
  final int deletions;
  final List<_RoundFileChangeItem> files;

  const _RoundFileChangeData({
    required this.additions,
    required this.deletions,
    required this.files,
  });

  static _RoundFileChangeData? tryParse(Object? value) {
    if (value is! Map) return null;
    final rawFiles = value['files'];
    if (rawFiles is! List) return null;
    final files = <_RoundFileChangeItem>[];
    for (final raw in rawFiles) {
      if (raw is! Map) continue;
      final path = '${raw['path'] ?? ''}'.trim();
      if (path.isEmpty) continue;
      files.add(
        _RoundFileChangeItem(
          path: path,
          status: '${raw['status'] ?? 'modified'}',
          additions: _int(raw['additions']),
          deletions: _int(raw['deletions']),
        ),
      );
    }
    return _RoundFileChangeData(
      additions: _int(value['additions']),
      deletions: _int(value['deletions']),
      files: List.unmodifiable(files),
    );
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class _RoundFileChangeItem {
  final String path;
  final String status;
  final int additions;
  final int deletions;

  const _RoundFileChangeItem({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
  });
}

class _LogTile extends StatelessWidget {
  final McpLogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _LogTile({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.pending
        ? AppStatusTone.warn
        : entry.success
        ? AppStatusTone.live
        : AppStatusTone.error;

    return AppCard(
      onTap: onToggle,
      selected: expanded,
      borderColor: AppTones.logCardBorder(theme),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                expanded
                    ? BootstrapIcons.chevronDown
                    : BootstrapIcons.chevronRight,
                size: 11,
                color: theme.colorScheme.mutedForeground,
              ),
              const Gap(AppSpacing.sm),
              AppStatusDot(tone: tone, size: 6),
              const Gap(AppSpacing.sm),
              SizedBox(
                width: 62,
                child: AppMonoText(entry.clockText, size: 11),
              ),
              SizedBox(
                width: 112,
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTones.mono(
                    theme,
                    size: 11,
                    color: theme.colorScheme.foreground,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: entry.purpose != null
                    ? Text(
                        entry.purpose!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTones.body(
                          theme,
                          size: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      )
                    : entry.isToolCall
                    ? Text(
                        '未提供调用说明',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTones.muted(theme, size: 11),
                      )
                    : AppMonoText(entry.argsSummary, size: 11),
              ),
              if (entry.isToolCall && entry.argsSummary.isNotEmpty) ...[
                const Gap(AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: AppTooltip(
                    message: entry.argsSummary,
                    child: AppMonoText(entry.argsSummary, size: 10),
                  ),
                ),
              ],
              const Gap(AppSpacing.sm),
              if (!entry.pending && !entry.success) ...[
                AppTooltip(
                  message: '执行失败，点击查看错误详情',
                  child: AppTag(
                    label: '失败',
                    color: theme.colorScheme.destructive,
                    icon: BootstrapIcons.exclamationCircle,
                  ),
                ),
                const Gap(AppSpacing.sm),
              ],
              SizedBox(
                width: 56,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AppMonoText(
                    entry.pending ? '进行中' : entry.durationText,
                    size: 11,
                    color: entry.pending
                        ? AppTones.warning
                        : AppTones.metricText(theme),
                  ),
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const Gap(AppSpacing.md),
            if (entry.error != null) ...[
              AppNotice(
                tone: AppNoticeTone.danger,
                message: '执行失败',
                detail: entry.error,
              ),
              const Gap(AppSpacing.md),
            ],
            JsonView(
              label: '请求',
              data: entry.displayRequest,
              scrollable: false,
              previewLines: 18,
              showCopy: true,
              onOpen: () => _openPayload(
                context,
                label: '请求',
                data: entry.displayRequest,
              ),
            ),
            const Gap(AppSpacing.md),
            JsonView(
              label: '响应',
              data: entry.displayResponse ?? const {'pending': true},
              scrollable: false,
              previewLines: 18,
              showCopy: true,
              onOpen: () => _openPayload(
                context,
                label: '响应',
                data: entry.displayResponse ?? const {'pending': true},
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPayload(
    BuildContext context, {
    required String label,
    required Object? data,
  }) {
    return AppDialog.show<void>(
      context: context,
      title: '${entry.title} · $label',
      description: '完整 $label JSON',
      maxWidth: 720,
      maxHeight: 620,
      content: JsonView(
        label: label,
        data: data,
        scrollable: false,
        showCopy: true,
      ),
    );
  }
}
