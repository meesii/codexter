import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 系统级敏感信息存储。macOS 使用无需 Keychain Sharing entitlement 的本机 Keychain 模式。
class SecretStore {
  static const _openAiRuntimeApiKeyKey = 'openai_runtime_api_key';

  final FlutterSecureStorage _storage;

  SecretStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          (Platform.isMacOS
              ? const FlutterSecureStorage(
                  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
                )
              : const FlutterSecureStorage());

  Future<String> readOpenAiRuntimeApiKey() async {
    return (await _storage.read(key: _openAiRuntimeApiKeyKey))?.trim() ?? '';
  }

  Future<void> writeOpenAiRuntimeApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: _openAiRuntimeApiKeyKey);
      return;
    }
    await _storage.write(key: _openAiRuntimeApiKeyKey, value: normalized);
  }
}
