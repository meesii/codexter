import 'dart:io';

import 'package:codexter/models/global_config.dart';
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

  test('Runtime API Key 持久化前会从 Hive 配置中清空', () async {
    final source = await File('lib/stores/app_state.dart').readAsString();
    expect(
      source,
      contains("ConfigStore.saveGlobalConfig(config.copyWith(openAiRuntimeApiKey: ''))"),
    );
    expect(source, contains('secretStore.writeOpenAiRuntimeApiKey(nextRuntimeKey)'));
  });
}
