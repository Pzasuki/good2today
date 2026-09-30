// 图标映射：计划只存图标 key（字符串），用此表映射到 Material 图标。
// 这样导出的 JSON/数据库更干净，避免直接存 IconData。
import 'package:flutter/material.dart';

// icons key -> IconData 的映射表
const Map<String, IconData> iconMap = {
  'flag': Icons.flag,
  'fitness': Icons.fitness_center,
  'book': Icons.menu_book,
  'water': Icons.water_drop,
  'run': Icons.directions_run,
  'sleep': Icons.bedtime,
  'work': Icons.work,
  'music': Icons.music_note,
  'code': Icons.code,
  'language': Icons.translate,
  'leaf': Icons.eco,
  'heart': Icons.favorite,
};

// 默认图标 key，供新增计划时使用
const String defaultIconKey = 'flag';

// 根据 key 取 IconData，找不到时退回默认图标
IconData iconForKey(String? key) => iconMap[key] ?? Icons.flag;