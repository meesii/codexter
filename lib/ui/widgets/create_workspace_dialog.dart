import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/workspace.dart';
import '../../stores/app_state.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_toast.dart';
import 'json_view.dart';

/// 工作区编辑对话框：基础设置、能力配置、Agents 指令。
class CreateWorkspaceDialog extends StatefulWidget {
  final AppState appState;
  final Workspace? workspace;

  const CreateWorkspaceDialog({
    super.key,
    required this.appState,
    this.workspace,
  });

  static Future<void> show(BuildContext context, AppState appState) {
    return _show(context, appState);
  }

  static Future<void> showEdit(
    BuildContext context,
    AppState appState,
    Workspace workspace,
  ) {
    return _show(context, appState, workspace: workspace);
  }

  static Future<void> _show(
    BuildContext context,
    AppState appState, {
    Workspace? workspace,
  }) {
    final editing = workspace != null;
    return AppDialog.show<void>(
      context: context,
      title: editing ? '修改工作区' : '新建工作区',
      description: '配置工作区路径、可用能力和发送给 ChatGPT 的项目指令。',
      maxWidth: 600,
      maxHeight: 680,
      content: CreateWorkspaceDialog(
        key: _formKey,
        appState: appState,
        workspace: workspace,
      ),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: () => _formKey.currentState?.submit(dialogContext),
          child: Text(editing ? '保存' : '创建'),
        ),
      ],
    );
  }

  static final GlobalKey<_CreateWorkspaceDialogState> _formKey =
      GlobalKey<_CreateWorkspaceDialogState>();

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late final TextEditingController _agentsController;
  late final TextEditingController _agentsPreviewController;
  late bool _inheritSkills;
  late bool _inheritMcps;
  late Set<String> _selectedSkills;
  late Set<String> _selectedMcps;
  late String _agentsMode;
  int _tabIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final workspace = widget.workspace;
    _nameController = TextEditingController(text: workspace?.name ?? '');
    _pathController = TextEditingController(text: workspace?.projectRoot ?? '');
    _agentsController = TextEditingController(
      text: workspace?.customAgents ?? '',
    );
    _agentsPreviewController = TextEditingController();
    _pathController.addListener(_refreshAgentsPreview);
    _refreshAgentsPreview();

    final enabledSkillNames = widget.appState.skills
        .where((skill) => skill.enabled)
        .map((skill) => skill.name)
        .toSet();
    final enabledMcpNames = widget.appState.mcps
        .where((mcp) => mcp.enabled)
        .map((mcp) => mcp.name)
        .toSet();

    _inheritSkills = workspace?.selectedSkillNames == null;
    _inheritMcps = workspace?.selectedMcpNames == null;
    _selectedSkills =
        workspace?.selectedSkillNames?.toSet() ?? enabledSkillNames;
    _selectedMcps = workspace?.selectedMcpNames?.toSet() ?? enabledMcpNames;
    _agentsMode = workspace?.agentsMode ?? Workspace.agentsAuto;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.removeListener(_refreshAgentsPreview);
    _pathController.dispose();
    _agentsController.dispose();
    _agentsPreviewController.dispose();
    super.dispose();
  }

  Future<void> submit(BuildContext dialogContext) async {
    final name = _nameController.text.trim();
    final path = _pathController.text.trim();

    if (name.isEmpty || path.isEmpty) {
      setState(() {
        _tabIndex = 0;
        _error = '名称和路径都不能为空';
      });
      return;
    }
    if (!await Directory(path).exists()) {
      setState(() {
        _tabIndex = 0;
        _error = '路径不存在：$path';
      });
      return;
    }
    if (_agentsMode == Workspace.agentsCustom &&
        _agentsController.text.trim().isEmpty) {
      setState(() {
        _tabIndex = 2;
        _error = '自定义 AGENTS.md 内容不能为空';
      });
      return;
    }

    final selectedSkillNames = _selectedSkills.toList()..sort();
    final selectedMcpNames = _selectedMcps.toList()..sort();
    final customAgents = _agentsController.text.trim();

    final workspace = widget.workspace;
    if (workspace == null) {
      await widget.appState.createWorkspace(
        name: name,
        projectRoot: path,
        selectedSkillNames: _inheritSkills ? null : selectedSkillNames,
        selectedMcpNames: _inheritMcps ? null : selectedMcpNames,
        agentsMode: _agentsMode,
        customAgents: customAgents,
      );
    } else {
      await widget.appState.updateWorkspace(
        workspace.copyWith(
          name: name,
          projectRoot: path,
          selectedSkillNames: _inheritSkills ? null : selectedSkillNames,
          selectedMcpNames: _inheritMcps ? null : selectedMcpNames,
          clearSelectedSkillNames: _inheritSkills,
          clearSelectedMcpNames: _inheritMcps,
          agentsMode: _agentsMode,
          customAgents: customAgents,
        ),
      );
    }
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    AppToast.success(dialogContext, workspace == null ? '工作区已创建' : '工作区已更新');
  }

  Future<void> _pickDirectory() async {
    try {
      final currentPath = _pathController.text.trim();
      final picked = await getDirectoryPath(
        initialDirectory: currentPath.isEmpty ? null : currentPath,
        confirmButtonText: '选择文件夹',
      );
      if (picked == null || picked.isEmpty || !mounted) return;

      setState(() {
        _pathController.text = picked;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = p.basename(picked);
        }
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开目录选择器失败：$error');
    }
  }

  void _refreshAgentsPreview() {
    final root = _pathController.text.trim();
    var body = '';

    if (root.isNotEmpty) {
      for (final name in const ['AGENTS.override.md', 'AGENTS.md']) {
        final file = File(p.join(root, name));
        try {
          if (!file.existsSync()) continue;
          body = file.readAsStringSync();
          break;
        } catch (_) {}
      }
    }

    if (_agentsPreviewController.text != body) {
      _agentsPreviewController.value = TextEditingValue(text: body);
    }
  }

  Widget _buildTabs() {
    final theme = Theme.of(context);
    const labels = ['基本设置', '能力配置', 'Agents'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index == _tabIndex;
          return Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  if (index == 2) _refreshAgentsPreview();
                  setState(() {
                    _tabIndex = index;
                    _error = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? theme.colorScheme.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                    border: Border.all(
                      color: active
                          ? theme.colorScheme.border
                          : Colors.transparent,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: theme.typography.sans.copyWith(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBasicTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionIntro(
          title: '基本设置',
          description: '定义工作区显示名称和 ChatGPT 可以访问的本地项目目录。',
        ),
        const Gap(20),
        AppField(
          label: '工作区名称',
          controller: _nameController,
          placeholder: 'My Project',
        ),
        const Gap(18),
        AppField(
          label: '项目路径',
          controller: _pathController,
          placeholder: r'C:\Projects\my-project',
          trailing: Button(
            style: ButtonStyle.outline(size: ButtonSize.normal),
            onPressed: Platform.isWindows ? _pickDirectory : null,
            child: const Text('浏览'),
          ),
          hint: '文件读写和命令默认都限制在此目录范围内。',
        ),
      ],
    );
  }

  Widget _buildCapabilitiesTab() {
    final availableSkills =
        widget.appState.skills
            .where((skill) => skill.enabled)
            .map((skill) => skill.name)
            .toList()
          ..sort();
    final availableMcps =
        widget.appState.mcps
            .where((mcp) => mcp.enabled)
            .map((mcp) => mcp.name)
            .toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionIntro(
          title: '能力配置',
          description: '这里只控制当前工作区可见的能力，全局禁用的项目不会出现在这里。',
        ),
        const Gap(14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildCapabilityCard(
                  title: 'Skills',
                  inheritGlobal: _inheritSkills,
                  onModeChanged: (inherit) =>
                      setState(() => _inheritSkills = inherit),
                  selected: _selectedSkills,
                  available: availableSkills,
                  onToggle: (name) => setState(() {
                    _selectedSkills.contains(name)
                        ? _selectedSkills.remove(name)
                        : _selectedSkills.add(name);
                  }),
                ),
              ),
              const Gap(12),
              Expanded(
                child: _buildCapabilityCard(
                  title: '下游 MCP',
                  inheritGlobal: _inheritMcps,
                  onModeChanged: (inherit) =>
                      setState(() => _inheritMcps = inherit),
                  selected: _selectedMcps,
                  available: availableMcps,
                  onToggle: (name) => setState(() {
                    _selectedMcps.contains(name)
                        ? _selectedMcps.remove(name)
                        : _selectedMcps.add(name);
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilityCard({
    required String title,
    required bool inheritGlobal,
    required ValueChanged<bool> onModeChanged,
    required Set<String> selected,
    required List<String> available,
    required ValueChanged<String> onToggle,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.8),
        ),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.typography.sans.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Gap(16),
              AppSegmented(
                labels: const ['跟随全局', '自定义'],
                activeIndex: inheritGlobal ? 0 : 1,
                onChanged: (index) => onModeChanged(index == 0),
              ),
            ],
          ),
          const Gap(10),
          Container(
            height: 1,
            color: theme.colorScheme.border.withValues(alpha: 0.6),
          ),
          const Gap(10),
          Expanded(
            child: available.isEmpty
                ? Center(
                    child: Text(
                      '请先在全局管理中启用项目',
                      style: theme.typography.sans.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 430;
                        final itemWidth = twoColumns
                            ? (constraints.maxWidth - 8) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: available.map((name) {
                            final checked =
                                inheritGlobal || selected.contains(name);
                            return SizedBox(
                              width: itemWidth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.muted.withValues(
                                    alpha: inheritGlobal ? 0.22 : 0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    theme.radiusMd,
                                  ),
                                ),
                                child: Checkbox(
                                  state: checked
                                      ? CheckboxState.checked
                                      : CheckboxState.unchecked,
                                  onChanged: inheritGlobal
                                      ? null
                                      : (_) => onToggle(name),
                                  enabled: !inheritGlobal,
                                  trailing: Expanded(
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsTab() {
    final theme = Theme.of(context);
    final modeIndex = switch (_agentsMode) {
      Workspace.agentsCustom => 1,
      Workspace.agentsDisabled => 2,
      _ => 0,
    };
    final editable = _agentsMode == Workspace.agentsCustom;
    final controller = editable ? _agentsController : _agentsPreviewController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionIntro(
          title: 'Agents',
          description: '控制工作区的 project_instructions；只有“自定义”模式可以修改内容。',
        ),
        const Gap(14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.card,
              border: Border.all(
                color: theme.colorScheme.border.withValues(alpha: 0.8),
              ),
              borderRadius: BorderRadius.circular(theme.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '指令来源',
                      style: theme.typography.sans.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    AppSegmented(
                      labels: const ['自动读取', '自定义', '禁用'],
                      activeIndex: modeIndex,
                      onChanged: (index) {
                        _refreshAgentsPreview();
                        setState(() {
                          _agentsMode = switch (index) {
                            1 => Workspace.agentsCustom,
                            2 => Workspace.agentsDisabled,
                            _ => Workspace.agentsAuto,
                          };
                          _error = null;
                        });
                      },
                    ),
                  ],
                ),
                const Gap(12),
                Expanded(
                  child: Opacity(
                    opacity: editable ? 1 : 0.72,
                    child: AppField(
                      label: editable ? '自定义内容' : '内容预览',
                      controller: controller,
                      readOnly: !editable,
                      placeholder: editable
                          ? '# Project Instructions\n\n修改代码前先读取相关文件……'
                          : '暂无内容',
                      maxLines: 11,
                      hint: editable
                          ? '只保存在当前工作区配置中，不会改写项目目录里的 AGENTS.md。'
                          : '只读预览；自动读取优先 AGENTS.override.md，其次 AGENTS.md。',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = switch (_tabIndex) {
      1 => _buildCapabilitiesTab(),
      2 => _buildAgentsTab(),
      _ => _buildBasicTab(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabs(),
        const Gap(20),
        SizedBox(height: 400, child: tab),
        if (_error != null) ...[
          const Gap(16),
          AppNotice(tone: AppNoticeTone.danger, message: _error!),
        ],
      ],
    );
  }
}

class _SectionIntro extends StatelessWidget {
  final String title;
  final String description;

  const _SectionIntro({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.typography.sans.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(4),
        Text(
          description,
          style: theme.typography.sans.copyWith(
            fontSize: 11,
            height: 1.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}
