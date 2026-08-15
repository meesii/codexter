import 'package:shadcn_flutter/shadcn_flutter.dart';

/// shadcn 风格主题：界面字体优先使用各平台 CJK UI 字体，代码区域保留 Geist Mono。
///
/// 注意：TextStyle 的 package 参数会同时作用于 fontFamilyFallback，导致系统字体名
/// 被改写成 `packages/<package>/<font>`。因此这里不在带系统 fallback 的样式上使用 package。
class AppTheme {
  const AppTheme._();

  static const _cjkSans = <String>[
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
  ];

  static const _monoFallback = <String>[
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Menlo',
    'Noto Sans Mono CJK SC',
    'Microsoft YaHei UI',
  ];

  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorSchemes.lightNeutral,
      radius: 0.6,
      typography: _typography,
    );
  }

  static ThemeData get dark {
    return ThemeData.dark(
      colorScheme: ColorSchemes.darkNeutral,
      radius: 0.6,
      typography: _typography,
    );
  }

  static Typography get _typography {
    return const Typography.geist().copyWith(
      // UI 以简体中文系统界面字体为首选。Microsoft YaHei UI 同时覆盖 Latin，
      // 可以避免中文 fallback 与 Geist 混排时字面高度、基线和字重观感不一致。
      sans: () => const TextStyle(
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: _cjkSans,
      ),
      // 包内字体手动写完整 family 路径，避免 package 参数把系统 fallback 也加前缀。
      mono: () => const TextStyle(
        fontFamily: 'packages/shadcn_flutter/GeistMono',
        fontFamilyFallback: _monoFallback,
      ),
    );
  }
}

/// 全局 Switch 视觉：开启使用 primary 轨道，关闭使用 input 轨道；
/// 滑块在明暗主题下都保持与轨道足够的明度反差。
class AppSwitchTheme extends StatelessWidget {
  final Widget child;

  const AppSwitchTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.colorScheme.brightness == Brightness.dark;

    return ComponentTheme<SwitchTheme>(
      data: SwitchTheme(
        activeColor: theme.colorScheme.primary,
        inactiveColor: theme.colorScheme.input,
        activeThumbColor: theme.colorScheme.primaryForeground,
        inactiveThumbColor: dark
            ? theme.colorScheme.foreground
            : theme.colorScheme.background,
      ),
      child: child,
    );
  }
}

/// 语义色与排版令牌，避免各页面各写一套硬编码颜色
class AppTones {
  const AppTones._();

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const info = Color(0xFF2563EB);

  /// 交互强调色与状态色分离：绿色只表达成功/运行，蓝色表达选中与可交互。
  static Color interaction(ThemeData theme) {
    return theme.colorScheme.brightness == Brightness.dark
        ? const Color(0xFF60A5FA)
        : info;
  }

  static Color interactionSurface(ThemeData theme) {
    final alpha = theme.colorScheme.brightness == Brightness.dark ? 0.12 : 0.07;
    return interaction(theme).withValues(alpha: alpha);
  }

  /// 日志耗时使用独立的蓝灰色，和普通 muted 文本拉开层级。
  static Color metricText(ThemeData theme) {
    return theme.colorScheme.brightness == Brightness.dark
        ? const Color(0xFF86A6D7)
        : const Color(0xFF4F6FA5);
  }

  static Color surfaceRaised(ThemeData theme) {
    return theme.colorScheme.brightness == Brightness.dark
        ? const Color(0xFF141414)
        : const Color(0xFFFCFCFC);
  }

  static Color surfaceSunken(ThemeData theme) {
    return theme.colorScheme.brightness == Brightness.dark
        ? const Color(0xFF0F0F0F)
        : const Color(0xFFF7F7F8);
  }

  static Color borderSubtle(ThemeData theme) {
    final alpha = theme.colorScheme.brightness == Brightness.dark ? 0.68 : 0.44;
    return theme.colorScheme.border.withValues(alpha: alpha);
  }

  static Color borderFaint(ThemeData theme) {
    final alpha = theme.colorScheme.brightness == Brightness.dark ? 0.52 : 0.30;
    return theme.colorScheme.border.withValues(alpha: alpha);
  }

  static Color logCardBorder(ThemeData theme) {
    final alpha = theme.colorScheme.brightness == Brightness.dark ? 0.60 : 0.38;
    return theme.colorScheme.border.withValues(alpha: alpha);
  }

  static Color serviceCardSurface(ThemeData theme) {
    return theme.colorScheme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFFBFBFC);
  }

  static TextStyle mono(
    ThemeData theme, {
    double size = 12,
    Color? color,
    FontWeight? weight,
  }) {
    return theme.typography.mono.copyWith(
      fontSize: size,
      height: 1.5,
      color: color ?? theme.colorScheme.mutedForeground,
      fontWeight: weight,
    );
  }

  static TextStyle title(ThemeData theme, {double size = 15}) {
    return theme.typography.sans.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.foreground,
      height: 1.3,
    );
  }

  static TextStyle body(ThemeData theme, {double size = 13, Color? color}) {
    return theme.typography.sans.copyWith(
      fontSize: size,
      color: color ?? theme.colorScheme.foreground,
      height: 1.5,
    );
  }

  static TextStyle muted(ThemeData theme, {double size = 12}) {
    return theme.typography.sans.copyWith(
      fontSize: size,
      color: theme.colorScheme.mutedForeground,
      height: 1.5,
    );
  }

  static TextStyle label(ThemeData theme) {
    return theme.typography.sans.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.foreground,
    );
  }
}
