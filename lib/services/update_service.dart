import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';

typedef UpdateProgress = void Function(double? fraction);

class AppUpdateInfo {
  final String version;
  final String tag;
  final String installerUrl;
  final String installerSha256;
  final String? releaseUrl;
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.version,
    required this.tag,
    required this.installerUrl,
    required this.installerSha256,
    this.releaseUrl,
    this.publishedAt,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final windows = json['windows'];
    if (windows is! Map) {
      throw const FormatException('更新清单缺少 Windows 安装包信息');
    }
    final version = '${json['version'] ?? ''}'.trim();
    final installerUrl = '${windows['installer_url'] ?? ''}'.trim();
    final installerSha256 = '${windows['installer_sha256'] ?? ''}'.trim();
    if (version.isEmpty || installerUrl.isEmpty || installerSha256.isEmpty) {
      throw const FormatException('更新清单字段不完整');
    }
    return AppUpdateInfo(
      version: version,
      tag: '${json['tag'] ?? 'v$version'}'.trim(),
      installerUrl: installerUrl,
      installerSha256: installerSha256.toLowerCase(),
      releaseUrl: '${json['release_url'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['release_url']}'.trim(),
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
    );
  }
}

class UpdateCheckResult {
  final String currentVersion;
  final AppUpdateInfo latest;

  const UpdateCheckResult({required this.currentVersion, required this.latest});

  bool get hasUpdate =>
      AppUpdateService.compareVersions(latest.version, currentVersion) > 0;
}

class AppUpdateService {
  AppUpdateService([this._manifestUrl = appUpdateManifestUrl]);

  final String _manifestUrl;

  Future<UpdateCheckResult> check() async {
    final currentVersion = await AppRuntimeInfo.version;
    final data = await _fetchJson(Uri.parse(_manifestUrl));
    return UpdateCheckResult(
      currentVersion: currentVersion,
      latest: AppUpdateInfo.fromJson(data),
    );
  }

  Future<File> downloadInstaller(
    AppUpdateInfo update, {
    UpdateProgress? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前仅支持 Windows 自动安装更新');
    }

    final uri = Uri.parse(update.installerUrl);
    final client = _client();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, '$appName Updater');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('下载更新失败（HTTP ${response.statusCode}）', uri: uri);
      }

      final tempDir = await getTemporaryDirectory();
      final file = File(
        p.join(tempDir.path, '$appName-${update.version}-Setup.exe'),
      );
      if (await file.exists()) await file.delete();

      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0 ? response.contentLength : null;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(total == null ? null : received / total);
        }
      } finally {
        await sink.close();
      }

      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != update.installerSha256) {
        await file.delete();
        throw const FormatException('安装包校验失败，请重新下载');
      }
      onProgress?.call(1);
      return file;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> launchInstaller(File installer) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前仅支持 Windows 自动安装更新');
    }
    await Process.start(installer.path, const [
      // /SILENT 会保留 Inno Setup 的安装进度窗口；/VERYSILENT 会连进度窗口一起隐藏。
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final client = _client();
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, '$appName Updater');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('检查更新失败（HTTP ${response.statusCode}）', uri: uri);
      }
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('更新清单格式错误');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15);

  static int compareVersions(String left, String right) {
    final a = _parseVersion(left);
    final b = _parseVersion(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _parseVersion(String value) {
    final core = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('-')
        .first;
    return core
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList(growable: false);
  }
}
