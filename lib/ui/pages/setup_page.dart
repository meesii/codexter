import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../services/setup_service.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_spacing.dart';
import '../widgets/app_toast.dart';
import '../widgets/json_view.dart';

/// 公网配置：域名、监听地址、Tunnel 与 cloudflared 日志
class SetupPage extends StatefulWidget {
  final AppState appState;

  const SetupPage({super.key, required this.appState});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _setupService = SetupService();
  late TextEditingController _domainController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tunnelNameController;
  late bool _useCloudflared;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = widget.appState.config;
    _domainController = TextEditingController(text: config.domain);
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: '${config.port}');
    _tunnelNameController = TextEditingController(text: config.tunnelName);
    _useCloudflared = config.useCloudflared;
  }

  @override
  void dispose() {
    _domainController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tunnelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final config = appState.config;

    return AppPageScaffold(
      title: '公网配置',
      subtitle: config.domain.isEmpty
          ? '尚未配置域名'
          : 'https://${config.domain}/{uuid}/mcp',
      actions: [
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: _saving ? null : _saveAndRestart,
          child: AppButtonLabel(
            icon: BootstrapIcons.check2,
            label: _saving ? '应用中…' : '保存并重启服务',
          ),
        ),
      ],
      child: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (appState.lastError != null) ...[
              AppNotice(
                tone: AppNoticeTone.danger,
                message: '服务未正常启动',
                detail: appState.lastErrorSummary,
                detailMaxLines: 2,
              ),
              const Gap(AppSpacing.lg),
            ],
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(
                    title: '连接',
                    caption: '所有工作区共用同一个域名，路径由各自的 UUID 区分',
                  ),
                  AppField(
                    label: '公网域名',
                    controller: _domainController,
                    placeholder: 'mcp.example.com',
                  ),
                  const Gap(AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: AppField(
                          label: '本地监听地址',
                          controller: _hostController,
                          placeholder: '127.0.0.1',
                        ),
                      ),
                      const Gap(AppSpacing.md),
                      Expanded(
                        child: AppField(
                          label: '端口',
                          controller: _portController,
                          placeholder: '18920',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionHeader(
                    title: 'Cloudflare Tunnel',
                    caption: 'APP 启动时长驻，增删工作区不会断开',
                    trailing: Switch(
                      value: _useCloudflared,
                      onChanged: (value) =>
                          setState(() => _useCloudflared = value),
                    ),
                  ),
                  if (_useCloudflared) ...[
                    AppField(
                      label: 'Tunnel 名称',
                      controller: _tunnelNameController,
                      placeholder: 'codex-mcp',
                    ),
                    const Gap(AppSpacing.md),
                    AppInfoRow(
                      label: 'Tunnel ID',
                      value: config.tunnelId ?? '未创建',
                      mono: true,
                    ),
                    AppInfoRow(
                      label: 'Cloudflared',
                      value: config.cloudflaredBin ?? '使用内置下载路径',
                      mono: true,
                    ),
                    const Gap(AppSpacing.md),
                    Row(
                      children: [
                        Button(
                          style: ButtonStyle.outline(size: ButtonSize.normal),
                          onPressed: _saving ? null : _createTunnel,
                          child: const AppButtonLabel(
                            icon: BootstrapIcons.cloudPlus,
                            label: '创建 / 修复 Tunnel',
                          ),
                        ),
                        const Gap(AppSpacing.sm),
                        Button(
                          style: ButtonStyle.outline(size: ButtonSize.normal),
                          onPressed: _saving ? null : _verifyRoute,
                          child: const AppButtonLabel(
                            icon: BootstrapIcons.activity,
                            label: '验证连通性',
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      '已关闭公网访问，MCP 仅监听本机地址。',
                      style: AppTones.muted(Theme.of(context)),
                    ),
                ],
              ),
            ),
            if (_useCloudflared)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(title: 'Cloudflared 日志'),
                    ConsoleView(
                      text: appState.tunnelService.logTail,
                      maxHeight: 220,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndRestart() async {
    setState(() => _saving = true);

    final tunnelName = _tunnelNameController.text.trim();
    await widget.appState.saveGlobalConfig(
      widget.appState.config.copyWith(
        domain: _setupService.normalizeDomain(_domainController.text),
        host: _hostController.text.trim().isEmpty
            ? '127.0.0.1'
            : _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 18920,
        useCloudflared: _useCloudflared,
        tunnelName: tunnelName.isEmpty ? 'codex-mcp' : tunnelName,
      ),
    );
    await widget.appState.restartServices();

    if (mounted) {
      setState(() => _saving = false);
      if (widget.appState.lastError == null) {
        AppToast.success(context, '配置已保存，服务已重启');
      } else {
        AppToast.error(context, '重启失败：${widget.appState.lastErrorSummary}');
      }
    }
  }

  Future<void> _createTunnel() async {
    setState(() => _saving = true);

    try {
      final bin = await _setupService.findCloudflaredBin();
      if (bin == null) throw Exception('未找到 cloudflared，请在首次配置向导中下载');

      final domain = _setupService.normalizeDomain(_domainController.text);
      if (domain.isEmpty) throw Exception('请先填写域名');

      final tunnelName = _tunnelNameController.text.trim().isEmpty
          ? 'codex-mcp'
          : _tunnelNameController.text.trim();

      final login = await _setupService.loginCloudflare(bin);
      if (!login.success) throw Exception(login.error ?? 'Cloudflare 登录未完成');

      final tunnelId = await _setupService.createTunnel(bin, tunnelName);
      await _setupService.routeDns(bin, tunnelName, domain);

      final updated = await _setupService.writeTunnelConfig(
        widget.appState.config.copyWith(
          domain: domain,
          tunnelName: tunnelName,
          cloudflaredBin: bin,
          useCloudflared: true,
        ),
        tunnelId,
      );
      await widget.appState.saveGlobalConfig(updated);
      await widget.appState.restartServices();

      if (mounted) {
        AppToast.success(context, 'Tunnel 已创建');
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, '创建失败：$error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verifyRoute() async {
    setState(() => _saving = true);

    final domain = widget.appState.config.domain;
    if (domain.isEmpty) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.warning(context, '请先保存域名');
      }
      return;
    }

    final reachable = await widget.appState.tunnelService.verifyRoute(
      'https://$domain/healthz',
      attempts: 6,
    );
    if (mounted) {
      setState(() => _saving = false);
      if (reachable) {
        AppToast.success(context, '公网地址可用');
      } else {
        AppToast.warning(context, '公网地址暂不可用，请检查 DNS 与隧道状态');
      }
    }
  }
}
