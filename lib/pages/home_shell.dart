// 主壳：玻璃质感浮动底部导航栏 + PageView 滑动切换页面。
// 支持手势左右滑动和点击底部按钮平滑切换，页面状态保持不丢失。

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'today_page.dart';
import 'calendar_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final PageController _controller = PageController(initialPage: 0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 页面内容延伸到底部导航栏后面，毛玻璃才有内容可以模糊
      extendBody: true,
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          KeepAliveWrapper(child: TodayPage()),
          KeepAliveWrapper(child: CalendarPage()),
          KeepAliveWrapper(child: StatsPage()),
          KeepAliveWrapper(child: SettingsPage()),
        ],
      ),
      bottomNavigationBar: _GlassNavBar(
        index: _index,
        onSelected: (i) {
          _controller.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
      ),
    );
  }
}

// 玻璃质感浮动导航栏：圆角胶囊 + 毛玻璃模糊 + 半透明底色
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: NavigationBar(
            height: 64,
            elevation: 0,
            backgroundColor: scheme.surface.withValues(alpha: 0.70),
            surfaceTintColor: Colors.transparent,
            indicatorColor: scheme.primary.withValues(alpha: 0.25),
            selectedIndex: index,
            onDestinationSelected: onSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: '今日',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: '日历',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: '统计',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 包一层 KeepAlive：PageView 切换时不销毁页面，滚动位置等状态得以保留
class KeepAliveWrapper extends StatefulWidget {
  const KeepAliveWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}