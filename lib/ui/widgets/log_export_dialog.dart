import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../models/mcp_log_entry.dart';
import '../../services/log_export_service.dart';
import '../../utils/fmt.dart';
import '../theme/app_theme.dart';
import 'app_atoms.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'json_view.dart';

class LogExportDialog {
  const LogExportDialog._();

  static Future<void> show(
    BuildContext context, {
    required List<McpLogEntry> entries,
    required String workspaceName,
    required String projectRoot,
  }) {
    if (!entries.any((entry) => entry.isToolCall)) return Future<void>.value();
    return AppDialog.show<void>(
      context: context,
      title: '导出日志',
      description: '选择要导出的调用记录',
      maxWidth: 820,
      maxHeight: 760,
      scrollContent: false,
      content: _LogExportDialogBody(
        entries: entries,
        workspaceName: workspaceName,
        projectRoot: projectRoot,
      ),
    );
  }
}

class _LogExportDialogBody extends StatefulWidget {
  final List<McpLogEntry> entries;
  final String workspaceName;
  final String projectRoot;

  const _LogExportDialogBody({
    required this.entries,
    required this.workspaceName,
    required this.projectRoot,
  });

  @override
  State<_LogExportDialogBody> createState() => _LogExportDialogBodyState();
}

class _LogExportDialogBodyState extends State<_LogExportDialogBody> {
  final _searchController = TextEditingController();
  late final Set<String> _selectedIds;
  LogExportGranularity _granularity = LogExportGranularity.standard;
  LogExportResponseMode _responseMode = LogExportResponseMode.none;
  bool _onlyTools = true;
  bool _onlyErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.entries
        .where((entry) => entry.isToolCall)
        .map((entry) => entry.id)
        .toSet();
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<McpLogEntry> get _visibleEntries {
    final keyword = _searchController.text.trim().toLowerCase();
    return widget.entries
        .where((entry) {
          if (_onlyTools && !entry.isToolCall) return false;
          if (_onlyErrors && (entry.pending || entry.success)) return false;
          if (keyword.isEmpty) return true;
          return entry.title.toLowerCase().contains(keyword) ||
              (entry.purpose?.toLowerCase().contains(keyword) ?? false) ||
              entry.argsSummary.toLowerCase().contains(keyword);
        })
        .toList(growable: false);
  }

  List<McpLogEntry> get _selectedEntries =>
      widget.entries.where((entry) => _selectedIds.contains(entry.id)).toList(growable: false);

  LogExportDocument get _document => LogExportService.build(
    entries: _selectedEntries,
    workspaceName: widget.workspaceName,
    projectRoot: widget.projectRoot,
    options: LogExportOptions(granularity: _granularity, responseMode: _responseMode),
  );

  void _selectVisible(bool selected) {
    setState(() {
      for (final entry in _visibleEntries) {
        if (selected) {
          _selectedIds.add(entry.id);
        } else {
          _selectedIds.remove(entry.id);
        }
      }
    });
  }

