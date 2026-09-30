// 内置主题配色预设：设置页选择后全局生效。
import 'package:flutter/material.dart';

// 一套主题配色：key（持久化用）、名称、种子色
class AppTheme {
  final String key;
  final String label;
  final Color seed;

  const AppTheme(this.key, this.label, this.seed);
}

// 预设配色列表
const List<AppTheme> appThemes = [
  AppTheme('indigo', '靛蓝', Colors.indigo),
  AppTheme('blue', '天蓝', Colors.blue),
  AppTheme('teal', '青碧', Colors.teal),
  AppTheme('green', '森绿', Colors.green),
  AppTheme('orange', '暖橙', Colors.orange),
  AppTheme('pink', '樱粉', Colors.pink),
  AppTheme('purple', '葡紫', Colors.purple),
];

// 按 key 取配色，找不到时退回默认（第一套）
AppTheme themeByKey(String key) => appThemes.firstWhere(
      (t) => t.key == key,
      orElse: () => appThemes.first,
    );