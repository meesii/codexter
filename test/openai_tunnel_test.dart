import 'dart:io';

import 'package:codexter/models/global_config.dart';
import 'package:codexter/models/workspace.dart';
import 'package:codexter/services/openai_tunnel_service.dart';
import 'package:codexter/services/setup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenAI Tunnel ID 只接受 tunnel_ + 32 位十六进制格式', () {
    expect(SetupService.isValidOpenAiTunnelId('tunnel_0123456789abcdef0123456789abcdef'), isTrue);
    expect(
      SetupService.isValidOpenAiTunnelId('  tunnel_0123456789ABCDEF0123456789ABCDEF  '),
      isTrue,
    );
    expect(SetupService.isValidOpenAiTunnelId('tunnel_short'), isFalse);
    expect(SetupService.isValidOpenAiTunnelId('0123456789abcdef0123456789abcdef'), isFalse);
  });

  test('OpenAI Tunnel 只有全部预期进程 ready 才算运行', () {
    expect(
      OpenAiTunnelService.isFullyRunningState(expectedCount: 2, processCount: 2, readyCount: 2),
      isTrue,
    );
    expect(
      OpenAiTunnelService.isFullyRunningState(expectedCount: 2, processCount: 1, readyCount: 1),
      isFalse,
    );
    expect(
      OpenAiTunnelService.isFullyRunningState(expectedCount: 2, processCount: 2, readyCount: 1),
      isFalse,
    );
    expect(
      OpenAiTunnelService.isFullyRunningState(expectedCount: 0, processCount: 0, readyCount: 0),
      isFalse,
    );
  });

  test('OpenAI provider 独立启用 Tunnel，不依赖 Cloudflare 开关', () {
    final config = GlobalConfig(tunnelProvider: GlobalConfig.tunnelOpenAi, useCloudflared: false);
    expect(config.useOpenAiTunnel, isTrue);
    expect(config.tunnelEnabled, isTrue);
  });

  test('OpenAI 模式保留 Cloudflare 域名但运行时不会激活它', () {
    final openAi = GlobalConfig(
      domain: 'mcp.example.com',
      tunnelProvider: GlobalConfig.tunnelOpenAi,
      useCloudflared: false,
    );
    expect(openAi.domain, 'mcp.example.com');
    expect(openAi.baseUrl, 'http://127.0.0.1:18920');
    expect(openAi.widgetOrigin, isEmpty);

    final cloudflare = openAi.copyWith(
      tunnelProvider: GlobalConfig.tunnelCloudflare,
      useCloudflared: true,
    );
    expect(cloudflare.baseUrl, 'https://mcp.example.com');
    expect(cloudflare.widgetOrigin, 'https://mcp.example.com');
  });

  test('首次向导完成时先启动服务并设置直达主页面，再持久化完成状态', () async {
    final source = await File('lib/ui/pages/first_run_page.dart').readAsString();
    final finishStart = source.indexOf('Future<void> _finish() async');
    expect(finishStart, greaterThanOrEqualTo(0));
    final finish = source.substring(finishStart);
    final startServices = finish.indexOf('await widget.appState.startServices();');
    final onCompleted = finish.indexOf('widget.onCompleted();');
    final completeFirstRun = finish.indexOf('await widget.appState.completeFirstRun');
    expect(startServices, greaterThanOrEqualTo(0));
    expect(onCompleted, greaterThan(startServices));
    expect(completeFirstRun, greaterThan(onCompleted));
  });

  test('OpenAI API Key 持久化前会从 Hive 配置中清空', () async {
    final source = await File('lib/stores/app_state.dart').readAsString();
    expect(
      source,
      contains("ConfigStore.saveGlobalConfig(config.copyWith(openAiRuntimeApiKey: ''))"),
    );
    expect(source, contains('secretStore.writeOpenAiRuntimeApiKey(nextRuntimeKey)'));
  });

  test('Cloudflare 登录拿到授权 URL 后证书 TLS 超时允许直接重试', () {
    expect(
      SetupService.isCloudflareLoginRetryable(
        'ERR Failed to write the certificate. net/http: TLS handshake timeout',
        hasLoginUrl: true,
      ),
      isTrue,
    );
    expect(
      SetupService.isCloudflareLoginRetryable(
        'ERR Failed to write the certificate. net/http: TLS handshake timeout',
        hasLoginUrl: false,
      ),
      isFalse,
    );
  });

  test('切换 Tunnel 方案不会因普通工作区编辑丢失 OpenAI Tunnel ID', () {
    final workspace = Workspace(
      uuid: 'workspace-1',
      name: 'Codexter',
      projectRoot: r'X:\\codexter',
      createdAt: DateTime(2026),
      lastActiveAt: DateTime(2026),
      openAiTunnelId: 'tunnel_0123456789abcdef0123456789abcdef',
    );
    final updated = workspace.copyWith(name: 'Codexter Updated');
    expect(updated.openAiTunnelId, workspace.openAiTunnelId);
  });

  test('切到 OpenAI 后工作区 Tunnel ID 改为逐个配置', () async {
    final wizard = await File('lib/ui/widgets/tunnel_switch_dialog.dart').readAsString();
    final appState = await File('lib/stores/app_state.dart').readAsString();
    final service = await File('lib/services/openai_tunnel_service.dart').readAsString();
    final home = await File('lib/ui/pages/home_page.dart').readAsString();

    expect(wizard, contains("label: '验证 Tunnel ID'"));
    expect(wizard, contains('不会写入任何工作区'));
    expect(wizard, isNot(contains('_workspaceTunnelControllers')));
    expect(appState, isNot(contains('必须配置 OpenAI Tunnel ID')));
    expect(service, contains('workspace.openAiTunnelId?.trim().isNotEmpty'));
    expect(home, contains("'未配置 Tunnel ID'"));
  });

  test('已有工作区在 OpenAI 模式下允许暂时留空 Tunnel ID', () async {
    final source = await File('lib/ui/widgets/create_workspace_dialog.dart').readAsString();
    expect(source, contains('final creating = widget.workspace == null;'));
    expect(source, contains('(creating && openAiTunnelId.isEmpty)'));
    expect(source, contains('openAiTunnelId.isNotEmpty &&'));
    expect(source, contains('final duplicate = openAiTunnelId.isEmpty'));
  });

  test('全局设置通过独立向导切换 Tunnel，而不是直接修改 provider', () async {
    final source = await File('lib/ui/widgets/settings_dialog.dart').readAsString();
    expect(source, contains('TunnelSwitchDialog.show(context, appState)'));
    expect(source, contains("label: '切换方案'"));
    expect(source, isNot(contains('_tunnelProvider = GlobalConfig.tunnelOpenAi;')));
    expect(source, isNot(contains('_tunnelProvider = GlobalConfig.tunnelCloudflare;')));
  });

  test('Tunnel 切换失败会恢复原配置和工作区', () async {
    final source = await File('lib/stores/app_state.dart').readAsString();
    final switchStart = source.indexOf('Future<void> switchTunnelProvider');
    expect(switchStart, greaterThanOrEqualTo(0));
    final body = source.substring(switchStart);
    expect(body, contains('final previousConfig = _config;'));
    expect(body, contains('final previousWorkspaces = List<Workspace>.of(_workspaces);'));
    expect(body, contains('await saveGlobalConfig(previousConfig);'));
    expect(body, contains('_workspaces = previousWorkspaces;'));
  });

  test('两种 Tunnel 配置切换时都保留另一套配置', () async {
    final firstRun = await File('lib/ui/pages/first_run_page.dart').readAsString();
    final settings = await File('lib/ui/widgets/settings_dialog.dart').readAsString();
    final workspaceDialog = await File(
      'lib/ui/widgets/create_workspace_dialog.dart',
    ).readAsString();
    expect(
      firstRun,
      isNot(
        contains(
          "openAiRuntimeApiKey: _openAiApiKeyController.text.trim(),\\n              domain: '',",
        ),
      ),
    );
    expect(settings, contains('? appState.config.domain'));
    expect(
      workspaceDialog,
      isNot(contains('clearOpenAiTunnelId: !widget.appState.config.useOpenAiTunnel')),
    );
  });
}
