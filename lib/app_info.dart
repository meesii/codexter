import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

const appName = 'Codexter';
const appId = 'codexter';
const appLogoAsset = 'assets/brand/logo.png';
const defaultUpdateManifestUrl =
    'https://github.com/meesii/codexter/releases/latest/download/latest.json';
const appUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue: defaultUpdateManifestUrl,
);

/// Debug 运行只隔离应用配置目录；目录内部文件名和结构保持不变。
String get appConfigDirName => kDebugMode ? '$appId-dev' : appId;

class AppRuntimeInfo {
  const AppRuntimeInfo._();

  static Future<PackageInfo>? _packageInfo;
  static Future<String>? _version;
  static Future<String>? _versionLabel;

  static Future<PackageInfo> get packageInfo => _packageInfo ??= PackageInfo.fromPlatform();

  static Future<String> get version => _version ??= packageInfo.then((info) => info.version);

  static Future<String> get versionLabel =>
      _versionLabel ??= version.then((value) => kDebugMode ? 'v$value · DEV' : 'v$value');
}
