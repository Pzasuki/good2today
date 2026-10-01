// 设置页：主题颜色切换、数据导入导出、关于 App。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../utils/app_themes.dart';
import 'export_import_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final current = appState.themeKey;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        // 底部留白避开浮动玻璃导航栏
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // 主题颜色选择
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题颜色',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('选一套舒服的配色，点击立即全局生效',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (final t in appThemes)
                        GestureDetector(
                          onTap: () => appState.setThemeKey(t.key),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: t.seed,
                                  shape: BoxShape.circle,
                                  border: current == t.key
                                      ? Border.all(
                                          width: 3,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline)
                                      : null,
                                ),
                                child: current == t.key
                                    ? const Icon(Icons.check,
                                        color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Text(t.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 数据导入导出入口
          ListTile(
            leading: const Icon(Icons.import_export),
            title: const Text('导入 / 导出数据'),
            subtitle: const Text('备份为 JSON 文件，或从备份恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExportImportPage()),
            ),
          ),
          const Divider(),
          // 关于
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于打卡记录'),
            subtitle: const Text('功能介绍'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  // 关于弹窗：介绍 App 的主要功能
  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于打卡记录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('版本 1.0.0 · 纯本地应用，数据仅存于手机，无需账号'),
              const SizedBox(height: 14),
              _aboutRow(Icons.today, '今日打卡',
                  '点卡片即可打卡，长按编辑，左滑删除；显示连续天数与目标进度'),
              _aboutRow(Icons.flag, '计划与目标',
                  '每天 / 每周固定几天 / 不固定打卡；周期目标（每周、每月、每年至少 N）或总量目标；按天或按次计，可开启一天多次'),
              _aboutRow(Icons.calendar_month, '日历',
                  '月视图查看每天的打卡圆点，任意日期补打卡，支持写备注'),
              _aboutRow(Icons.bar_chart, '统计',
                  '本周/本月完成率、历史最长连续天数、各计划完成次数对比图'),
              _aboutRow(Icons.import_export, '数据备份',
                  '导出 JSON 备份分享保存，支持合并 / 覆盖导入恢复'),
              _aboutRow(Icons.dark_mode, '外观',
                  'Material 3 设计，多套主题配色，深色模式跟随系统'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // 功能介绍的一行：图标 + 标题 + 描述
  static Widget _aboutRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(desc,
                    style:
                        const TextStyle(fontSize: 12, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}