// 主壳：底部导航 + PageView 滑动切换页面。
// 支持手势左右滑动和点击底部按钮平滑切换，页面状态保持不丢失。

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
      // PageView：左右滑动切换页面，带真实的滑动动画
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        // 点击底部按钮时平滑滑动到目标页
        onDestinationSelected: (i) {
          _controller.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
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