import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../app_info.dart';
import '../../services/setup_service.dart';
import '../../stores/app_state.dart';
import '../../utils/app_paths.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';
import '../widgets/setup_wizard_steps.dart';

/// 首次启动向导：cloudflared → 域名 → Tunnel → 完成
class FirstRunPage extends StatefulWidget {
    final AppState appState;

    const FirstRunPage({super.key, required this.appState});

    @override
    State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
    static const _stepLabels = ['Cloudflared', '域名', 'Tunnel', '完成'];

    final _setupService = SetupService();
    final _domainController = TextEditingController();
    final _tunnelNameController = TextEditingController(text: 'codex-mcp');

    int _step = 0;
    bool _busy = false;
    String? _error;
    String? _status;
    String? _cloudflaredBin;
    String? _cloudflaredVersion;
    bool _probed = false;
    double _downloadFraction = 0;
    String _installPath = '';

    @override
    void initState() {
        super.initState();
        _probeCloudflared();
    }

    @override
    void dispose() {
        _domainController.dispose();
        _tunnelNameController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Scaffold(
            child: Stack(
                children: [
                    Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
                            child: Container(
                                margin: const EdgeInsets.all(AppSpacing.x2l),
                                decoration: BoxDecoration(
                                    color: theme.colorScheme.card,
                                    borderRadius: BorderRadius.circular(theme.radiusXl),
                                    border: Border.all(color: theme.colorScheme.border),
                                ),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                        _buildHeader(theme),
                                        Expanded(
                                            child: SingleChildScrollView(
                                                padding: const EdgeInsets.all(AppSpacing.x2l),
                                                child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                                    children: [
                                                        if (_error != null) ...[
                                                            AppNotice(
                                                                tone: AppNoticeTone.danger,
                                                                message: _error!,
                                                            ),
                                                            const Gap(AppSpacing.lg),
                                                        ],
                                                        if (_status != null) ...[
                                                            AppNotice(
                                                                tone: AppNoticeTone.info,
                                                                message: _status!,
                                                            ),
                                                            const Gap(AppSpacing.lg),
                                                        ],
                                                        _buildStepBody(),
                                                    ],
                                                ),
                                            ),
                                        ),
                                        _buildFooter(theme),
                                    ],
                                ),
                            ),
                        ),
                    ),
                    Positioned(
                        top: AppSpacing.lg,
                        right: AppSpacing.lg,
                        child: AppIconButton(
                            icon: widget.appState.darkMode
                                ? BootstrapIcons.sun
                                : BootstrapIcons.moon,
                            tooltip: widget.appState.darkMode ? '切换浅色' : '切换深色',
                            onPressed: () {
                                widget.appState.toggleDarkMode();
                                AppToast.info(
                                    context,
                                    widget.appState.darkMode ? '已切换至深色模式' : '已切换至浅色模式',
                                );
                            },
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildHeader(ThemeData theme) {
        return Container(
            padding: const EdgeInsets.all(AppSpacing.x2l),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text('欢迎使用 $appName', style: AppTones.title(theme, size: 18)),
                    const Gap(AppSpacing.xs),
                    Text(
                        '配置一次公网入口，之后每个工作区会自动获得独立的 UUID 地址。',
                        style: AppTones.muted(theme),
                    ),
                    const Gap(AppSpacing.xl),
                    StepIndicator(labels: _stepLabels, activeIndex: _step),
                ],
            ),
        );
    }

    Widget _buildFooter(ThemeData theme) {
        final isLastStep = _step == _stepLabels.length - 1;
        return Container(
            padding: const EdgeInsets.all(AppSpacing.x2l),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.colorScheme.border)),
            ),
            child: Row(
                children: [
                    if (_step > 0)
                        Button(
                            style: ButtonStyle.outline(size: ButtonSize.normal),
                            onPressed: _busy ? null : () => setState(() => _step--),
                            child: const Text('上一步'),
                        ),
                    const Spacer(),
                    Button(
                        style: ButtonStyle.primary(size: ButtonSize.normal),
                        onPressed: _busy ? null : (isLastStep ? _finish : _next),
                        child: Text(
                            _busy ? '处理中…' : (isLastStep ? '进入主页' : '下一步'),
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildStepBody() {
        return switch (_step) {
            0 => CloudflaredStep(
                    probed: _probed,
                    binPath: _cloudflaredBin,
                    version: _cloudflaredVersion,
                    busy: _busy,
                    downloadFraction: _downloadFraction,
                    installPath: _installPath,
                    releaseAssetName: _setupService.githubAssetName,
                    managedBinName: _setupService.managedBinName,
                    onDownload: _downloadCloudflared,
                    onRecheck: _probeCloudflared,
                    onOpenRelease: () => _openUrl(SetupService.githubReleasesUrl),
                ),
            1 => DomainStep(
                    controller: _domainController,
                    onOpenDashboard: () => _openUrl('https://dash.cloudflare.com/'),
                ),
            2 => TunnelStep(controller: _tunnelNameController),
            _ => DoneStep(
                    domain: _setupService.normalizeDomain(_domainController.text),
                    onOpenDocs: () =>
                        _openUrl('https://learn.chatgpt.com/docs/mcp-server'),
                ),
        };
    }

    Future<void> _openUrl(String url) async {
        final ok = await _setupService.openUrl(url);
        if (!mounted) return;
        if (ok) {
            AppToast.info(context, '已在浏览器中打开');
        } else {
            AppToast.error(context, '打开浏览器失败，请稍后重试');
        }
    }

    Future<void> _probeCloudflared() async {
        final target = await AppPaths.cloudflaredPath;
        final bin = await _setupService.findCloudflaredBin();
        final version = bin == null ? null : await _setupService.probeVersion(bin);
        if (!mounted) return;
        setState(() {
            _installPath = target;
            _cloudflaredBin = bin;
            _cloudflaredVersion = version;
            _probed = true;
        });
    }

    Future<void> _downloadCloudflared() async {
        setState(() {
            _busy = true;
            _error = null;
            _status = '正在下载 Cloudflared…';
            _downloadFraction = 0;
        });

        try {
            await _setupService.downloadCloudflared(onProgress: (progress) {
                if (!mounted) return;
                setState(() => _downloadFraction = progress.fraction);
            });
            await _probeCloudflared();
            if (mounted) setState(() => _status = 'Cloudflared 已就绪');
        } catch (error) {
            if (mounted) setState(() => _error = '下载失败：$error');
        } finally {
            if (mounted) {
                setState(() {
                    _busy = false;
                    _downloadFraction = 0;
                });
            }
        }
    }

    Future<void> _next() async {
        setState(() {
            _error = null;
            _status = null;
        });

        if (_step == 0 && _cloudflaredBin == null) {
            setState(() => _error = '请先安装 cloudflared');
            return;
        }
        if (_step == 1 && _setupService.normalizeDomain(_domainController.text).isEmpty) {
            setState(() => _error = '请输入有效域名');
            return;
        }
        if (_step == 2) {
            final succeeded = await _provisionTunnel();
            if (!succeeded) return;
        }
        if (mounted) setState(() => _step++);
    }

    Future<bool> _provisionTunnel() async {
        final bin = _cloudflaredBin;
        if (bin == null) {
            setState(() => _error = 'cloudflared 未安装');
            return false;
        }

        setState(() {
            _busy = true;
            _status = '正在检查 Cloudflare 登录状态…';
        });

        try {
            final domain = _setupService.normalizeDomain(_domainController.text);
            final tunnelName = _tunnelNameController.text.trim().isEmpty
                ? 'codex-mcp'
                : _tunnelNameController.text.trim();

            final login = await _setupService.loginCloudflare(bin);
            if (!login.success) throw Exception(login.error ?? 'Cloudflare 登录未完成');

            setState(() => _status = '正在创建 Tunnel…');
            final tunnelId = await _setupService.createTunnel(bin, tunnelName);

            setState(() => _status = '正在配置 DNS 路由…');
            await _setupService.routeDns(bin, tunnelName, domain);

            setState(() => _status = '正在写入配置…');
            final port = await AppPaths.findAvailablePort(18920);
            final config = await _setupService.writeTunnelConfig(
                widget.appState.config.copyWith(
                    domain: domain,
                    port: port,
                    tunnelName: tunnelName,
                    cloudflaredBin: bin,
                    useCloudflared: true,
                ),
                tunnelId,
            );
            await widget.appState.saveGlobalConfig(config);

            if (mounted) {
                setState(() {
                    _busy = false;
                    _status = 'Tunnel 已创建：$tunnelId';
                });
            }
            return true;
        } catch (error) {
            if (mounted) {
                setState(() {
                    _busy = false;
                    _status = null;
                    _error = '配置失败：$error';
                });
            }
            return false;
        }
    }

    Future<void> _finish() async {
        setState(() {
            _busy = true;
            _status = '正在启动服务…';
        });
        await widget.appState.completeFirstRun(widget.appState.config);
        if (mounted) setState(() => _busy = false);
    }
}
