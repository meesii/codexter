import 'dart:ui' as ui;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../services/setup_service.dart';
import '../../stores/app_state.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';
import 'app_spacing.dart';
import 'app_toast.dart';
import 'json_view.dart';

class SettingsDialog {
  const SettingsDialog._();

  static Future<void> show(BuildContext context, AppState appState) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭设置',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final theme = Theme.of(dialogContext);
        final dark = theme.colorScheme.brightness == Brightness.dark;
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        final scale = Tween<double>(begin: 0.975, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: fade,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: dark ? 0.32 : 0.18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: FadeTransition(
                    opacity: fade,
                    child: ScaleTransition(
                      scale: scale,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 800,
                          maxHeight: 620,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: _SettingsDialogBody(appState: appState),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );
  }
}

class _SettingsDialogBody extends StatefulWidget {
  final AppState appState;

  const _SettingsDialogBody({required this.appState});

  @override
  State<_SettingsDialogBody> createState() => _SettingsDialogBodyState();
}

class _SettingsDialogBodyState extends State<_SettingsDialogBody> {
  final SetupService _setupService = SetupService();
  late final TextEditingController _domainController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tunnelNameController;
  late bool _useCloudflared;
  int _section = 0;
  bool _saving = false;

  AppState get appState => widget.appState;

