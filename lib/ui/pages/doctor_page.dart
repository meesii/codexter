import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../services/doctor_service.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';

/// 环境检查：cloudflared、登录、Tunnel、服务、Git、工作区路径
class DoctorPage extends StatefulWidget {
  final AppState appState;

  const DoctorPage({super.key, required this.appState});

  @override
  State<DoctorPage> createState() => _DoctorPageState();
}

class _DoctorPageState extends State<DoctorPage> {
  String? _repairingTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  Future<void> _runChecks() => widget.appState.runDoctor();

  Future<void> _repairCheck(DoctorCheck check) async {
    if (_repairingTitle != null) return;
    setState(() => _repairingTitle = check.title);
    try {
      await widget.appState.repairDoctorCheck(check);
      await _runChecks();
      if (mounted) AppToast.success(context, '已修复：${check.title}');
    } catch (error) {
      if (mounted) AppToast.error(context, '修复失败：$error');
    } finally {
      if (mounted) setState(() => _repairingTitle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = widget.appState.doctorChecks;
    final running = widget.appState.doctorRunning;
    final activeTitle = widget.appState.doctorRunningTitle;
    final failed = checks.where((check) => check.state == DoctorState.fail).length;
    final checksByTitle = {for (final check in checks) check.title: check};

    return AppPageScaffold(
      title: '环境检查',
      subtitle: running
          ? '正在逐项检查'
          : checks.isEmpty
          ? null
          : failed == 0
          ? '全部通过'
          : '$failed 项需要处理',
      actions: [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: running ? null : _runChecks,
          child: const AppButtonLabel(icon: BootstrapIcons.arrowRepeat, label: '重新检查'),
        ),
      ],
      child: GridView.builder(
        padding: AppSpacing.pagePadding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 132,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        itemCount: DoctorService.checkTitles.length,
        itemBuilder: (context, index) {
          final title = DoctorService.checkTitles[index];
          final check = checksByTitle[title];
          return _CheckTile(
            title: title,
            check: check,
            loading: running && activeTitle == title,
            repairing: _repairingTitle == title,
            onRepair: check?.state == DoctorState.fail && check!.repairable && !running
                ? () => _repairCheck(check)
                : null,
          );
        },
      ),
    );
  }
}

class _CheckTile extends StatefulWidget {
  final String title;
  final DoctorCheck? check;
  final bool loading;
  final bool repairing;
  final VoidCallback? onRepair;

  const _CheckTile({
    required this.title,
    required this.check,
    required this.loading,
    required this.repairing,
    this.onRepair,
  });

  @override
  State<_CheckTile> createState() => _CheckTileState();
}

class _CheckTileState extends State<_CheckTile> {
  static const _iconBoxSize = 36.0;
  static const _statusSlotWidth = 52.0;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.check?.state;
    final tone = switch (state) {
      DoctorState.pass => AppStatusTone.live,
      DoctorState.warn => AppStatusTone.warn,
      DoctorState.fail => AppStatusTone.error,
      null => AppStatusTone.idle,
    };
    final label = switch (state) {
      DoctorState.pass => '通过',
      DoctorState.warn => '注意',
      DoctorState.fail => '失败',
      null => '等待',
    };
    final color = switch (state) {
      DoctorState.pass => AppTones.success,
      DoctorState.warn => AppTones.warning,
      DoctorState.fail => theme.colorScheme.destructive,
      null => theme.colorScheme.mutedForeground,
    };
    final detail = widget.loading ? '正在检查…' : widget.check?.detail ?? '等待检查';
    final hint = widget.loading ? null : widget.check?.hint;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AppCard(
        selected: _hovered,
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: _iconBoxSize,
                  height: _iconBoxSize,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(child: Icon(_iconFor(widget.title), size: 16, color: color)),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.card,
                            shape: BoxShape.circle,
                          ),
                          child: AppStatusDot(tone: tone, size: 6),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTones.title(theme, size: 13),
                  ),
                ),
                const Gap(AppSpacing.sm),
                SizedBox(
                  width: _statusSlotWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.loading
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator())
                        : AppTag(label: label, color: color),
                  ),
                ),
              ],
            ),
            const Gap(AppSpacing.sm),
            SizedBox(
              height: 30,
              child: AppMonoText(
                detail,
                size: 10.5,
                maxLines: 2,
                color: theme.colorScheme.foreground.withValues(alpha: 0.74),
              ),
            ),
            const Gap(AppSpacing.xs),
            SizedBox(
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    right: widget.onRepair == null ? 0 : 66,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: hint == null
                          ? const SizedBox.shrink()
                          : Text(
                              '建议：$hint',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTones.muted(theme, size: 10),
                            ),
                    ),
                  ),
                  if (widget.onRepair != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Button(
                        style: ButtonStyle.outline(size: ButtonSize.small),
                        onPressed: widget.repairing ? null : widget.onRepair,
                        child: widget.repairing
                            ? const SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(),
                              )
                            : const Text('修复'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String title) {
    return switch (title) {
      'Cloudflared' => BootstrapIcons.cloud,
      'Cloudflare 登录' => BootstrapIcons.check2,
      'Tunnel 配置' => BootstrapIcons.gear,
      '公网域名' => BootstrapIcons.link45deg,
      '本地 MCP 服务' => BootstrapIcons.hddRack,
      'Cloudflare Tunnel' => BootstrapIcons.cloud,
      '公网连通性' => BootstrapIcons.activity,
      'Git' => BootstrapIcons.terminal,
      '工作区路径' => BootstrapIcons.folder2Open,
      _ => BootstrapIcons.activity,
    };
  }
}
