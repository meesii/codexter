import 'package:collection/collection.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/skill_entry.dart';
import '../../services/capability_manager.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';

/// Skills 全局管理：从 Codex 导入 / 手动创建 / 临时启停
class SkillsPage extends StatefulWidget {
  final AppState appState;

  const SkillsPage({super.key, required this.appState});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  final _capabilityManager = CapabilityManager();
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final skills = widget.appState.skills;
    final enabledCount = skills.where((skill) => skill.enabled).length;

    return AppPageScaffold(
      title: 'Skills',
      subtitle: skills.isEmpty ? null : '共 ${skills.length} 个，$enabledCount 个启用',
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
          child: const AppButtonLabel(icon: BootstrapIcons.plus, label: '手动创建'),
        ),
      ],
      child: skills.isEmpty ? _buildEmpty(context) : _buildList(context, skills),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return AppEmptyState(
      icon: BootstrapIcons.puzzle,
      title: '暂无 Skills',
      subtitle: 'Skills 是给 ChatGPT 的额外操作手册，可从 ~/.codex/skills 导入或手动编写。',
      action: Button(
        style: ButtonStyle.outline(size: ButtonSize.normal),
        onPressed: _importing ? null : _importFromCodex,
        child: const AppButtonLabel(icon: BootstrapIcons.download, label: '从 Codex 导入'),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<SkillEntry> skills) {
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: skills.length,
      itemBuilder: (context, index) {
        final skill = skills[index];
        return _SkillTile(
          skill: skill,
          onToggle: (value) => widget.appState.toggleSkill(skill.name, value),
          onEdit: () => _openEditor(context, skill: skill),
          onDelete: () => _confirmDelete(context, skill),
        );
      },
    );
  }

  Future<void> _importFromCodex() async {
    setState(() => _importing = true);

    try {
      final scanned = await _capabilityManager.scanCodexSkills();
      var imported = 0;
      for (final item in scanned) {
        final existing = widget.appState.skills.firstWhereOrNull(
          (skill) => skill.name == item.name,
        );
        if (existing != null) continue;
        await widget.appState.saveSkill(
          SkillEntry(
            name: item.name,
            description: item.description,
            source: 'codex_import',
            rootPath: item.rootPath,
            createdAt: DateTime.now(),
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

  Future<void> _confirmDelete(BuildContext context, SkillEntry skill) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '删除 Skill',
      message: '确定删除「${skill.name}」吗？Codex 目录中的原始文件不会被删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!context.mounted) return;
    if (confirmed) {
      await widget.appState.deleteSkill(skill.name);
      if (!context.mounted) return;
      AppToast.success(context, 'Skill 已删除');
    }
  }

  Future<void> _openEditor(BuildContext context, {SkillEntry? skill}) async {
    final nameController = TextEditingController(text: skill?.name ?? '');
    final descController = TextEditingController(text: skill?.description ?? '');
    final bodyController = TextEditingController(
      text: await _capabilityManager.readSkillBody(skill?.rootPath) ?? '',
    );
    if (!context.mounted) return;

    await AppDialog.show<void>(
      context: context,
      title: skill == null ? '创建 Skill' : '编辑 Skill',
      description: '内容会写入应用数据目录下的 SKILL.md',
      maxWidth: 560,
      content: AppDialogFields(
        children: [
          AppField(label: '名称', controller: nameController, placeholder: 'my-skill'),
          AppField(label: '描述', controller: descController, placeholder: '一句话说明这个 Skill 做什么'),
          AppField(
            label: 'SKILL.md 内容',
            controller: bodyController,
            placeholder: '## 步骤\n1. …',
            maxLines: 10,
          ),
        ],
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
            final rootPath = await _capabilityManager.writeManualSkill(
              name: name,
              description: descController.text.trim(),
              body: bodyController.text,
            );
            await widget.appState.saveSkill(
              SkillEntry(
                name: name,
                description: descController.text.trim(),
                source: skill?.source ?? 'manual',
                rootPath: rootPath,
                enabled: skill?.enabled ?? true,
                createdAt: skill?.createdAt ?? DateTime.now(),
              ),
            );
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            AppToast.success(dialogContext, skill == null ? 'Skill 已创建' : 'Skill 已保存');
          },
          child: Text(skill == null ? '创建' : '保存'),
        ),
      ],
    );
  }
}

class _SkillTile extends StatelessWidget {
  final SkillEntry skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SkillTile({
    required this.skill,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

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
