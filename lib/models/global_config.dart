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

    GlobalConfig copyWith({
        String? domain,
        String? host,
        int? port,
        bool? useCloudflared,
        String? tunnelId,
        String? tunnelName,
        String? cloudflaredBin,
        bool? firstRunCompleted,
        bool? darkMode,
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
            darkMode: darkMode ?? this.darkMode,
        );
    }
}