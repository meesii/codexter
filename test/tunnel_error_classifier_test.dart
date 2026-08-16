import 'package:codexter/services/tunnel_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TunnelErrorClassifier', () {
    test('识别 DNS NXDOMAIN / Failed host lookup', () {
      final info = TunnelErrorClassifier.classify(
        "SocketException: Failed host lookup: 'mcp.example.com'",
      );
      expect(info.code, TunnelIssueCode.dnsMissing);
      expect(info.repairable, isTrue);
    });

    test('识别 Cloudflare 1033', () {
      final info = TunnelErrorClassifier.classify(
        '<title>Error 1033 | Cloudflare</title>',
        httpStatus: 530,
      );
      expect(info.code, TunnelIssueCode.cloudflare1033);
    });

    test('识别 Cloudflare 1016', () {
      final info = TunnelErrorClassifier.classify(
        '<title>Error 1016 | Origin DNS error</title>',
        httpStatus: 530,
      );
      expect(info.code, TunnelIssueCode.cloudflare1016);
    });

    test('识别缺少 cert.pem', () {
      final info = TunnelErrorClassifier.classify('未找到当前环境的 Cloudflare cert.pem，请重新登录 Cloudflare');
      expect(info.code, TunnelIssueCode.originCertMissing);
    });

    test('识别缺少 Tunnel credentials', () {
      final info = TunnelErrorClassifier.classify(
        "Tunnel credentials file 'abc.json' doesn't exist or is not a file",
      );
      expect(info.code, TunnelIssueCode.tunnelCredentialsMissing);
    });

    test('识别 origin 502 / connection refused', () {
      final info = TunnelErrorClassifier.classify(
        'dial tcp 127.0.0.1:18920: connect: connection refused',
        httpStatus: 502,
      );
      expect(info.code, TunnelIssueCode.originUnreachable);
    });
  });
}
