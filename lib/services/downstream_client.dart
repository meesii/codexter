import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../app_info.dart';
import '../models/downstream_mcp_entry.dart';
import '../utils/path_guard.dart';
import 'computer_use_client.dart';
import 'computer_use_tools.dart';
import 'network_proxy.dart';

enum DownstreamState { idle, connecting, connected, failed, closed }

const defaultStartupTimeoutMs = 20000;
const defaultToolTimeoutMs = 60000;
const downstreamProtocolVersion = '2025-06-18';

/// 单个下游 MCP 连接，支持内置能力、stdio 子进程与 streamable http 传输。
class DownstreamClient {
  final DownstreamMcpEntry entry;

  DownstreamState state = DownstreamState.idle;
  String? lastError;
  List<Map<String, dynamic>> tools = const [];
  Map<String, dynamic>? serverInfo;

  Process? _child;
  ComputerUseClient? _computerUse;
  HttpClient? _httpClient;
  String? _httpSessionId;
  StreamSubscription<String>? _stdoutSub;
  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  DownstreamClient(this.entry);

  String get name => entry.name;

  bool get isConnected => state == DownstreamState.connected;

  int get startupTimeoutMs => entry.startupTimeoutMs ?? defaultStartupTimeoutMs;

  int get toolTimeoutMs => entry.toolTimeoutMs ?? defaultToolTimeoutMs;

  String get transportKind {
    if (entry.isBuiltinComputerUse) return 'builtin';
    if (entry.isStdio) return 'stdio';
    if (entry.isUrl) return 'http';
    return 'unknown';
  }

  String get targetDescription {
    if (entry.isBuiltinComputerUse) {
      return _computerUse?.runtimePaths?.helperPath ?? 'Auto-discover Codex Computer Use runtime';
    }
    if (entry.isStdio) return entry.command ?? '';
    if (entry.isUrl) return entry.url ?? '';
    return '';
  }

  String? get description => entry.isBuiltinComputerUse
      ? computerUseMcpDescription
      : serverInfo?['description'] as String?;

  Map<String, dynamic> toStatusJson() {
    return {
      'name': name,
      if (entry.displayName != name) 'displayName': entry.displayName,
      'transport': transportKind,
      'target': targetDescription,
      'state': state.name,
      'toolCount': tools.length,
      if (description != null) 'description': description,
      if (entry.isBuiltin) 'builtIn': true,
      if (lastError != null) 'error': lastError,
    };
  }

  Future<void> connect() async {
    if (state == DownstreamState.connecting || state == DownstreamState.connected) return;
    state = DownstreamState.connecting;
    lastError = null;

    try {
      if (entry.isBuiltinComputerUse) {
        tools = computerUseToolDefinitions.map((tool) => Map<String, dynamic>.from(tool)).toList();
        final client = ComputerUseClient();
        _computerUse = client;
        await client.start();
        serverInfo = {
          'name': computerUseMcpDisplayName,
          'version': client.runtimePaths?.skyVersion ?? 'Codex runtime',
          'description': computerUseMcpDescription,
        };
        state = DownstreamState.connected;
        return;
      }

      if (entry.isStdio) {
        await _startStdio();
      } else if (entry.isUrl) {
        _httpClient = NetworkProxy.createHttpClient()
          ..connectionTimeout = Duration(milliseconds: startupTimeoutMs);
      } else {
        throw Exception('未配置 command 或 url');
      }

      final initResult = await _request('initialize', {
        'protocolVersion': downstreamProtocolVersion,
        'capabilities': const <String, dynamic>{},
        'clientInfo': const {'name': appId, 'version': '1.0.0'},
      }, timeoutMs: startupTimeoutMs);
      serverInfo = initResult['serverInfo'] as Map<String, dynamic>?;
      _notify('notifications/initialized');

      await refreshTools();
      state = DownstreamState.connected;
    } catch (error) {
      lastError = '$error';
      await close();
      state = DownstreamState.failed;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> refreshTools() async {
    if (entry.isBuiltinComputerUse) {
      tools = computerUseToolDefinitions.map((tool) => Map<String, dynamic>.from(tool)).toList();
      return tools;
    }
    final result = await _request('tools/list', const {}, timeoutMs: startupTimeoutMs);
    final rawTools = result['tools'];
    tools = rawTools is List ? rawTools.whereType<Map<String, dynamic>>().toList() : const [];
    return tools;
  }

  Future<Map<String, dynamic>> callTool(String toolName, Map<String, dynamic> arguments) {
    if (entry.isBuiltinComputerUse) {
      final client = _computerUse;
      if (client == null) throw StateError('Computer Use is not connected');
      return client.callTool(toolName, arguments, timeoutMs: toolTimeoutMs);
    }
    return _request('tools/call', {
      'name': toolName,
      'arguments': arguments,
    }, timeoutMs: toolTimeoutMs);
  }

  Future<Map<String, dynamic>> listResources() {
    if (entry.isBuiltinComputerUse) return Future.value({'resources': const []});
    return _request('resources/list', const {});
  }

  Future<Map<String, dynamic>> readResource(String uri) {
    if (entry.isBuiltinComputerUse) {
      throw UnsupportedError('Computer Use does not expose resources');
    }
    return _request('resources/read', {'uri': uri});
  }

  Future<Map<String, dynamic>> listPrompts() {
    if (entry.isBuiltinComputerUse) return Future.value({'prompts': const []});
    return _request('prompts/list', const {});
  }

  Future<Map<String, dynamic>> getPrompt(String promptName, Map<String, dynamic> arguments) {
    if (entry.isBuiltinComputerUse) throw UnsupportedError('Computer Use does not expose prompts');
    return _request('prompts/get', {'name': promptName, 'arguments': arguments});
  }

  Future<void> close() async {
    state = DownstreamState.closed;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('连接已关闭: $name'));
      }
    }
    _pending.clear();

