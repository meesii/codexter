import 'dart:async';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../models/process_info.dart';
import '../../services/process_session_manager.dart';
import '../../utils/fmt.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'json_view.dart';

/// 运行终端面板：每个受管进程一张卡片，可手动结束
class TerminalPanel extends StatefulWidget {
  final ProcessSessionManager? processManager;
  final int toolCalls;
  final int errorCount;
  final int processCount;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  const TerminalPanel({
    super.key,
    required this.processManager,
    required this.toolCalls,
    required this.errorCount,
    required this.processCount,
    required this.tabIndex,
    required this.onTabChanged,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = widget.processManager;
    final processes = manager?.list() ?? const <ProcessInfo>[];

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
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: manager == null
              ? const AppEmptyState(
                  icon: BootstrapIcons.terminal,
                  title: '工作区未启动',
                  subtitle: '启用工作区并启动服务后才能管理进程。',
                )
              : processes.isEmpty
              ? const AppEmptyState(
                  icon: BootstrapIcons.terminal,
                  title: '没有受管进程',
                  subtitle: 'ChatGPT 通过 exec_command 启动的进程会显示在这里，可随时手动结束。',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.workspaceDetailContentHorizontal,
                    AppSpacing.xl,
                    AppSpacing.workspaceDetailContentHorizontal,
                    AppSpacing.x2l,
                  ),
                  itemCount: processes.length,
                  itemBuilder: (context, index) =>
                      _TerminalCard(manager: manager, info: processes[index]),
                ),
        ),
      ],
    );
  }
}

class _TerminalCard extends StatelessWidget {
  final ProcessSessionManager manager;
  final ProcessInfo info;

  const _TerminalCard({required this.manager, required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final output = manager.viewOutput(info.processId);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppStatusDot(
                tone: info.running ? AppStatusTone.live : AppStatusTone.idle,
              ),
              const Gap(AppSpacing.sm),
              Text(
                '#${info.processId}',
                style: AppTones.title(theme, size: 13),
              ),
              const Gap(AppSpacing.sm),
              Expanded(child: AppMonoText(info.label, size: 11)),
              AppTag(
                label: info.stateText,
                color: info.running ? AppTones.success : null,
              ),
              const Gap(AppSpacing.sm),
              AppStat(
                icon: BootstrapIcons.clock,
                value: Fmt.duration(info.wallTime.inMilliseconds),
              ),
              const Gap(AppSpacing.md),
              Button(
                style: ButtonStyle.destructive(size: ButtonSize.small),
                onPressed: info.running ? () => _confirmKill(context) : null,
                child: const AppButtonLabel(
                  icon: BootstrapIcons.stopFill,
                  label: '结束',
                ),
              ),
            ],
          ),
          const Gap(AppSpacing.md),
          ConsoleView(text: output),
        ],
      ),
    );
  }

  Future<void> _confirmKill(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '结束进程',
      message: '将先发送 SIGTERM，2 秒后仍未退出则强制结束：\n${info.command}',
      confirmLabel: '结束进程',
      destructive: true,
    );
    if (!context.mounted) return;
    if (!confirmed) return;
    try {
      await manager.kill(info.processId);
      if (!context.mounted) return;
      AppToast.success(context, '进程已结束');
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, '结束失败：$error');
    }
  }
}
