import 'dart:async';
import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app_info.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';
import '../widgets/proxy_settings_form.dart';

class StartupCheckPage extends StatefulWidget {
  final AppState appState;
  final VoidCallback onContinue;

  const StartupCheckPage({super.key, required this.appState, required this.onContinue});

  @override
  State<StartupCheckPage> createState() => _StartupCheckPageState();
}

class _StartupCheckPageState extends State<StartupCheckPage> {
  static const _cloudflareSteps = ['本地服务', '启动隧道', '连接边缘', '完成注册'];
  static const _openAiSteps = ['本地服务', '启动 Tunnel Client', '连接 OpenAI', '完成注册'];

  bool _starting = true;
  String? _error;
  int _stageIndex = 0;
  bool _retrying = false;

  AppState get _appState => widget.appState;

  @override
  void initState() {
    super.initState();
    _appState.addListener(_refresh);
    _appState.tunnelService.addListener(_refresh);
    _appState.openAiTunnelService.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _appState.removeListener(_refresh);
    _appState.tunnelService.removeListener(_refresh);
    _appState.openAiTunnelService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted || !_starting) return;
    setState(_syncStage);
  }

  void _syncStage() {
    final openAi = _appState.config.useOpenAiTunnel;
    final log = openAi ? _appState.openAiTunnelService.logTail : _appState.tunnelService.logTail;
    var reached = 0;
    var retrying = false;
    if (_appState.config.tunnelEnabled) {
      for (final line in log.split(RegExp(r'\r?\n'))) {
        if (openAi) {
          if (line.contains('start OpenAI tunnel')) reached = 1;
          if (line.contains('control') || line.contains('connect')) reached = 2;
          if (line.contains('OpenAI tunnel ready:')) reached = 3;
        } else {
          if (line.contains('Starting tunnel') || line.contains('start tunnel')) reached = 1;
          if (line.contains('curve preferences') ||
              line.contains('Initial protocol') ||
              line.contains('CONNECTIVITY PRE-CHECKS') ||
              line.toLowerCase().contains('precheck')) {
            reached = 2;
          }
          if (line.contains('Failed to dial') || line.contains('Retrying connection')) {
            reached = 2;
            retrying = true;
          }
          if (line.contains('Registered tunnel connection')) {
            reached = 3;
            retrying = false;
          }
        }
      }
    }
    if (reached > _stageIndex) _stageIndex = reached;
    _retrying = retrying && _stageIndex == 2;
  }

  void _enterMain() {
    unawaited(_appState.runDoctor());
    widget.onContinue();
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _starting = true;
      _error = null;
      _stageIndex = 0;
      _retrying = false;
    });

    try {
      await _appState.startServices();
      if (!mounted) return;
      final tunnelRequired =
          _appState.config.useCloudflared ||
          (_appState.config.useOpenAiTunnel &&
              _appState.workspaces.any((workspace) => workspace.enabled));
      if (tunnelRequired && !_appState.tunnelRunning) {
        setState(() {
          _starting = false;
          _error = _appState.lastErrorSummary ?? '隧道未在时限内就绪';
        });
        return;
      }
      setState(() {
        _stageIndex = tunnelRequired ? 3 : 0;
        _retrying = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted) return;
      _enterMain();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  Future<void> _showProxySettings() async {
    final saved = await ProxySettingsDialog.show(
      context: context,
      appState: _appState,
      description: '如果当前网络无法稳定连接 Tunnel 服务，可在这里配置 HTTP 或 SOCKS5 代理。',
    );
    if (mounted && saved) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = !_starting && _error != null;
    final tunnelSteps = _appState.config.useOpenAiTunnel ? _openAiSteps : _cloudflareSteps;
    final tunnelRequired =
        _appState.config.useCloudflared ||
        (_appState.config.useOpenAiTunnel &&
            _appState.workspaces.any((workspace) => workspace.enabled));
    final steps = tunnelRequired ? tunnelSteps : tunnelSteps.take(1).toList();

    return Scaffold(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    appLogoAsset,
                    width: 56,
                    height: 56,
                    filterQuality: FilterQuality.high,
                  ),
                  const Gap(AppSpacing.xl),
                  Text(
                    failed ? 'Tunnel 需要处理' : '正在启动 $appName',
                    style: AppTones.title(theme, size: 18),
                  ),
                  const Gap(AppSpacing.x2l),
                  _StartupStepper(
                    labels: steps,
                    currentIndex: _stageIndex.clamp(0, steps.length - 1),
                    failed: failed,
                    retrying: _retrying,
                  ),
                  if (failed) ...[
                    const Gap(AppSpacing.x2l),
                    AppNotice(
                      tone: AppNoticeTone.danger,
                      message: '暂时没有连上 Tunnel',
                      detail: _error ?? '可以换网络或配置代理后重试，也可以先进入主页面。',
                      detailMaxLines: 4,
                    ),
                    const Gap(AppSpacing.lg),
                    Row(
                      children: [
                        Button(
                          style: ButtonStyle.outline(size: ButtonSize.normal),
                          onPressed: _showProxySettings,
                          child: AppButtonLabel(
                            icon: BootstrapIcons.globe,
                            label: _appState.config.proxyEnabled
                                ? '网络代理 · ${Uri.tryParse(_appState.config.proxyUrl)?.scheme.toUpperCase() ?? 'HTTP'}'
                                : '网络代理',
                          ),
                        ),
                        const Spacer(),
                        Button(
                          style: ButtonStyle.outline(size: ButtonSize.normal),
                          onPressed: _start,
                          child: const AppButtonLabel(
                            icon: BootstrapIcons.arrowRepeat,
                            label: '重新连接',
                          ),
                        ),
                        const Gap(AppSpacing.sm),
                        Button(
                          style: ButtonStyle.primary(size: ButtonSize.normal),
                          onPressed: _enterMain,
                          child: const Text('仍然进入'),
                        ),
                      ],
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

class _StartupStepper extends StatelessWidget {
  final List<String> labels;
  final int currentIndex;
  final bool failed;
  final bool retrying;

  const _StartupStepper({
    required this.labels,
    required this.currentIndex,
    required this.failed,
    required this.retrying,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingLine = theme.colorScheme.mutedForeground.withValues(alpha: 0.28);
    final doneLine = AppTones.success.withValues(alpha: 0.55);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stepWidth = constraints.maxWidth / labels.length;
        return Stack(
          children: [
            Positioned(
              top: 10,
              left: stepWidth / 2,
              right: stepWidth / 2,
              height: 2,
              child: Row(
                children: [
                  for (var index = 0; index < labels.length - 1; index++)
                    Expanded(
                      child: _StepLine(color: index < currentIndex ? doneLine : pendingLine),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < labels.length; index++)
                  Expanded(
                    child: _StartupStep(
                      label: labels[index],
                      done:
                          index < currentIndex ||
                          (index == currentIndex && !failed && currentIndex == labels.length - 1),
                      active: index == currentIndex && !failed,
                      failed: failed && index == currentIndex,
                      retrying: retrying && index == currentIndex,
                      theme: theme,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StartupStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  final bool failed;
  final bool retrying;
  final ThemeData theme;

  const _StartupStep({
    required this.label,
    required this.done,
    required this.active,
    required this.failed,
    required this.retrying,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? theme.colorScheme.destructive
        : done
        ? AppTones.success
        : active
        ? theme.colorScheme.foreground
        : theme.colorScheme.mutedForeground.withValues(alpha: 0.42);

    return Column(
      children: [
        SizedBox(
          height: 22,
          child: Center(
            child: _StepDot(done: done, active: active, failed: failed, color: color),
          ),
        ),
        const Gap(AppSpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.sans.copyWith(
            fontSize: 11.5,
            fontWeight: active || done ? FontWeight.w500 : FontWeight.w400,
            color: color,
          ),
        ),
        SizedBox(
          height: 16,
          child: retrying
              ? Text('自动重试', textAlign: TextAlign.center, style: AppTones.muted(theme, size: 10))
              : null,
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool done;
  final bool active;
  final bool failed;
  final Color color;

  const _StepDot({
    required this.done,
    required this.active,
    required this.failed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: failed
            ? Icon(BootstrapIcons.xCircleFill, size: 16, color: color)
            : done
            ? Icon(BootstrapIcons.checkCircleFill, size: 16, color: color)
            : active
            ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator())
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final Color color;

  const _StepLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
        child: const SizedBox(height: 2, width: double.infinity),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 4.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
