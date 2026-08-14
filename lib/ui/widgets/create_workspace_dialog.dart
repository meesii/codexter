import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/workspace.dart';
import '../../stores/app_state.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

/// 工作区编辑对话框：名称 + 项目路径（可调用系统目录选择器）
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
      description: editing
          ? '修改名称或项目路径，UUID 与 MCP 地址保持不变'
          : '每个工作区会获得独立的 UUID 公网路径',
      maxWidth: 460,
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workspace?.name ?? '');
    _pathController = TextEditingController(
      text: widget.workspace?.projectRoot ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> submit(BuildContext dialogContext) async {
    final name = _nameController.text.trim();
    final path = _pathController.text.trim();

    if (name.isEmpty || path.isEmpty) {
      setState(() => _error = '名称和路径都不能为空');
      return;
    }
    if (!await Directory(path).exists()) {
      setState(() => _error = '路径不存在：$path');
      return;
    }

    final workspace = widget.workspace;
    if (workspace == null) {
      await widget.appState.createWorkspace(name: name, projectRoot: path);
    } else {
      await widget.appState.updateWorkspace(
        workspace.copyWith(name: name, projectRoot: path),
      );
    }
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    AppToast.success(dialogContext, workspace == null ? '工作区已创建' : '工作区已更新');
  }

  Future<void> _pickDirectory() async {
    final script = [
      "Add-Type -AssemblyName System.Windows.Forms | Out-Null",
      "\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog",
      "\$dialog.ShowNewFolderButton = \$true",
      "if (\$dialog.ShowDialog() -eq 'OK') { Write-Output \$dialog.SelectedPath }",
    ].join('; ');

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ]);
      final picked = '${result.stdout}'.trim();
      if (picked.isEmpty) return;
      setState(() {
        _pathController.text = picked;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = p.basename(picked);
        }
        _error = null;
      });
    } catch (error) {
      setState(() => _error = '打开目录选择器失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogFields(
      children: [
        AppField(
          label: '工作区名称',
          controller: _nameController,
          placeholder: 'My Project',
        ),
        AppField(
          label: '项目路径',
          controller: _pathController,
          placeholder: r'C:\Projects\my-project',
          trailing: Button(
            style: ButtonStyle.outline(size: ButtonSize.normal),
            onPressed: Platform.isWindows ? _pickDirectory : null,
            child: const Text('浏览'),
          ),
          hint: 'ChatGPT 的所有文件读写都被限制在这个目录内',
        ),
        if (_error != null)
          AppNotice(tone: AppNoticeTone.danger, message: _error!),
      ],
    );
  }
}
