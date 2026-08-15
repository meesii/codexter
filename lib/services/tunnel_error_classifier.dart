enum TunnelIssueCode {
  none,
  cloudflaredMissing,
  originCertMissing,
  tunnelMissing,
  tunnelCredentialsMissing,
  tunnelConfigMissing,
  domainMissing,
  localServerStopped,
  tunnelStopped,
  dnsMissing,
  dnsUnauthorized,
  cloudflare1016,
  cloudflare1033,
  originUnreachable,
  originTlsError,
  originProtocolMismatch,
  publicHttpError,
  timeout,
  unknown,
}

class TunnelErrorInfo {
  final TunnelIssueCode code;
  final String summary;
  final String hint;
  final bool repairable;

  const TunnelErrorInfo({
    required this.code,
    required this.summary,
    required this.hint,
    required this.repairable,
  });
}

class TunnelErrorClassifier {
  const TunnelErrorClassifier._();

  static TunnelErrorInfo classify(String raw, {int? httpStatus}) {
    final text = raw.toLowerCase();

    if (_containsAny(text, const [
      'failed host lookup',
      'no address associated with hostname',
      'name or service not known',
      'nodename nor servname provided',
      'nxdomain',
    ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.dnsMissing,
        summary: '公网域名没有可用的 DNS 解析',
        hint: '重新创建域名到 Tunnel 的 DNS 路由',
        repairable: true,
      );
    }

    if (_containsAny(text, const ['error 1033', '1033'])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.cloudflare1033,
        summary: 'Cloudflare 找不到健康的 Tunnel 连接',
        hint: '重新启动 Tunnel 并检查 cloudflared 连接状态',
        repairable: true,
      );
    }

    if (_containsAny(text, const ['error 1016', '1016'])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.cloudflare1016,
        summary: 'Cloudflare DNS 路由存在，但 Tunnel 当前不可用',
        hint: '检查 DNS 路由并重新启动 Tunnel',
        repairable: true,
      );
    }

    if (_containsAny(text, const [
          'cert.pem',
          'origincert',
          'origin cert',
          '未找到当前环境的 cloudflare cert',
        ]) &&
        _containsAny(text, const [
          'not exist',
          'doesn\'t exist',
          'no such file',
          '未找到',
          'missing',
        ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.originCertMissing,
        summary: '当前环境缺少 Cloudflare 登录凭据 cert.pem',
        hint: '重新登录 Cloudflare 后继续修复',
        repairable: true,
      );
    }

    if (_containsAny(text, const [
          'credentials file',
          'tunnel credentials',
          '缺少 tunnel credentials',
        ]) &&
        _containsAny(text, const [
          'doesn\'t exist',
          'does not exist',
          'not a file',
          'no such file',
          '缺少',
          'missing',
        ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.tunnelCredentialsMissing,
        summary: '缺少当前 Tunnel 的 credentials 文件',
        hint: '尝试恢复旧凭据或重新生成 Tunnel 配置',
        repairable: true,
      );
    }

    if (_containsAny(text, const [
      '1003',
      'unauthorized',
      'not authorized',
      'permission denied',
      'insufficient permissions',
      '无权管理',
    ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.dnsUnauthorized,
        summary: '当前 Cloudflare 登录凭据无权管理该域名',
        hint: '重新登录正确的 Cloudflare Zone 后重试',
        repairable: true,
      );
    }

    if (_containsAny(text, const [
          'connection refused',
          'unable to reach the origin service',
          'bad gateway',
        ]) ||
        httpStatus == 502) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.originUnreachable,
        summary: 'Tunnel 已连接，但本地 MCP 服务不可达',
        hint: '重新启动本地 MCP 服务并检查监听端口',
        repairable: true,
      );
    }

    if (_containsAny(text, const [
      'x509:',
      'certificate signed by unknown authority',
      'certificate is valid for',
    ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.originTlsError,
        summary: 'Tunnel 到本地服务的 TLS 校验失败',
        hint: '检查本地服务协议和证书配置',
        repairable: false,
      );
    }

    if (_containsAny(text, const [
      'malformed http response',
      'http/1.x transport connection broken',
    ])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.originProtocolMismatch,
        summary: 'Tunnel 配置的 HTTP/HTTPS 协议与本地服务不一致',
        hint: '检查 ingress service 的协议配置',
        repairable: false,
      );
    }

    if (_containsAny(text, const ['timeout', 'timed out', '未就绪'])) {
      return const TunnelErrorInfo(
        code: TunnelIssueCode.timeout,
        summary: 'Tunnel 连接超时',
        hint: '重新启动 Tunnel；若持续失败请查看详细日志',
        repairable: true,
      );
    }

    if (httpStatus != null && httpStatus >= 500) {
      return TunnelErrorInfo(
        code: TunnelIssueCode.publicHttpError,
        summary: '公网地址返回 HTTP $httpStatus',
        hint: '检查 Tunnel、DNS 和本地服务状态',
        repairable: true,
      );
    }

    return const TunnelErrorInfo(
      code: TunnelIssueCode.unknown,
      summary: '无法自动识别 Tunnel 错误',
      hint: '查看详细错误和 cloudflared 日志',
      repairable: false,
    );
  }

  static bool _containsAny(String text, List<String> patterns) {
    return patterns.any(text.contains);
  }
}
