import 'package:codexter/services/tunnel_process_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configPath = r'C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml';

  group('TunnelProcessGuard.isOwnedCommand', () {
    test('匹配本应用启动参数', () {
      const command =
          r'C:\Users\VCLOUD\AppData\Roaming\codexter\bin\cloudflared.exe tunnel --config C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml --protocol http2 --edge-ip-version 4 run dbfc758b-7e32-4884-821a-257da713958b';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isTrue);
    });

    test('匹配带引号的 --config 路径', () {
      const command =
          r'cloudflared.exe tunnel --config "C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml" run abc';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isTrue);
    });

    test('匹配 --config= 写法', () {
      const command =
          r'cloudflared.exe tunnel --config=C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml run abc';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isTrue);
    });

    test('不匹配用户自己的 cloudflared 配置', () {
      const command =
          r'C:\Program Files\cloudflared\cloudflared.exe tunnel --config C:\Users\VCLOUD\.cloudflared\config.yml run my-tunnel';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isFalse);
    });

    test('不匹配 quick tunnel', () {
      const command = r'cloudflared.exe tunnel --url http://127.0.0.1:3000';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isFalse);
    });

    test('不匹配空命令行', () {
      expect(TunnelProcessGuard.isOwnedCommand('', configPath), isFalse);
    });

    test('正斜杠配置路径也能匹配 Windows 命令行', () {
      const unixStyle = 'C:/Users/VCLOUD/AppData/Roaming/codexter/cloudflared.yml';
      const command =
          r'cloudflared.exe tunnel --config C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml run abc';
      expect(TunnelProcessGuard.isOwnedCommand(command, unixStyle), isTrue);
    });

    test('不匹配仅路径相似的配置文件', () {
      const command =
          r'cloudflared.exe tunnel --config C:\Users\VCLOUD\AppData\Roaming\codexter\cloudflared.yml.bak run abc';
      expect(TunnelProcessGuard.isOwnedCommand(command, configPath), isFalse);
    });
  });

  group('TunnelProcessGuard.parseOwnedPids', () {
    test('只收集属于本应用的 PID', () {
      const listing = '''
56584\tC:\\Users\\VCLOUD\\AppData\\Roaming\\codexter\\bin\\cloudflared.exe tunnel --config C:\\Users\\VCLOUD\\AppData\\Roaming\\codexter\\cloudflared.yml run dbfc758b-7e32-4884-821a-257da713958b
13988\tC:\\Program Files\\cloudflared\\cloudflared.exe tunnel --config C:\\Users\\VCLOUD\\.cloudflared\\config.yml run other
39516\tC:\\Users\\VCLOUD\\AppData\\Roaming\\codexter\\bin\\cloudflared.exe tunnel --config C:\\Users\\VCLOUD\\AppData\\Roaming\\codexter\\cloudflared.yml --protocol http2 run dbfc758b-7e32-4884-821a-257da713958b
''';
      expect(TunnelProcessGuard.parseOwnedPids(listing, configPath), [56584, 39516]);
    });

    test('跳过没有命令行的进程', () {
      const listing = '12345\t';
      expect(TunnelProcessGuard.parseOwnedPids(listing, configPath), isEmpty);
    });
  });
}
