class JsonRpcError {
  final int code;
  final String message;
  final Object? data;

  const JsonRpcError(this.code, this.message, {this.data});

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  static const parseError = JsonRpcError(-32700, 'Parse error');
  static const invalidRequest = JsonRpcError(-32600, 'Invalid Request');
  static const methodNotFound = JsonRpcError(-32601, 'Method not found');
  static const invalidParams = JsonRpcError(-32602, 'Invalid params');
  static const internalError = JsonRpcError(-32603, 'Internal error');

  static JsonRpcError internal(Object error) {
    return JsonRpcError(-32603, 'Internal error', data: '$error');
  }

  static JsonRpcError params(String message) {
    return JsonRpcError(-32602, message);
  }
}

class JsonRpcRequest {
  final Object? id;
  final String method;
  final Map<String, dynamic>? params;

  const JsonRpcRequest({this.id, required this.method, this.params});

  /// MCP 通知没有 id，按协议不能回响应体
  bool get isNotification => id == null;

  static JsonRpcRequest? tryParse(Object? json) {
    if (json is! Map) return null;
    final method = json['method'];
    if (method is! String || method.isEmpty) return null;
    final params = json['params'];
    return JsonRpcRequest(
      id: json['id'],
      method: method,
      params: params is Map ? params.cast<String, dynamic>() : null,
    );
  }

  String? get toolName => params?['name'] as String?;

  Map<String, dynamic> get arguments {
    final args = params?['arguments'];
    if (args is Map) return args.cast<String, dynamic>();
    return const {};
  }
}

class JsonRpcResponse {
  final Object? id;
  final Map<String, dynamic>? result;
  final JsonRpcError? error;

  const JsonRpcResponse({this.id, this.result, this.error});

  factory JsonRpcResponse.success(Object? id, Map<String, dynamic> result) {
    return JsonRpcResponse(id: id, result: result);
  }

  factory JsonRpcResponse.failure(Object? id, JsonRpcError error) {
    return JsonRpcResponse(id: id, error: error);
  }

  bool get isSuccess => error == null;

  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': '2.0',
      'id': id,
      if (error != null) 'error': error!.toJson() else 'result': result ?? const {},
    };
  }
}
