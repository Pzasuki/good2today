// 入口：初始化 Provider，配置 Material 3 主题（支持深色模式）。

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'db/app_state.dart';
import 'pages/home_shell.dart';

void main() {
  // 加载中文日期符号，供日历标题/星期以中文显示
  initializeDateFormatting('zh_CN');
  runApp(
    // ChangeNotifierProvider 向全 App 提供 AppState
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const DailyLogApp(),
    ),
  );
}

class DailyLogApp extends StatelessWidget {
  const DailyLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听 AppState：切换主题颜色时重建 MaterialApp
    return Consumer<AppState>(
      builder: (context, appState, _) {
        // Material 3 动态取色：根据所选主题种子色生成整套配色
        return MaterialApp(
          title: '打卡记录',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: appState.themeSeed),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: appState.themeSeed,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: ThemeMode.system,
          home: const HomeShell(),
        );
      },
    );
  }
}