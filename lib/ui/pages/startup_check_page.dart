import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app_info.dart';
import '../../services/doctor_service.dart';
import '../../services/tunnel_error_classifier.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';

class StartupCheckPage extends StatefulWidget {
  final AppState appState;
  final VoidCallback onContinue;

  const StartupCheckPage({
    super.key,
    required this.appState,
    required this.onContinue,
  });

  @override
  State<StartupCheckPage> createState() => _StartupCheckPageState();
}

class _StartupCheckPageState extends State<StartupCheckPage> {
  List<DoctorCheck> _checks = const [];
  String _status = '正在准备运行环境…';
  String? _activeTitle;
  String? _repairingTitle;
  String? _repairError;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  List<DoctorCheck> get _failedChecks =>
      _checks.where((check) => check.state == DoctorState.fail).toList();

  Future<void> _runChecks() async {
    if (!mounted) return;
    setState(() {
      _checks = const [];
      _checking = true;
      _repairError = null;
      _activeTitle = null;
      _status = '正在启动本地服务…';
    });

    try {
      final checks = await widget.appState.runStartupChecks(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _status = status);
        },
        onCheckStart: (title) {
          if (!mounted) return;
          setState(() {
            _activeTitle = title;
            _status = '正在检查 $title…';
          });
        },
        onCheckComplete: (check) {
          if (!mounted) return;
          setState(() {
            _checks = [..._checks, check];
          });
        },
      );
      if (!mounted) return;
      final failed = checks
          .where((check) => check.state == DoctorState.fail)
          .toList();
      setState(() {
        _checks = checks;
        _activeTitle = null;
        _checking = false;
        _status = failed.isEmpty ? '运行环境检查通过' : '发现 ${failed.length} 项需要处理';
      });
      if (failed.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (mounted) widget.onContinue();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _activeTitle = null;
        _status = '启动检测未完成';
        _repairError = '$error';
      });
    }
  }

  Future<void> _repair(DoctorCheck check) async {
    if (_repairingTitle != null) return;
    setState(() {
      _repairingTitle = check.title;
      _repairError = null;
    });
    try {
      await widget.appState.repairDoctorCheck(check);
      if (!mounted) return;
      await _runChecks();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _repairError = '$error';
      });
    } finally {
      if (mounted) setState(() => _repairingTitle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = _failedChecks;
    final showFailures =
        !_checking && (failed.isNotEmpty || _repairError != null);

    return Scaffold(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.background,
              AppTones.surfaceRaised(theme),
              theme.colorScheme.background,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.x2l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    appLogoAsset,
                    width: 52,
                    height: 52,
                    filterQuality: FilterQuality.high,
                  ),
                  const Gap(AppSpacing.xl),
                  Text(
                    showFailures ? '运行环境需要处理' : '正在启动 $appName',
                    style: AppTones.title(theme, size: 16),
                  ),
                  const Gap(AppSpacing.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_checking) ...[
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(),
                        ),
                        const Gap(AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: AppTones.muted(theme, size: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_checking && _activeTitle != null) ...[
                    const Gap(AppSpacing.xs),
                    AppMonoText(
                      '${_checks.length + 1} / ${DoctorService.startupCheckTitles.length}',
                      size: 10.5,
                    ),
                  ],
                  if (showFailures) ...[
                    const Gap(AppSpacing.x2l),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.card.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(theme.radiusXl),
                        border: Border.all(color: theme.colorScheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final check in failed) ...[
                            _StartupIssueTile(
                              check: check,
                              repairing: _repairingTitle == check.title,
                              onRepair: check.repairable
                                  ? () => _repair(check)
                                  : null,
                            ),
                            if (check != failed.last) const Gap(AppSpacing.sm),
                          ],
                          if (_repairError != null) ...[
                            if (failed.isNotEmpty) const Gap(AppSpacing.md),
                            AppNotice(
                              tone: AppNoticeTone.danger,
                              message: '自动修复失败',
                              detail: _repairError,
                              detailMaxLines: 6,
                            ),
                          ],
                          const Gap(AppSpacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Button(
                                style: ButtonStyle.outline(
                                  size: ButtonSize.normal,
                                ),
                                onPressed: _repairingTitle == null
                                    ? _runChecks
                                    : null,
                                child: const AppButtonLabel(
                                  icon: BootstrapIcons.arrowRepeat,
                                  label: '重新检测',
                                ),
                              ),
                              const Gap(AppSpacing.sm),
                              Button(
                                style: ButtonStyle.primary(
                                  size: ButtonSize.normal,
                                ),
                                onPressed: _repairingTitle == null
                                    ? widget.onContinue
                                    : null,
                                child: const Text('仍然进入主页面'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupIssueTile extends StatelessWidget {
  final DoctorCheck check;
  final bool repairing;
  final VoidCallback? onRepair;

  const _StartupIssueTile({
    required this.check,
    required this.repairing,
    required this.onRepair,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.destructive;
    final raw = check.rawError?.trim();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Icon(
              BootstrapIcons.exclamationTriangle,
              size: 15,
              color: color,
            ),
          ),
          const Gap(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        check.title,
                        style: AppTones.title(theme, size: 12.5),
                      ),
                    ),
                    const Gap(AppSpacing.sm),
                    AppTag(label: _issueLabel(check.issue), color: color),
                  ],
                ),
                const Gap(AppSpacing.xs),
                Text(
                  check.detail,
                  style: AppTones.muted(theme, size: 10.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (raw != null && raw.isNotEmpty && raw != check.detail) ...[
                  const Gap(2),
                  AppMonoText(raw, size: 9.5, maxLines: 2),
                ],
              ],
            ),
          ),
          if (onRepair != null) ...[
            const Gap(AppSpacing.md),
            Button(
              style: ButtonStyle.outline(size: ButtonSize.small),
              onPressed: repairing ? null : onRepair,
              child: repairing
                  ? const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(),
                    )
                  : const Text('修复'),
            ),
          ],
        ],
      ),
    );
  }

  static String _issueLabel(TunnelIssueCode issue) {
    return switch (issue) {
      TunnelIssueCode.cloudflaredMissing => 'CLOUDFLARED-MISSING',
      TunnelIssueCode.originCertMissing => 'CERT-MISSING',
      TunnelIssueCode.tunnelMissing => 'TUNNEL-MISSING',
      TunnelIssueCode.tunnelCredentialsMissing => 'CREDENTIALS-MISSING',
      TunnelIssueCode.tunnelConfigMissing => 'CONFIG-MISSING',
      TunnelIssueCode.domainMissing => 'DOMAIN-MISSING',
      TunnelIssueCode.localServerStopped => 'LOCAL-SERVER-DOWN',
      TunnelIssueCode.tunnelStopped => 'TUNNEL-DOWN',
      TunnelIssueCode.dnsMissing => 'DNS-NXDOMAIN',
      TunnelIssueCode.dnsUnauthorized => 'DNS-AUTH',
      TunnelIssueCode.cloudflare1016 => 'CF-1016',
      TunnelIssueCode.cloudflare1033 => 'CF-1033',
      TunnelIssueCode.originUnreachable => 'ORIGIN-UNREACHABLE',
      TunnelIssueCode.originTlsError => 'ORIGIN-TLS',
      TunnelIssueCode.originProtocolMismatch => 'ORIGIN-PROTOCOL',
      TunnelIssueCode.publicHttpError => 'PUBLIC-HTTP',
      TunnelIssueCode.timeout => 'TIMEOUT',
      TunnelIssueCode.unknown => 'UNKNOWN',
      TunnelIssueCode.none => 'OK',
    };
  }
}
