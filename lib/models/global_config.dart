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
  });

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
      closeActionRemembered:
          closeActionRemembered ?? this.closeActionRemembered,
    );
  }
}
