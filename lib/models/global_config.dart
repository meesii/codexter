import 'package:hive/hive.dart';

part 'global_config.g.dart';

@HiveType(typeId: 0)
class GlobalConfig extends HiveObject {
  @HiveField(0)
  String domain;

  @HiveField(1)
  String host;

  @HiveField(2)
  int port;

  @HiveField(3)
  bool useCloudflared;

  @HiveField(4)
  String? tunnelId;

  @HiveField(5)
  String tunnelName;

  @HiveField(6)
  String? cloudflaredBin;

  @HiveField(7)
  bool firstRunCompleted;

  @HiveField(8)
  bool? darkMode;

  @HiveField(9)
  bool closeToTray;

  @HiveField(10)
  bool notificationsEnabled;

  @HiveField(11)
  bool notificationSound;

  @HiveField(12)
  double sidebarWidth;

  @HiveField(13)
  bool closeActionRemembered;

  @HiveField(14)
  bool computerUseEnabled;

  @HiveField(15, defaultValue: false)
  bool proxyEnabled;

  @HiveField(16, defaultValue: '')
  String proxyUrl;

  @HiveField(17, defaultValue: tunnelCloudflare)
  String tunnelProvider;

  @HiveField(18)
  String? tunnelClientBin;

  @HiveField(19, defaultValue: '')
  String openAiRuntimeApiKey;

  static const tunnelCloudflare = 'cloudflare';
  static const tunnelOpenAi = 'openai';

  GlobalConfig({
    this.domain = '',
    this.host = '127.0.0.1',
    this.port = 18920,
    this.useCloudflared = true,
    this.tunnelId,
    this.tunnelName = 'codex-mcp',
    this.cloudflaredBin,
    this.firstRunCompleted = false,
    this.darkMode,
    this.closeToTray = true,
    this.notificationsEnabled = true,
    this.notificationSound = true,
    this.sidebarWidth = 236,
    this.closeActionRemembered = false,
    this.computerUseEnabled = false,
    this.proxyEnabled = false,
    this.proxyUrl = '',
    this.tunnelProvider = tunnelCloudflare,
    this.tunnelClientBin,
    this.openAiRuntimeApiKey = '',
  });

  bool get useOpenAiTunnel => tunnelProvider == tunnelOpenAi;
  bool get tunnelEnabled => useCloudflared || useOpenAiTunnel;

  String get baseUrl {
    if (domain.isEmpty) return 'http://$host:$port';
    return 'https://$domain';
  }

  /// ChatGPT MCP UI 的独立组件 origin。提交带 UI 的插件时必须显式配置 HTTPS 域名。
  String get widgetOrigin => domain.isEmpty ? '' : 'https://$domain';

  String workspaceUrl(String uuid) {
    return '$baseUrl/$uuid/mcp';
  }

  String get localServiceUrl => 'http://$host:$port';

  static const _unset = Object();

  GlobalConfig copyWith({
    String? domain,
    String? host,
    int? port,
    bool? useCloudflared,
    String? tunnelId,
    String? tunnelName,
    String? cloudflaredBin,
    bool? firstRunCompleted,
    Object? darkMode = _unset,
    bool? closeToTray,
    bool? notificationsEnabled,
    bool? notificationSound,
    double? sidebarWidth,
    bool? closeActionRemembered,
    bool? computerUseEnabled,
    bool? proxyEnabled,
    String? proxyUrl,
    String? tunnelProvider,
    String? tunnelClientBin,
    String? openAiRuntimeApiKey,
  }) {
    return GlobalConfig(
      domain: domain ?? this.domain,
      host: host ?? this.host,
      port: port ?? this.port,
      useCloudflared: useCloudflared ?? this.useCloudflared,
      tunnelId: tunnelId ?? this.tunnelId,
      tunnelName: tunnelName ?? this.tunnelName,
      cloudflaredBin: cloudflaredBin ?? this.cloudflaredBin,
      firstRunCompleted: firstRunCompleted ?? this.firstRunCompleted,
      darkMode: identical(darkMode, _unset) ? this.darkMode : darkMode as bool?,
      closeToTray: closeToTray ?? this.closeToTray,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationSound: notificationSound ?? this.notificationSound,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      closeActionRemembered: closeActionRemembered ?? this.closeActionRemembered,
      computerUseEnabled: computerUseEnabled ?? this.computerUseEnabled,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      tunnelProvider: tunnelProvider ?? this.tunnelProvider,
      tunnelClientBin: tunnelClientBin ?? this.tunnelClientBin,
      openAiRuntimeApiKey: openAiRuntimeApiKey ?? this.openAiRuntimeApiKey,
    );
  }
}
