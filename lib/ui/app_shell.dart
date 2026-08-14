import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../stores/app_state.dart';
import 'pages/doctor_page.dart';
import 'pages/home_page.dart';
import 'pages/mcp_manage_page.dart';
import 'pages/skills_page.dart';
import 'pages/workspace_detail_page.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_spacing.dart';
import 'widgets/create_workspace_dialog.dart';

/// 侧边栏 + 内容区的主框架
class AppShell extends StatefulWidget {
  final AppState appState;

  const AppShell({super.key, required this.appState});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late double _sidebarWidth;

  AppState get appState => widget.appState;

  @override
  void initState() {
    super.initState();
    _sidebarWidth = appState.config.sidebarWidth.clamp(
      AppSpacing.sidebarMinWidth,
      AppSpacing.sidebarMaxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, child) {
          return Row(
            children: [
              SizedBox(
                width: _sidebarWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppSidebar(
                        appState: appState,
                        onCreateWorkspace: () =>
                            CreateWorkspaceDialog.show(context, appState),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _sidebarWidth = (_sidebarWidth + details.delta.dx)
                                  .clamp(
                                    AppSpacing.sidebarMinWidth,
                                    AppSpacing.sidebarMaxWidth,
                                  );
                            });
                          },
                          onHorizontalDragEnd: (_) {
                            appState.setSidebarWidth(_sidebarWidth);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildContent()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (appState.selectedWorkspace != null) {
      return WorkspaceDetailPage(appState: appState);
    }
    return switch (appState.currentPage) {
      AppPage.home => HomePage(appState: appState),
      AppPage.skills => SkillsPage(appState: appState),
      AppPage.mcpManage => McpManagePage(appState: appState),
      AppPage.doctor => DoctorPage(appState: appState),
    };
  }
}