    await _stdoutSub?.cancel();
    _stdoutSub = null;

    final computerUse = _computerUse;
    _computerUse = null;
    await computerUse?.close();

    final child = _child;
    _child = null;
    if (child != null) {
      try {
        child.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }

    _httpClient?.close(force: true);
    _httpClient = null;
    _httpSessionId = null;
  }

  Future<void> _startStdio() async {
    final command = entry.command;
    if (command == null || command.isEmpty) throw Exception('command 为空');

    final environment = NetworkProxy.processEnvironment(overrides: entry.env);

    try {
      _child = await Process.start(
        command,
        entry.args,
        workingDirectory: entry.cwd,
        environment: environment,
      );
    } on ProcessException catch (error) {
      // Windows 的 .cmd/.bat 以及通过 PATHEXT 暴露的命令不能总被
      // CreateProcess 直接解析。仅在“找不到文件/命令”时通过 shell 重试，
      // 保持可执行文件在正常情况下仍然直接启动。
      if (!Platform.isWindows || error.errorCode != 2) rethrow;

      _child = await Process.start(
        command,
        entry.args,
        workingDirectory: entry.cwd,
        environment: environment,
        runInShell: true,
      );
    }

    _stdoutSub = _child!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine);

    _child!.stderr.listen((data) {
      final text = TextDecode.bytes(data).trim();
      if (text.isNotEmpty) lastError = text;
    });

    _child!.exitCode.then((code) {
      if (state != DownstreamState.closed) {
        state = DownstreamState.failed;
        lastError = '进程退出 (code $code)';
      }
    });
  }

  void _onStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    _completePending(message);
  }

  void _completePending(Map<String, dynamic> message) {
    final rawId = message['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = message['error'];
    if (error != null) {
      completer.completeError(Exception('$name: ${error is Map ? error['message'] : error}'));
      return;
    }
    final result = message['result'];
    completer.complete(result is Map<String, dynamic> ? result : <String, dynamic>{});
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    int? timeoutMs,
  }) async {
    final requestId = _nextRequestId++;
    final payload = {
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      if (params.isNotEmpty) 'params': params,
    };
    final timeout = Duration(milliseconds: timeoutMs ?? toolTimeoutMs);

    if (entry.isStdio) {
      final completer = Completer<Map<String, dynamic>>();
      _pending[requestId] = completer;
      _writeStdio(payload);
      return completer.future.timeout(
        timeout,
        onTimeout: () {
          _pending.remove(requestId);
          throw TimeoutException('$name.$method 超时');
        },
      );
    }

    return _httpRequest(payload).timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException('$name.$method 超时');
      },
    );
  }

  void _notify(String method) {
    final payload = {'jsonrpc': '2.0', 'method': method};
    if (entry.isStdio) {
      _writeStdio(payload);
      return;
    }
    _httpRequest(payload).catchError((Object _) => <String, dynamic>{});
  }

  void _writeStdio(Map<String, dynamic> payload) {
    final child = _child;
    if (child == null) throw Exception('$name 未启动');
    child.stdin.write('${jsonEncode(payload)}\n');
  }

  Future<Map<String, dynamic>> _httpRequest(Map<String, dynamic> payload) async {
    final client = _httpClient;
    final url = entry.url;
    if (client == null || url == null) throw Exception('$name 未配置 url');

    final request = await client.postUrl(Uri.parse(url));
    // Some MCP servers compare the media type literally and reject the
    // charset parameter emitted by ContentType.json.
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    entry.headers.forEach(request.headers.set);
    if (_httpSessionId != null) {
      request.headers.set('Mcp-Session-Id', _httpSessionId!);
    }
    request.write(jsonEncode(payload));

    final response = await request.close();
    final sessionId = response.headers.value('mcp-session-id');
    if (sessionId != null) _httpSessionId = sessionId;

    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw Exception('$name HTTP ${response.statusCode}: ${body.trim()}');
    }
    if (body.trim().isEmpty) return <String, dynamic>{};

    final message = _decodeHttpBody(body);
    final error = message['error'];
    if (error != null) {
      throw Exception('$name: ${error is Map ? error['message'] : error}');
    }
    final result = message['result'];
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }

  /// streamable http 可能返回 SSE，取最后一条 data 行
  Map<String, dynamic> _decodeHttpBody(String body) {
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      return jsonDecode(trimmed) as Map<String, dynamic>;
    }
    final dataLines = trimmed
        .split('\n')
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (dataLines.isEmpty) throw Exception('$name 返回了无法解析的响应');
    return jsonDecode(dataLines.last) as Map<String, dynamic>;
  }
}
