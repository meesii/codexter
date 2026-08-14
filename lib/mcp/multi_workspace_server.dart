import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/summary_notice.dart';
import '../models/workspace.dart';
import '../services/capability_runtime.dart';
import '../stores/log_store.dart';
import 'mcp_server.dart';

final RegExp _mcpPathRegex = RegExp(
    r'^/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/mcp/?$',
);

/// 单端口多路径 MCP 路由。增删工作区只改内部 Map，不影响 HttpServer 与 Tunnel
class MultiWorkspaceServer {
    final Map<String, WorkspaceHandler> _handlers = {};
    HttpServer? _server;
    String _host = '127.0.0.1';
    int _port = 0;
    String _widgetDomain = '';

    bool get isRunning => _server != null;
    String get host => _host;
    int get port => _port;
    String get widgetDomain => _widgetDomain;
    List<String> get workspaceUuids => _handlers.keys.toList();

    void setWidgetDomain(String origin) {
        _widgetDomain = origin.trim();
        for (final handler in _handlers.values) {
            handler.widgetDomain = _widgetDomain;
        }
    }

    Future<void> start({required String host, required int port}) async {
        if (_server != null) return;
        _host = host;
        _port = port;
        _server = await HttpServer.bind(host, port, shared: false);
        _server!.idleTimeout = const Duration(minutes: 30);
        _serve();
    }

    Future<void> stop() async {
        for (final handler in _handlers.values) {
            await handler.close();
        }
        _handlers.clear();
        final server = _server;
        _server = null;
        await server?.close(force: true);
    }

    WorkspaceHandler addWorkspace({
        required Workspace workspace,
        required LogStore logStore,
        required CapabilityRuntime capabilities,
        SummaryHandler? onSummary,
    }) {
        removeWorkspace(workspace.uuid);
        final handler = WorkspaceHandler.create(
            workspace: workspace,
            logStore: logStore,
            capabilities: capabilities,
            widgetDomain: _widgetDomain,
            onSummary: onSummary,
        );
        _handlers[workspace.uuid] = handler;
        return handler;
    }

    void removeWorkspace(String uuid) {
        final handler = _handlers.remove(uuid);
        handler?.close();
    }

    bool hasWorkspace(String uuid) => _handlers.containsKey(uuid);

    WorkspaceHandler? handlerOf(String uuid) => _handlers[uuid];

    Future<void> _serve() async {
        final server = _server;
        if (server == null) return;

        await for (final request in server) {
            // Streamable HTTP clients may issue tool calls, UI resource reads and
            // protocol requests concurrently. Do not serialize the whole endpoint
            // behind one slow tool invocation.
            unawaited(_handleRequest(request));
        }
    }

    Future<void> _handleRequest(HttpRequest request) async {
        try {
            await _route(request);
        } catch (error) {
            debugPrint('MCP 请求处理失败: $error');
            try {
                request.response.statusCode = HttpStatus.internalServerError;
                await request.response.close();
            } catch (_) {}
        }
    }

    Future<void> _route(HttpRequest request) async {
        final path = request.uri.path;

        if (path == '/healthz') {
            await _writeJson(request, HttpStatus.ok, {
                'ok': true,
                'workspaces': _handlers.length,
            });
            return;
        }

        final match = _mcpPathRegex.firstMatch(path);
        if (match == null) {
            await _writeJson(request, HttpStatus.notFound, {'error': 'not found'});
            return;
        }

        final handler = _handlers[match.group(1)!.toLowerCase()];
        if (handler == null) {
            await _writeJson(request, HttpStatus.notFound, {'error': 'workspace not found'});
            return;
        }

        await handler.handle(request);
    }

    Future<void> _writeJson(HttpRequest request, int status, Map<String, dynamic> body) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
    }
}