  void _selectRecent(int count) {
    final visible = _visibleEntries;
    final start = visible.length > count ? visible.length - count : 0;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(visible.sublist(start).map((entry) => entry.id));
    });
  }

  Future<void> _copy() async {
    if (_selectedIds.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _document.text));
    if (mounted) AppToast.success(context, '日志已复制到剪贴板');
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final fileName = 'codexter-log-${_fileTimestamp(now)}.md';
      const markdownType = XTypeGroup(label: 'Markdown', extensions: ['md']);
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [markdownType],
      );
      if (location == null) return;

      final document = _document;
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(document.text)),
        mimeType: 'text/markdown',
        name: fileName,
      );
      await file.saveTo(location.path);
      if (mounted) AppToast.success(context, '日志已导出');
    } catch (error) {
      if (mounted) AppToast.error(context, '导出日志失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleEntries;
    final document = _document;
    final selectedCount = _selectedIds.length;
    return SizedBox(
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('日志范围', style: AppTones.label(theme)),
              const Gap(AppSpacing.sm),
              Text(
                '已选择 $selectedCount / ${widget.entries.length}',
                style: AppTones.muted(theme, size: 11),
              ),
              const Spacer(),
              AppFilterField(
                controller: _searchController,
                placeholder: '筛选工具、Purpose 或参数',
                width: 250,
              ),
            ],
          ),
          const Gap(AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SmallAction(
                label: '全选',
                onPressed: visible.isEmpty ? null : () => _selectVisible(true),
              ),
              _SmallAction(
                label: '取消全选',
                onPressed: visible.isEmpty ? null : () => _selectVisible(false),
              ),
              _SmallAction(
                label: '最近 20',
                onPressed: visible.isEmpty ? null : () => _selectRecent(20),
              ),
              _SmallAction(
                label: '最近 50',
                onPressed: visible.isEmpty ? null : () => _selectRecent(50),
              ),
              _SmallAction(
                label: '最近 100',
                onPressed: visible.isEmpty ? null : () => _selectRecent(100),
              ),
              Checkbox(
                state: _onlyTools ? CheckboxState.checked : CheckboxState.unchecked,
                onChanged: (value) => setState(() => _onlyTools = value == CheckboxState.checked),
                trailing: const Text('仅工具调用'),
              ),
              Checkbox(
                state: _onlyErrors ? CheckboxState.checked : CheckboxState.unchecked,
                onChanged: (value) => setState(() => _onlyErrors = value == CheckboxState.checked),
                trailing: const Text('仅异常'),
              ),
            ],
          ),
          const Gap(AppSpacing.md),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTones.surfaceSunken(theme),
                borderRadius: BorderRadius.circular(theme.radiusMd),
                border: Border.all(color: AppTones.borderSubtle(theme)),
              ),
              child: visible.isEmpty
                  ? const Center(child: Text('没有符合筛选条件的日志'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: AppTones.borderSubtle(theme)),
                      itemBuilder: (context, index) {
                        final entry = visible[index];
                        final selected = _selectedIds.contains(entry.id);
                        return _LogExportRow(
                          entry: entry,
                          selected: selected,
                          onChanged: (checked) => setState(() {
                            if (checked) {
                              _selectedIds.add(entry.id);
                            } else {
                              _selectedIds.remove(entry.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ),
          const Gap(AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _OptionGroup(
                  title: '导出详细程度',
                  description: _granularityDescription(_granularity),
                  child: AppSegmented(
                    labels: const ['精简', '标准', '详细'],
                    activeIndex: _granularity.index,
                    onChanged: (index) =>
                        setState(() => _granularity = LogExportGranularity.values[index]),
                  ),
                ),
              ),
              const Gap(AppSpacing.x2l),
              Expanded(
                child: _OptionGroup(
                  title: '响应内容',
                  description: _responseDescription(_responseMode),
                  child: AppSegmented(
                    labels: const ['不导出', '裁剪', '完整'],
                    activeIndex: _responseMode.index,
                    onChanged: (index) =>
                        setState(() => _responseMode = LogExportResponseMode.values[index]),
                  ),
                ),
              ),
            ],
          ),
          const Gap(AppSpacing.md),
          Row(
            children: [
              Text(
                '$selectedCount 条日志 · ${Fmt.bytes(document.utf8Bytes)} · 约 ${_compactNumber(document.estimatedTokens)} tokens',
                style: AppTones.muted(theme, size: 11),
              ),
              const Spacer(),
              Button(
                style: ButtonStyle.outline(size: ButtonSize.normal),
                onPressed: selectedCount == 0 ? null : _copy,
                child: const AppButtonLabel(icon: BootstrapIcons.clipboard, label: '复制到剪贴板'),
              ),
              const Gap(AppSpacing.sm),
              Button(
                style: ButtonStyle.primary(size: ButtonSize.normal),
                onPressed: selectedCount == 0 || _saving ? null : _save,
                child: AppButtonLabel(
                  icon: BootstrapIcons.download,
                  label: _saving ? '导出中…' : '导出 Markdown',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogExportRow extends StatelessWidget {
  final McpLogEntry entry;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _LogExportRow({required this.entry, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final purpose = entry.purpose?.trim();
    final args = entry.argsSummary.trim();
    final secondary = purpose?.isNotEmpty == true ? purpose! : args;
    final statusColor = entry.pending
        ? AppTones.warning
        : entry.success
        ? AppTones.success
        : theme.colorScheme.destructive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Checkbox(
        state: selected ? CheckboxState.checked : CheckboxState.unchecked,
        onChanged: (state) => onChanged(state == CheckboxState.checked),
        trailing: Expanded(
          child: Row(
            children: [
              SizedBox(width: 66, child: AppMonoText(entry.clockText, size: 10)),
              SizedBox(
                width: 124,
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTones.body(theme, size: 11),
                ),
              ),
              const Gap(AppSpacing.sm),
              Expanded(
                child: Text(
                  secondary.isEmpty ? '—' : secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTones.muted(theme, size: 11),
                ),
              ),
              const Gap(AppSpacing.sm),
              AppStatusDot(
                tone: entry.pending
                    ? AppStatusTone.warn
                    : entry.success
                    ? AppStatusTone.live
                    : AppStatusTone.error,
                size: 6,
              ),
              const Gap(AppSpacing.xs),
              Text(
                entry.pending
                    ? 'pending'
                    : entry.success
                    ? 'success'
                    : 'error',
                style: AppTones.muted(theme, size: 10).copyWith(color: statusColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SmallAction({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Button(
      style: ButtonStyle.outline(size: ButtonSize.small),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _OptionGroup({required this.title, required this.description, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTones.label(theme)),
        const Gap(AppSpacing.sm),
        child,
        const Gap(AppSpacing.xs),
        Text(description, style: AppTones.muted(theme, size: 10)),
      ],
    );
  }
}

String _granularityDescription(LogExportGranularity value) => switch (value) {
  LogExportGranularity.compact => 'Purpose、工具与状态。',
  LogExportGranularity.standard => '额外包含参数摘要，适合作为默认恢复日志。',
  LogExportGranularity.detailed => '包含完整调用参数、Method 与耗时。',
};

String _responseDescription(LogExportResponseMode value) => switch (value) {
  LogExportResponseMode.none => '默认不导出工具响应。',
  LogExportResponseMode.truncated => '每条工具响应最多保留 4000 字符。',
  LogExportResponseMode.full => '导出原始 JSON-RPC Response，文件可能显著增大。',
};

String _fileTimestamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}-${two(value.hour)}${two(value.minute)}${two(value.second)}';
}

String _compactNumber(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
  }
  return '${(value / 1000000).toStringAsFixed(1)}M';
}
