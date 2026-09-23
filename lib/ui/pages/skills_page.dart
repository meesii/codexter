import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../models/skill_entry.dart';
import '../../services/capability_manager.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';

/// Skills 全局管理：目录负责发现，配置仅保存启用状态。
class SkillsPage extends StatefulWidget {
  final AppState appState;

  const SkillsPage({super.key, required this.appState});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  bool _refreshing = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final skills = widget.appState.skills;
    final enabledCount = skills.where((skill) => skill.enabled).length;

    return AppPageScaffold(
      title: '下游 Skills',
      subtitle: skills.isEmpty ? null : '共 ${skills.length} 个，$enabledCount 个启用',
      actions: [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.small),
          onPressed: _refreshing ? null : _refreshSkills,
          child: AppButtonLabel(
            icon: _refreshing ? BootstrapIcons.hourglassSplit : BootstrapIcons.arrowClockwise,
            label: _refreshing ? '刷新中…' : '刷新',
          ),
        ),
        const Gap(AppSpacing.sm),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.small),
          onPressed: _openSkillsDirectory,
          child: const AppButtonLabel(icon: BootstrapIcons.folder2Open, label: '打开目录'),
        ),
        const Gap(AppSpacing.sm),
        _SkillImportMenuButton(
          disabled: _refreshing || _importing,
          onCodex: () => unawaited(
            _importSkills(widget.appState.capabilityManager.importCodexSkills, 'Codex'),
          ),
          onCursor: () => unawaited(
            _importSkills(widget.appState.capabilityManager.importCursorSkills, 'Cursor'),
          ),
        ),
      ],
      child: skills.isEmpty ? _buildEmpty(context) : _buildList(skills),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return AppEmptyState(
      icon: BootstrapIcons.puzzle,
      title: '暂无 Skills',
      subtitle: '将包含 SKILL.md 的 Skill 文件夹复制到 Codexter 的 skills 目录，然后点击刷新。',
      action: Button(
        style: ButtonStyle.outline(size: ButtonSize.normal),
        onPressed: _openSkillsDirectory,
        child: const AppButtonLabel(icon: BootstrapIcons.folder2Open, label: '打开 Skills 目录'),
      ),
    );
  }

  Widget _buildList(List<SkillEntry> skills) {
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: skills.length,
      itemBuilder: (context, index) {
        final skill = skills[index];
        return _SkillTile(
          skill: skill,
          onToggle: (value) => widget.appState.toggleSkill(skill.name, value),
          onDelete: () => _confirmDeleteSkill(skill),
        );
      },
    );
  }

  Future<void> _refreshSkills() async {
    setState(() => _refreshing = true);
    try {
      await widget.appState.refreshSkills();
      if (!mounted) return;
      AppToast.success(context, 'Skills 已刷新，共发现 ${widget.appState.skills.length} 个');
    } catch (error) {
      if (mounted) AppToast.error(context, '刷新 Skills 失败：$error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openSkillsDirectory() async {
    final ok = await widget.appState.capabilityManager.openLocalSkillsDirectory();
    if (!mounted) return;
    if (!ok) AppToast.error(context, '打开 Skills 目录失败');
  }

  Future<void> _confirmDeleteSkill(SkillEntry skill) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '删除 Skill',
      message: '确定删除「${skill.name}」吗？这会删除 Codexter skills 目录中的整个 Skill 文件夹。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    try {
      await widget.appState.deleteSkill(skill.name);
      if (!mounted) return;
      AppToast.success(context, 'Skill「${skill.name}」已删除');
    } catch (error) {
      if (mounted) AppToast.error(context, '删除 Skill 失败：$error');
    }
  }

  Future<void> _importSkills(Future<SkillImportResult> Function() importer, String source) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await importer();
      await widget.appState.refreshSkills();
      if (!mounted) return;
      AppToast.success(
        context,
        '从 $source 扫描到 ${result.scanned} 个，新导入 ${result.imported} 个，跳过 ${result.skipped} 个',
      );
    } catch (error) {
      if (mounted) AppToast.error(context, '从 $source 导入 Skills 失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _SkillImportMenuButton extends StatefulWidget {
  final bool disabled;
  final VoidCallback onCodex;
  final VoidCallback onCursor;

  const _SkillImportMenuButton({
    required this.disabled,
    required this.onCodex,
    required this.onCursor,
  });

  @override
  State<_SkillImportMenuButton> createState() => _SkillImportMenuButtonState();
}

class _SkillImportMenuButtonState extends State<_SkillImportMenuButton> {
  bool _menuOpen = false;

  Future<void> _showMenu() async {
    if (_menuOpen || widget.disabled) return;
    setState(() => _menuOpen = true);
    final result = showDropdown<void>(
      context: context,
      alignment: Alignment.topRight,
      anchorAlignment: Alignment.bottomRight,
      offset: const Offset(0, 4),
      builder: (_) => SizedBox(
        width: 170,
        child: DropdownMenu(
          surfaceOpacity: 0.98,
          surfaceBlur: 12,
          children: [
            MenuButton(
              onPressed: (_) => widget.onCodex(),
              child: const Row(
                children: [
                  Icon(BootstrapIcons.download, size: 13),
                  Gap(AppSpacing.sm),
                  Text('从 Codex 导入'),
                ],
              ),
            ),
            MenuButton(
              onPressed: (_) => widget.onCursor(),
              child: const Row(
                children: [
                  Icon(BootstrapIcons.download, size: 13),
                  Gap(AppSpacing.sm),
                  Text('从 Cursor 导入'),
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
      tooltip: '导入 Skills',
      onPressed: widget.disabled ? null : _showMenu,
    );
  }
}

class _SkillTile extends StatelessWidget {
  final SkillEntry skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _SkillTile({required this.skill, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: AppSpacing.tilePadding,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Switch(value: skill.enabled, onChanged: onToggle),
          const Gap(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name, style: AppTones.title(theme, size: 13)),
                if (skill.description.isNotEmpty) ...[
                  const Gap(AppSpacing.xs),
                  Text(
                    skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTones.muted(theme, size: 12),
                  ),
                ],
                if (skill.rootPath != null) ...[
                  const Gap(AppSpacing.xs),
                  AppMonoText(skill.rootPath!, size: 10),
                ],
              ],
            ),
          ),
          const Gap(AppSpacing.md),
          AppIconButton(
            icon: BootstrapIcons.trash,
            tooltip: '删除 Skill',
            color: theme.colorScheme.destructive,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
