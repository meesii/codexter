import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/mcp_log_entry.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'json_view.dart';

/// 滚动到底部判定容差（像素），小于该距离视为已贴底
const _bottomThresholdPx = 48.0;

/// 时间线式实时日志：折叠一行摘要，展开显示完整请求/响应 JSON。
/// 最新条目位于列表底部；贴底时自动跟随，离开底部后暂停跟随并弹出悬浮提示。
class LogTimeline extends StatefulWidget {
  final List<McpLogEntry> entries;
  final int toolCalls;
  final int toolCount;
  final int processCount;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback? onClear;

  const LogTimeline({
    super.key,
    required this.entries,
    required this.toolCalls,
    required this.toolCount,
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
                  const Gap(AppSpacing.md),
                  SizedBox(
                    height: 36,
                    child: Button(
                      style: ButtonStyle.outline(size: ButtonSize.normal),
                      onPressed:
                          widget.entries.isEmpty || widget.onClear == null
                          ? null
                          : () {
                              setState(() {
                                _expandedId = null;
                                _hasNewMsg = false;
                                _atBottom = true;
                                _lastEntryId = null;
                              });
                              widget.onClear!();
                            },
                      child: const AppButtonLabel(
                        icon: BootstrapIcons.trash,
                        label: '清除日志',
                      ),
                    ),
                  ),
                  const Gap(AppSpacing.md),
                  Checkbox(
                    state: _hideProtocolRequests
                        ? CheckboxState.checked
                        : CheckboxState.unchecked,
                    onChanged: (state) => setState(
                      () => _hideProtocolRequests =
                          state == CheckboxState.checked,
                    ),
                    trailing: const Text('隐藏协议请求'),
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
                  const Gap(AppSpacing.md),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppFilterField(
                        controller: _filterController,
                        placeholder: '按工具名或参数筛选',
                        width: 200,
                      ),
                    ),
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
                    icon: BootstrapIcons.tools,
                    value: '${widget.toolCount} 个工具',
                  ),
                  const Gap(AppSpacing.lg),
                  AppStat(
                    icon: BootstrapIcons.activity,
                    value: '${widget.entries.length} 条日志',
                  ),
                  const Gap(AppSpacing.lg),
                  AppStat(
                    icon: BootstrapIcons.terminal,
                    value: '${widget.processCount} 个进程',
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
                            return _LogTile(
                              entry: entry,
                              expanded: _expandedId == entry.id,
                              onToggle: () => setState(() {
                                _expandedId = _expandedId == entry.id
                                    ? null
                                    : entry.id;
                              }),
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
