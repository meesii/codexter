import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../models/global_config.dart';
import '../../models/workspace.dart';
import '../../services/setup_service.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'cloudflare_login_notice.dart';
import 'setup_wizard_steps.dart';

class TunnelSwitchDialog {
  const TunnelSwitchDialog._();

  static Future<bool> show(BuildContext context, AppState appState) async {
    final targetProvider = appState.config.useOpenAiTunnel
        ? GlobalConfig.tunnelCloudflare
        : GlobalConfig.tunnelOpenAi;
    return await AppDialog.show<bool>(
          context: context,
          title: '切换隧道方案',
          description: targetProvider == GlobalConfig.tunnelOpenAi
              ? '保留现有工作区和 Cloudflare 配置，完成验证后切换到 OpenAI Tunnel。'
              : '保留现有工作区和 OpenAI Tunnel 配置，完成验证后切换到 Cloudflare Tunnel。',
          maxWidth: 720,
          maxHeight: 680,
          barrierDismissible: false,
          scrollContent: false,
          showCloseButton: false,
          content: _TunnelSwitchWizard(appState: appState, targetProvider: targetProvider),
        ) ??
        false;
  }
}

class _TunnelSwitchWizard extends StatefulWidget {
  final AppState appState;
  final String targetProvider;

  const _TunnelSwitchWizard({required this.appState, required this.targetProvider});

  @override
  State<_TunnelSwitchWizard> createState() => _TunnelSwitchWizardState();
}

class _TunnelSwitchWizardState extends State<_TunnelSwitchWizard> {
  final SetupService _setupService = SetupService();
  late final TextEditingController _domainController;
  late final TextEditingController _tunnelNameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _testTunnelIdController;

  int _step = 0;
  bool _busy = false;
  bool _probed = false;
  String? _bin;
  String? _version;
  String _installPath = '';
  double _downloadFraction = 0;
  String? _status;
  String? _loginUrl;
  GlobalConfig? _preparedCloudflareConfig;

  bool get _targetOpenAi => widget.targetProvider == GlobalConfig.tunnelOpenAi;

  List<String> get _labels =>
      _targetOpenAi ? const ['环境', '凭据', '连接', '切换'] : const ['环境', '配置', '连接', '切换'];

  @override
  void initState() {
    super.initState();
    final config = widget.appState.config;
    _domainController = TextEditingController(text: config.domain);
    _tunnelNameController = TextEditingController(text: config.tunnelName);
    _apiKeyController = TextEditingController();
    _testTunnelIdController = TextEditingController(
      text: widget.appState.workspaces
          .map((workspace) => workspace.openAiTunnelId?.trim() ?? '')
          .firstWhere(SetupService.isValidOpenAiTunnelId, orElse: () => ''),
    );
    _probe();
  }

