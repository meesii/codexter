import 'dart:convert';
import 'package:hive/hive.dart';

part 'downstream_mcp_entry.g.dart';

@HiveType(typeId: 3)
class DownstreamMcpEntry extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String transportJson;

  @HiveField(2)
  bool enabled;

  @HiveField(3)
  String source;

  @HiveField(4)
  int? startupTimeoutMs;

  @HiveField(5)
  int? toolTimeoutMs;

  DownstreamMcpEntry({
    required this.name,
    required this.transportJson,
    this.enabled = true,
    required this.source,
    this.startupTimeoutMs,
    this.toolTimeoutMs,
  });

  static const builtinComputerUseName = 'computer-use';

  bool get isCodexImport => source == 'codex_import';
  bool get isCursorImport => source == 'cursor_import';
  bool get isBuiltin => source == 'builtin';

  Map<String, dynamic> get transport => jsonDecode(transportJson) as Map<String, dynamic>;

  bool get isBuiltinComputerUse => isBuiltin && transport['builtin'] == 'computer-use';
  bool get isStdio => transport.containsKey('command');
  bool get isUrl => transport.containsKey('url');
  String get displayName => isBuiltinComputerUse ? 'Computer Use' : name;

  String? get command => transport['command'] as String?;

  List<String> get args {
    final raw = transport['args'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  Map<String, String> get env {
    final raw = transport['env'];
    if (raw is Map) return raw.cast<String, String>();
    return {};
  }

  String? get cwd => transport['cwd'] as String?;

  String? get url => transport['url'] as String?;

  Map<String, String> get headers {
    final raw = transport['headers'];
    if (raw is Map) return raw.cast<String, String>();
    return {};
  }

  String get transportSummary {
    if (isBuiltinComputerUse) return 'builtin: Codex Computer Use';
    if (isStdio) {
      final cmd = command ?? '';
      return 'stdio: $cmd';
    }
    if (isUrl) return 'url: $url';
    return 'unknown';
  }

  factory DownstreamMcpEntry.builtinComputerUse({required bool enabled}) {
    return DownstreamMcpEntry(
      name: builtinComputerUseName,
      transportJson: jsonEncode({'builtin': 'computer-use'}),
      enabled: enabled,
      source: 'builtin',
      startupTimeoutMs: 20000,
      toolTimeoutMs: 60000,
    );
  }

  static String buildStdioJson({
    required String command,
    List<String> args = const [],
    Map<String, String> env = const {},
    String? cwd,
  }) {
    final map = <String, dynamic>{'command': command};
    if (args.isNotEmpty) map['args'] = args;
    if (env.isNotEmpty) map['env'] = env;
    if (cwd != null && cwd.isNotEmpty) map['cwd'] = cwd;
    return jsonEncode(map);
  }

  static String buildUrlJson({required String url, Map<String, String> headers = const {}}) {
    final map = <String, dynamic>{'url': url};
    if (headers.isNotEmpty) map['headers'] = headers;
    return jsonEncode(map);
  }
}
