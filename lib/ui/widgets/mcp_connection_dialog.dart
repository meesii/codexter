import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../services/setup_service.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_dialog.dart';
import 'app_spacing.dart';
import 'app_toast.dart';

/// 展示工作区 MCP 地址，并引导用户在 ChatGPT 中创建自定义 MCP 应用。
class McpConnectionDialog {
  const McpConnectionDialog._();

  static Future<void> show(
    BuildContext context,
    String url, {
    bool useTunnel = false,
    String? tunnelId,
  }) {
    final value = useTunnel ? (tunnelId ?? '') : url;
    return AppDialog.show<void>(
      context: context,
      title: '连接到 ChatGPT',
      description: '在 ChatGPT 插件页面创建 MCP 应用，并使用当前工作区的连接信息。',
      maxWidth: 520,
      content: _McpConnectionContent(url: url, useTunnel: useTunnel, tunnelId: tunnelId),
      actions: (dialogContext) => [
        Button(
          style: ButtonStyle.outline(size: ButtonSize.normal),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
        Button(
          style: ButtonStyle.primary(size: ButtonSize.normal),
          onPressed: value.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: value));
                  AppToast.success(dialogContext, useTunnel ? 'Tunnel ID 已复制' : 'MCP URL 已复制');
                },
          child: Text(useTunnel ? '复制 Tunnel ID' : '复制 MCP URL'),
        ),
      ],
    );
  }
}

class _McpConnectionContent extends StatelessWidget {
  final String url;
  final bool useTunnel;
  final String? tunnelId;

  const _McpConnectionContent({required this.url, required this.useTunnel, this.tunnelId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tunnelValue = tunnelId?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(useTunnel ? 'Tunnel ID' : 'MCP URL', style: AppTones.title(theme, size: 12)),
        const Gap(AppSpacing.sm),
        AppCopyField(
          value: useTunnel && tunnelValue.isEmpty ? '尚未配置' : (useTunnel ? tunnelValue : url),
          selectable: true,
          maxLines: 1,
          compact: true,
        ),
        const Gap(AppSpacing.xl),
        Text('添加到 ChatGPT', style: AppTones.title(theme, size: 12)),
        const Gap(AppSpacing.md),
        _ConnectStep(
          index: 1,
          content: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('打开 '),
              _InlineLink(
                label: '设置',
                onPressed: () =>
                    SetupService().openUrl('https://chatgpt.com/plugins#settings/Security'),
              ),
              const Text(' → 开启“开发者模式”；打开 '),
              _InlineLink(
                label: '插件',
                onPressed: () => SetupService().openUrl('https://chatgpt.com/plugins'),
              ),
              const Text(' → 点击“+”号'),
            ],
          ),
        ),
        const _ConnectStep(index: 2, text: '选择“Create APP” → “创建 MCP 应用”'),
        _ConnectStep(
          index: 3,
          text: useTunnel
              ? (tunnelValue.isEmpty
                    ? '先编辑当前工作区并填写 OpenAI Tunnel ID'
                    : '在“连接”中选择“隧道”，选择对应隧道或手动填写上方 Tunnel ID')
              : '在“连接”中选择“服务器 URL”，填写上方 MCP URL',
        ),
        const _ConnectStep(index: 4, text: '“身份验证”选择“无身份验证”，填写名称和描述后创建插件', showLine: false),
      ],
    );
  }
}

class _InlineLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _InlineLink({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Text(
          label,
          style: AppTones.body(theme, size: 12).copyWith(height: 1.45, color: AppTones.info),
        ),
      ),
    );
  }
}

class _ConnectStep extends StatelessWidget {
  final int index;
  final String? text;
  final Widget? content;
  final bool showLine;

  const _ConnectStep({required this.index, this.text, this.content, this.showLine = true})
    : assert(text != null || content != null);

  TextSpan _buildStepTextSpan(ThemeData theme) {
    final baseStyle = AppTones.body(theme, size: 12).copyWith(height: 1.45);
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    final value = text ?? '';
    final matches = RegExp(r'“([^”]+)”').allMatches(value);
    var offset = 0;

    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: value.substring(offset, match.start)));
      }
      spans.add(const TextSpan(text: '“'));
      spans.add(TextSpan(text: match.group(1), style: boldStyle));
      spans.add(const TextSpan(text: '”'));
      offset = match.end;
    }

    if (offset < value.length) {
      spans.add(TextSpan(text: value.substring(offset)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTones.surfaceSunken(theme),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.border),
                  ),
                  child: Text(
                    '$index',
                    style: theme.typography.sans.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: theme.colorScheme.border,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? AppSpacing.md : 0),
              child: content == null
                  ? Text.rich(_buildStepTextSpan(theme))
                  : DefaultTextStyle(
                      style: AppTones.body(theme, size: 12).copyWith(height: 1.45),
                      child: content!,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
