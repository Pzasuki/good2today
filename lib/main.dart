// 入口：初始化 Provider，配置 Material 3 主题（支持深色模式）。

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'db/app_state.dart';
import 'pages/home_shell.dart';
import 'utils/app_themes.dart';

// 主题缓存：按 (主题key, 亮度) 缓存 ThemeData。
// ColorScheme.fromSeed 计算量不小，缓存后打卡等数据变化
// 不会反复触发 MaterialApp 重建整套配色。
final Map<(String, Brightness), ThemeData> _themeCache = {};

ThemeData _themeFor(String key, Brightness brightness) {
  return _themeCache.putIfAbsent((key, brightness), () {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: themeByKey(key).seed,
        brightness: brightness,
      ),
    );
  });
}

Future<void> main() async {
  // 加载中文日期符号，供日历标题/星期以中文显示。
  // 等加载完成再启动 UI，避免 TableCalendar 用 zh_CN 格式化时符号尚未就绪
  await initializeDateFormatting('zh_CN');
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
    // 只监听主题 key：打卡等数据变化不再触发 MaterialApp 重建
    final themeKey = context.select<AppState, String>((a) => a.themeKey);
    return MaterialApp(
      title: '打卡记录',
      debugShowCheckedModeBanner: false,
      theme: _themeFor(themeKey, Brightness.light),
      darkTheme: _themeFor(themeKey, Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}