  @override
  void dispose() {
    _domainController.dispose();
    _tunnelNameController.dispose();
    _apiKeyController.dispose();
    _testTunnelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 470,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepIndicator(labels: _labels, activeIndex: _step),
          const Gap(AppSpacing.xl),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: KeyedSubtree(
                  key: ValueKey('${widget.targetProvider}-$_step'),
                  child: _buildStep(theme),
                ),
              ),
            ),
          ),
          if (_loginUrl != null) ...[
            const Gap(AppSpacing.md),
            CloudflareLoginNotice(url: _loginUrl!),
          ] else if (_status != null) ...[
            const Gap(AppSpacing.md),
            Row(
              children: [
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator()),
                const Gap(AppSpacing.sm),
                Expanded(child: Text(_status!, style: AppTones.muted(theme, size: 11.5))),
              ],
            ),
          ],
          const Gap(AppSpacing.lg),
          Divider(color: theme.colorScheme.border, height: 1),
          const Gap(AppSpacing.lg),
          Row(
            children: [
              Button(
                style: ButtonStyle.outline(size: ButtonSize.normal),
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              const Spacer(),
              if (_step > 0) ...[
                Button(
                  style: ButtonStyle.outline(size: ButtonSize.normal),
                  onPressed: _busy ? null : () => setState(() => _step--),
                  child: const Text('上一步'),
                ),
                const Gap(AppSpacing.sm),
              ],
              Button(
                style: ButtonStyle.primary(size: ButtonSize.normal),
                onPressed: _busy ? null : (_step == _labels.length - 1 ? _commit : _next),
                child: Text(_busy ? '处理中…' : (_step == _labels.length - 1 ? '切换并重启' : '下一步')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep(ThemeData theme) {
    if (_targetOpenAi) {
      return switch (_step) {
        0 => TunnelClientStep(
          probed: _probed,
          binPath: _bin,
          version: _version,
          busy: _busy,
          downloadFraction: _downloadFraction,
          installPath: _installPath,
          releaseAssetName: _setupService.tunnelClientAssetName,
          managedBinName: _setupService.tunnelClientManagedBinName,
          onDownload: _downloadBinary,
          onRecheck: _probe,
          onOpenRelease: () => _setupService.openUrl(SetupService.tunnelClientReleasesUrl),
        ),
        1 => _buildOpenAiCredentials(theme),
        2 => const AppNotice(
          tone: AppNoticeTone.info,
          message: '测试 Tunnel Client 到 OpenAI 的真实连接',
          detail:
              '点击「下一步」后会使用上一步的验证 Tunnel ID 临时启动 Tunnel Client，验证 Tunnels Use 权限和控制面连接。已有工作区不会在这里批量修改。',
        ),
        _ => _buildOpenAiSummary(theme),
      };
    }

    return switch (_step) {
      0 => CloudflaredStep(
        probed: _probed,
        binPath: _bin,
        version: _version,
        busy: _busy,
        downloadFraction: _downloadFraction,
        installPath: _installPath,
        releaseAssetName: _setupService.githubAssetName,
        managedBinName: _setupService.managedBinName,
        onDownload: _downloadBinary,
        onRecheck: _probe,
        onOpenRelease: () => _setupService.openUrl(SetupService.githubReleasesUrl),
      ),
      1 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DomainStep(
            controller: _domainController,
            onOpenDashboard: () => _setupService.openUrl('https://dash.cloudflare.com/'),
          ),
          const Gap(AppSpacing.xl),
          TunnelStep(controller: _tunnelNameController),
        ],
      ),
      2 => AppNotice(
        tone: AppNoticeTone.info,
        message: '验证 Cloudflare Tunnel',
        detail: widget.appState.config.tunnelId?.trim().isNotEmpty == true
            ? '点击「下一步」会优先复用之前保存的 Tunnel 和凭据，修复 DNS 路由并验证公网解析。'
            : '点击「下一步」会登录 Cloudflare、创建 Tunnel、配置 DNS，并验证公网解析。',
      ),
      _ => _buildCloudflareSummary(theme),
    };
  }

  Widget _buildOpenAiCredentials(ThemeData theme) {
    final hasSavedKey = widget.appState.config.openAiRuntimeApiKey.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          label: 'OpenAI API Key',
          controller: _apiKeyController,
          obscure: true,
          placeholder: hasSavedKey ? '已保存，留空则继续使用' : 'sk-...',
          hint: '需要目标 Tunnel 的 Tunnels Read + Use 权限。Key 仍只保存到系统安全存储。',
        ),
        const Gap(AppSpacing.lg),
        AppField(
          label: '验证 Tunnel ID',
          controller: _testTunnelIdController,
          placeholder: 'tunnel_0123456789abcdef0123456789abcdef',
          hint: '只用于验证 OpenAI API Key 和 Tunnel Client 连接，不会写入任何工作区。切换完成后再到各工作区分别配置。',
        ),
        const Gap(AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Button(
              style: ButtonStyle.outline(size: ButtonSize.small),
              onPressed: _busy
                  ? null
                  : () => _setupService.openUrl(
                      'https://platform.openai.com/settings/organization/api-keys',
                    ),
              child: const Text('API Keys'),
            ),
            Button(
              style: ButtonStyle.outline(size: ButtonSize.small),
              onPressed: _busy
                  ? null
                  : () => _setupService.openUrl(
                      'https://platform.openai.com/settings/organization/tunnels',
                    ),
              child: const Text('Tunnels 管理'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOpenAiSummary(ThemeData theme) {
    final missingCount = widget.appState.workspaces
        .where((workspace) => (workspace.openAiTunnelId ?? '').trim().isEmpty)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppNotice(
          tone: AppNoticeTone.success,
          message: 'OpenAI Tunnel 配置已验证',
          detail: '点击「切换并重启」后才会真正停止 Cloudflare Tunnel 并启用 OpenAI Tunnel；工作区本身不会被修改。',
        ),
        if (missingCount > 0) ...[
          const Gap(AppSpacing.lg),
          Text(
            '$missingCount 个工作区尚未配置 Tunnel ID。切换完成后可在对应工作区的「修改工作区」中逐个填写；未配置前这些工作区不会启动 OpenAI Tunnel。',
            style: AppTones.body(theme),
          ),
        ],
      ],
    );
  }

  Widget _buildCloudflareSummary(ThemeData theme) {
    final config = _preparedCloudflareConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppNotice(
          tone: AppNoticeTone.success,
          message: 'Cloudflare Tunnel 已验证',
          detail:
              '点击「切换并重启」后才会真正停止 OpenAI Tunnel 并启用 Cloudflare Tunnel；工作区和已保存的 OpenAI Tunnel ID 都会保留。',
        ),
        const Gap(AppSpacing.lg),
        Text(
          '公网域名：${config?.domain ?? _domainController.text.trim()}',
          style: AppTones.body(theme),
        ),
        const Gap(AppSpacing.sm),
        Text(
          'Tunnel：${config?.tunnelName ?? _tunnelNameController.text.trim()}',
          style: AppTones.body(theme),
        ),
      ],
    );
  }

  Future<void> _probe() async {
    if (mounted) {
      setState(() {
        _probed = false;
        _status = null;
      });
    }
    final config = widget.appState.config;
    final bin = _targetOpenAi
        ? await _setupService.findTunnelClientBin(configuredPath: config.tunnelClientBin)
        : await _setupService.findCloudflaredBin(configuredPath: config.cloudflaredBin);
    final version = bin == null ? null : await _setupService.probeVersion(bin);
    final installPath = _targetOpenAi
        ? await _setupService.tunnelClientPath
        : await _setupService.cloudflaredPath;
    if (!mounted) return;
    setState(() {
      _bin = bin;
      _version = version;
      _installPath = installPath;
      _probed = true;
    });
  }

  Future<void> _downloadBinary() async {
    setState(() {
      _busy = true;
      _downloadFraction = 0;
      _status = _targetOpenAi ? '正在下载 Tunnel Client…' : '正在下载 cloudflared…';
    });
    try {
      if (_targetOpenAi) {
        await _setupService.downloadTunnelClient(
          onProgress: (progress) {
            if (mounted) setState(() => _downloadFraction = progress.fraction);
          },
        );
      } else {
        await _setupService.downloadCloudflared(
          onProgress: (progress) {
            if (mounted) setState(() => _downloadFraction = progress.fraction);
          },
        );
      }
      await _probe();
    } catch (error) {
      if (mounted) AppToast.error(context, '下载失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadFraction = 0;
          _status = null;
        });
      }
    }
  }

  Future<void> _next() async {
    if (_step == 0) {
      await _probe();
      if (!mounted) return;
      if (_bin == null) {
        AppToast.warning(context, _targetOpenAi ? '请先安装 Tunnel Client' : '请先安装 cloudflared');
        return;
      }
    } else if (_step == 1) {
      if (_targetOpenAi) {
        final valid = await _validateOpenAiCredentials();
        if (!valid || !mounted) return;
      } else {
        final domain = _setupService.normalizeDomain(_domainController.text);
        if (domain.isEmpty) {
          AppToast.warning(context, '请输入有效公网域名');
          return;
        }
        if (_tunnelNameController.text.trim().isEmpty) {
          AppToast.warning(context, '请输入 Tunnel 名称');
          return;
        }
      }
    } else if (_step == 2) {
      final ok = _targetOpenAi ? await _testOpenAiConnection() : await _prepareCloudflareTarget();
      if (!ok || !mounted) return;
    }

    if (mounted) setState(() => _step++);
  }

  String get _effectiveApiKey {
    final input = _apiKeyController.text.trim();
    return input.isEmpty ? widget.appState.config.openAiRuntimeApiKey.trim() : input;
  }

  Future<bool> _validateOpenAiCredentials() async {
    final key = _effectiveApiKey;
    final tunnelId = _testTunnelIdController.text.trim();
    if (key.isEmpty) {
      AppToast.warning(context, '请填写 OpenAI API Key');
      return false;
    }
    if (!SetupService.isValidOpenAiTunnelId(tunnelId)) {
      AppToast.warning(context, '请填写有效的验证 Tunnel ID');
      return false;
    }
    setState(() {
      _busy = true;
      _status = '正在验证 OpenAI API Key 和 Tunnel Read 权限…';
    });
    try {
      await _setupService.validateOpenAiTunnelRuntimeKey(apiKey: key, tunnelId: tunnelId);
      if (mounted) AppToast.success(context, 'OpenAI API Key 验证通过');
      return true;
    } catch (error) {
      if (mounted) {
        final message = error is FormatException ? error.message : '$error';
        AppToast.error(context, '验证失败：$message');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<bool> _testOpenAiConnection() async {
    final bin = _bin;
    if (bin == null) return false;
    setState(() {
      _busy = true;
      _status = '正在测试 Tunnel Client 连接…';
    });
    try {
      await _setupService.testOpenAiTunnelClientConnection(
        bin: bin,
        apiKey: _effectiveApiKey,
        tunnelId: _testTunnelIdController.text.trim(),
      );
      if (mounted) AppToast.success(context, 'OpenAI Tunnel 连接测试通过');
      return true;
    } catch (error) {
      if (mounted) {
        final message = error is FormatException ? error.message : '$error';
        AppToast.error(context, '连接测试失败：$message');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<bool> _prepareCloudflareTarget() async {
    final bin = _bin;
    if (bin == null) return false;
    final domain = _setupService.normalizeDomain(_domainController.text);
    final tunnelName = _tunnelNameController.text.trim();
    setState(() {
      _busy = true;
      _status = '正在检查 Cloudflare 登录状态…';
      _loginUrl = null;
    });

    try {
      final login = await _setupService.loginCloudflare(
        bin,
        onLoginUrl: (url) {
          if (mounted) setState(() => _loginUrl = url);
        },
      );
      if (!mounted) return false;
      if (login.authorizationPending) {
        AppToast.info(context, 'Cloudflare 授权或证书获取暂未完成，请确认浏览器授权后再次点击「下一步」');
        return false;
      }
      if (!login.success) throw Exception(login.error ?? 'Cloudflare 登录未完成');

      String? tunnelId = widget.appState.config.tunnelName == tunnelName
          ? widget.appState.config.tunnelId?.trim()
          : null;
      if (tunnelId != null && tunnelId.isNotEmpty) {
        final hasCredentials = await _setupService.ensureTunnelCredentials(tunnelId);
        if (!hasCredentials) tunnelId = null;
      }

      if (tunnelId == null || tunnelId.isEmpty) {
        if (mounted) setState(() => _status = '正在创建 Cloudflare Tunnel…');
        try {
          tunnelId = await _setupService.createTunnel(bin, tunnelName);
        } on TunnelNameConflictException catch (conflict) {
          if (!mounted) return false;
          final replace = await AppDialog.confirm(
            context: context,
            title: 'Tunnel 名称已存在',
            message:
                'Cloudflare 中已经存在名为「${conflict.name}」的 Tunnel，但本机没有可复用的运行凭据。是否删除旧 Tunnel 并重新创建？这会中断其他正在使用该 Tunnel 的设备。',
            confirmLabel: '删除并重建',
            destructive: true,
          );
          if (!replace) return false;
          setState(() => _status = '正在删除旧 Tunnel…');
          await _setupService.deleteTunnel(conflict.tunnelId);
          setState(() => _status = '正在重新创建 Tunnel…');
          tunnelId = await _setupService.createTunnel(bin, tunnelName);
        }
      }

      if (mounted) setState(() => _status = '正在配置并验证 DNS…');
      await _setupService.ensureDnsRoute(
        bin,
        tunnelId,
        domain,
        onLoginUrl: (url) {
          if (mounted) setState(() => _loginUrl = url);
        },
      );

      var target = widget.appState.config.copyWith(
        domain: domain,
        tunnelName: tunnelName,
        cloudflaredBin: bin,
        useCloudflared: true,
        tunnelProvider: GlobalConfig.tunnelCloudflare,
      );
      target = await _setupService.writeTunnelConfig(target, tunnelId);
      _preparedCloudflareConfig = target;
      if (mounted) AppToast.success(context, 'Cloudflare Tunnel 配置验证通过');
      return true;
    } catch (error) {
      if (mounted) AppToast.error(context, '验证失败：$error');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _loginUrl = null;
        });
      }
    }
  }

  List<Workspace> _targetWorkspaces() => List<Workspace>.of(widget.appState.workspaces);

  Future<void> _commit() async {
    final targetConfig = _targetOpenAi
        ? widget.appState.config.copyWith(
            tunnelProvider: GlobalConfig.tunnelOpenAi,
            useCloudflared: false,
            tunnelClientBin: _bin,
            openAiRuntimeApiKey: _effectiveApiKey,
          )
        : _preparedCloudflareConfig;
    if (targetConfig == null) {
      AppToast.error(context, '目标 Tunnel 配置尚未完成验证');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在切换 Tunnel 并重启服务…';
    });
    try {
      await widget.appState.switchTunnelProvider(
        targetConfig: targetConfig,
        targetWorkspaces: _targetWorkspaces(),
      );
      if (!mounted) return;
      AppToast.success(context, _targetOpenAi ? '已切换到 OpenAI Tunnel' : '已切换到 Cloudflare Tunnel');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) AppToast.error(context, '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }
}
