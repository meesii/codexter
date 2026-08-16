import 'package:shadcn_flutter/shadcn_flutter.dart';

/// 4px 栅格的间距令牌，全局统一
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double x2l = 28;
  static const double x3l = 40;

  static const double sidebarWidth = 236;
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 340;
  static const double windowTitleBarHeight = 32;
  static const double topBarHeight = 56;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(x2l, xl, x2l, x2l);
  static const EdgeInsets topBarPadding = EdgeInsets.symmetric(horizontal: x2l);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets tilePadding = EdgeInsets.symmetric(horizontal: md, vertical: md);
}