  @override
  void initState() {
    super.initState();
    final config = appState.config;
    _domainController = TextEditingController(text: config.domain);
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: '${config.port}');
    _tunnelNameController = TextEditingController(text: config.tunnelName);
    _useCloudflared = config.useCloudflared;
    appState.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _domainController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tunnelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDialogHeader(context),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNavigation(context),
                Expanded(child: _buildSection(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTones.borderSubtle(theme))),
      ),
      child: Row(
        children: [
          Expanded(child: Text('全局设置', style: AppTones.title(theme, size: 16))),
          _CloseButton(onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 158,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppTones.borderSubtle(theme))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsNavItem(
            icon: BootstrapIcons.sliders,
            label: '常规',
            selected: _section == 0,
            onTap: () => setState(() => _section = 0),
          ),
          _SettingsNavItem(
            icon: BootstrapIcons.bell,
            label: '通知',
            selected: _section == 1,
            onTap: () => setState(() => _section = 1),
          ),
          _SettingsNavItem(
            icon: BootstrapIcons.cloud,
            label: '公网服务',
            selected: _section == 2,
            onTap: () => setState(() => _section = 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    final title = switch (_section) {
      0 => '常规',
      1 => '通知',
      _ => '公网服务',
    };
    final description = switch (_section) {
      0 => '应用运行方式和界面外观。',
      1 => '控制 ChatGPT 完成一轮处理后的提醒方式。',
      _ => '配置本地监听与 Cloudflare Tunnel。',
    };

    final action = switch (_section) {
      1 => Button(
        style: ButtonStyle.outline(size: ButtonSize.small),
        onPressed: appState.config.notificationsEnabled
            ? _testNotification
            : null,
        child: const AppButtonLabel(icon: BootstrapIcons.bell, label: '测试通知'),
      ),
      2 => Button(
        style: ButtonStyle.primary(size: ButtonSize.small),
        onPressed: _saving ? null : _saveAndRestart,
        child: AppButtonLabel(
          icon: BootstrapIcons.check2,
          label: _saving ? '应用中…' : '保存并重启',
        ),
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title, description: description, action: action),
        Expanded(
          child: ClipRect(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: switch (_section) {
                    0 => _buildGeneral(context),
                    1 => _buildNotifications(context),
                    _ => _buildNetwork(context),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneral(BuildContext context) {
    final config = appState.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupHeading(title: '应用偏好', description: '这些设置会立即生效。'),
        const Gap(AppSpacing.md),
        _SettingsGroup(
          children: [
            _SettingItem(
              title: '关闭窗口时最小化到托盘',
              description: '关闭主窗口后继续保持 MCP、Tunnel 和运行中的命令。',
              trailing: Switch(
                value: config.closeToTray,
                onChanged: appState.setCloseToTray,
              ),
            ),
            _SettingItem(
              title: '界面主题',
              description: '跟随系统自动切换，或固定为浅色 / 深色。',
              trailing: _ThemeSelector(appState: appState),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotifications(BuildContext context) {
    final config = appState.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupHeading(
          title: '任务完成提醒',
          description: '收到 summary 后由系统通知中心提醒你，无需一直盯着 ChatGPT。',
        ),
        const Gap(AppSpacing.md),
        _SettingsGroup(
          children: [
            _SettingItem(
              title: '本轮完成通知',
              description: '显示工作区名称、标题和本轮摘要。',
              trailing: Switch(
                value: config.notificationsEnabled,
                onChanged: appState.setNotificationsEnabled,
              ),
            ),
            _SettingItem(
              title: '通知提示音',
              description: '通知出现时播放系统提示音。',
              trailing: Switch(
                value: config.notificationSound,
                onChanged: config.notificationsEnabled
                    ? appState.setNotificationSound
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetwork(BuildContext context) {
    final config = appState.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (appState.lastError != null) ...[
          AppNotice(
            tone: AppNoticeTone.danger,
            message: '服务未正常启动',
            detail: appState.lastErrorSummary,
            detailMaxLines: 2,
          ),
          const Gap(AppSpacing.xl),
        ],
        Builder(
          builder: (context) {
            final connection = _NetworkSection(
              title: '连接',
              description: config.domain.isEmpty
                  ? '所有工作区共用同一组连接参数。'
                  : 'https://${config.domain}/{uuid}/mcp',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppField(
                    label: '公网域名',
                    controller: _domainController,
                    placeholder: 'mcp.example.com',
                  ),
                  const Gap(AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: AppField(
                          label: '监听地址',
                          controller: _hostController,
                          placeholder: '127.0.0.1',
                        ),
                      ),
                      const Gap(AppSpacing.md),
                      Expanded(
                        child: AppField(
                          label: '端口',
                          controller: _portController,
                          placeholder: '18920',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            final tunnel = _NetworkSection(
              title: 'Cloudflare Tunnel',
              description: '应用启动时保持连接，为 ChatGPT 提供公网访问。',
              trailing: Switch(
                value: _useCloudflared,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _useCloudflared = value),
              ),
              child: _useCloudflared
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppField(
                          label: 'Tunnel 名称',
                          controller: _tunnelNameController,
                          placeholder: 'codex-mcp',
                        ),
                        const Gap(AppSpacing.lg),
                        _MetaRow(
                          label: 'Tunnel ID',
                          value: config.tunnelId ?? '未创建',
                        ),
                        const Gap(AppSpacing.sm),
                        _MetaRow(
                          label: 'Cloudflared',
                          value: config.cloudflaredBin ?? '使用内置下载路径',
                        ),
                        const Gap(AppSpacing.lg),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            Button(
                              style: ButtonStyle.outline(
                                size: ButtonSize.small,
                              ),
                              onPressed: _saving ? null : _createTunnel,
                              child: const AppButtonLabel(
                                icon: BootstrapIcons.cloudPlus,
                                label: '创建 / 修复',
                              ),
                            ),
                            Button(
                              style: ButtonStyle.outline(
                                size: ButtonSize.small,
                              ),
                              onPressed: _saving ? null : _verifyRoute,
                              child: const AppButtonLabel(
                                icon: BootstrapIcons.activity,
                                label: '验证连通性',
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Text(
                      '已关闭公网访问，MCP 仅监听本机地址。',
                      style: AppTones.muted(Theme.of(context), size: 11.5),
                    ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                connection,
                const Gap(AppSpacing.xl),
                _HorizontalRule(),
                const Gap(AppSpacing.xl),
                tunnel,
                if (_useCloudflared) ...[
                  const Gap(AppSpacing.xl),
                  _HorizontalRule(),
                  const Gap(AppSpacing.xl),
                  _buildTunnelLog(context),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTunnelLog(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupHeading(title: '运行日志', description: 'Cloudflared 最近的输出。'),
        const Gap(AppSpacing.md),
        ConsoleView(text: appState.tunnelService.logTail, maxHeight: 135),
      ],
    );
  }

  Future<void> _testNotification() async {
    final error = await appState.testNotification();
    if (!mounted) return;
    if (error == null) {
      AppToast.success(context, '测试通知已提交给系统');
    } else {
      AppToast.error(context, '发送通知失败：$error');
    }
  }

  Future<void> _saveAndRestart() async {
    setState(() => _saving = true);
    try {
      final tunnelName = _tunnelNameController.text.trim();
      await appState.saveGlobalConfig(
        appState.config.copyWith(
          domain: _setupService.normalizeDomain(_domainController.text),
          host: _hostController.text.trim().isEmpty
              ? '127.0.0.1'
              : _hostController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 18920,
          useCloudflared: _useCloudflared,
          tunnelName: tunnelName.isEmpty ? 'codex-mcp' : tunnelName,
        ),
      );
      await appState.restartServices();
      if (!mounted) return;
      if (appState.lastError == null) {
        AppToast.success(context, '公网配置已保存，服务已重启');
      } else {
        AppToast.error(context, '重启失败：${appState.lastErrorSummary}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createTunnel() async {
    setState(() => _saving = true);
    try {
      final bin = await _setupService.findCloudflaredBin();
      if (bin == null) throw Exception('未找到 cloudflared');
      final domain = _setupService.normalizeDomain(_domainController.text);
      if (domain.isEmpty) throw Exception('请先填写公网域名');
      final tunnelName = _tunnelNameController.text.trim().isEmpty
          ? 'codex-mcp'
          : _tunnelNameController.text.trim();
      final login = await _setupService.loginCloudflare(bin);
      if (!login.success) throw Exception(login.error ?? 'Cloudflare 登录未完成');
      final tunnelId = await _setupService.createTunnel(bin, tunnelName);
      await _setupService.routeDns(bin, tunnelName, domain);
      final updated = await _setupService.writeTunnelConfig(
        appState.config.copyWith(
          domain: domain,
          tunnelName: tunnelName,
          cloudflaredBin: bin,
          useCloudflared: true,
        ),
        tunnelId,
      );
      await appState.saveGlobalConfig(updated);
      _useCloudflared = true;
      await appState.restartServices();
      if (mounted) AppToast.success(context, 'Tunnel 已创建');
    } catch (error) {
      if (mounted) AppToast.error(context, '创建失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verifyRoute() async {
    setState(() => _saving = true);
    try {
      final domain = _setupService.normalizeDomain(_domainController.text);
      if (domain.isEmpty) throw Exception('请先填写公网域名');
      final reachable = await appState.tunnelService.verifyRoute(
        'https://$domain/healthz',
        attempts: 6,
      );
      if (!mounted) return;
      if (reachable) {
        AppToast.success(context, '公网地址可用');
      } else {
        AppToast.warning(context, '公网地址暂不可用，请检查 DNS 与隧道状态');
      }
    } catch (error) {
      if (mounted) AppToast.error(context, '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String description;
  final Widget? action;

  const _SectionHeader({
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTones.borderSubtle(theme))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTones.title(theme, size: 14)),
                const Gap(2),
                Text(description, style: AppTones.muted(theme, size: 11)),
              ],
            ),
          ),
          if (action != null) ...[const Gap(AppSpacing.lg), action!],
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.selected || _hovered;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.foreground.withValues(
                      alpha: widget.selected ? 0.085 : 0.045,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 13,
                  color: widget.selected
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.mutedForeground,
                ),
                const Gap(7),
                Text(
                  widget.label,
                  style: AppTones.body(theme, size: 11.5).copyWith(
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: widget.selected
                        ? theme.colorScheme.foreground
                        : theme.colorScheme.foreground.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  final String title;
  final String? description;

  const _GroupHeading({required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTones.title(theme, size: 13)),
        if (description != null) ...[
          const Gap(4),
          Text(description!, style: AppTones.muted(theme, size: 11.5)),
        ],
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        content.add(Container(height: 1, color: AppTones.borderSubtle(theme)));
      }
      content.add(children[index]);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: AppTones.borderSubtle(theme)),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: Column(children: content),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String title;
  final String description;
  final Widget trailing;

  const _SettingItem({
    required this.title,
    required this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTones.body(
                    theme,
                    size: 12.5,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const Gap(3),
                Text(description, style: AppTones.muted(theme, size: 11)),
              ],
            ),
          ),
          const Gap(AppSpacing.xl),
          trailing,
        ],
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;

  const _NetworkSection({
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTones.title(theme, size: 13)),
                  const Gap(4),
                  Text(
                    description,
                    style: AppTones.muted(theme, size: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const Gap(AppSpacing.md), trailing!],
          ],
        ),
        const Gap(AppSpacing.xl),
        child,
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: AppTones.muted(theme, size: 10.5)),
        ),
        Expanded(
          child: AppMonoText(
            value,
            size: 10.5,
            color: theme.colorScheme.foreground.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _HorizontalRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: AppTones.borderSubtle(Theme.of(context)),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final AppState appState;

  const _ThemeSelector({required this.appState});

  @override
  Widget build(BuildContext context) {
    final selected = appState.config.darkMode;
    return _SegmentedControl(
      items: const ['系统', '浅色', '深色'],
      selectedIndex: selected == null ? 0 : (selected ? 2 : 1),
      onChanged: (index) {
        switch (index) {
          case 0:
            appState.setThemeMode(null);
          case 1:
            appState.setThemeMode(false);
          case 2:
            appState.setThemeMode(true);
        }
      },
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedControl({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTones.surfaceSunken(theme),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(color: AppTones.borderSubtle(theme)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++)
            _SegmentedItem(
              label: items[index],
              selected: selectedIndex == index,
              onTap: () => onChanged(index),
            ),
        ],
      ),
    );
  }
}

class _SegmentedItem extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentedItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SegmentedItem> createState() => _SegmentedItemState();
}

class _SegmentedItemState extends State<_SegmentedItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.background
                : _hovered
                ? theme.colorScheme.foreground.withValues(alpha: 0.035)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.radiusSm),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: AppTones.body(theme, size: 11).copyWith(
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _CloseButton({required this.onPressed});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hovered
                ? theme.colorScheme.foreground.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.radiusMd),
          ),
          child: Icon(
            BootstrapIcons.x,
            size: 15,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}
