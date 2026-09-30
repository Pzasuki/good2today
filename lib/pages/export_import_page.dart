// 导入导出页：把数据备份为 JSON 文件分享出去，或从 JSON 备份恢复。
// 导入前可选「覆盖」（清空后恢复）或「合并」（保留现有、跳过重复）。

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/app_state.dart';

class ExportImportPage extends StatefulWidget {
  const ExportImportPage({super.key});

  @override
  State<ExportImportPage> createState() => _ExportImportPageState();
}

class _ExportImportPageState extends State<ExportImportPage> {
  bool _busy = false; // 导入/导出进行中，防止重复点击

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 两位数字补零，用于文件名时间戳
  String _p2(int n) => n.toString().padLeft(2, '0');

  // 导出：生成 JSON → 写临时文件 → 拉起系统分享
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final appState = context.read<AppState>();
      final json = await appState.exportToJson();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}_${_p2(now.hour)}${_p2(now.minute)}';
      final file = File('${dir.path}/daily_log_backup_$stamp.json');
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '打卡记录备份'),
      );
    } catch (e) {
      if (mounted) _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 导入：选文件 → 预览 → 选择覆盖/合并 → 确认执行
  Future<void> _import() async {
    // file_picker 13.x：静态方法，取消时返回空列表
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return; // 用户取消选择
    if (!mounted) return;

    // 读取文件内容
    String raw;
    try {
      raw = await File(path).readAsString();
    } catch (e) {
      _toast('无法读取文件：$e');
      return;
    }

    // 解析预览信息
    var nPlans = 0, nGoals = 0, nRecords = 0;
    String? exportedAt;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      nPlans = (data['plans'] as List?)?.length ?? 0;
      nGoals = (data['goals'] as List?)?.length ?? 0;
      nRecords = (data['records'] as List?)?.length ?? 0;
      exportedAt = data['exportedAt'] as String?;
    } catch (_) {
      _toast('不是有效的打卡备份文件');
      return;
    }
    if (!mounted) return;

    // 选择导入方式
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择导入方式'),
        content: Text(
          '备份包含：计划 $nPlans 个、目标 $nGoals 个、'
          '记录 $nRecords 条'
          '${exportedAt == null ? '' : '\n导出时间：$exportedAt'}\n\n'
          '覆盖导入：清空现有数据，完全恢复为备份内容（适合换机/恢复）\n\n'
          '合并导入：保留现有数据，补充备份中的数据（重复的自动跳过）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('合并导入'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'overwrite'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    // 覆盖是危险操作，再确认一次
    if (mode == 'overwrite') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖？'),
          content: const Text('现有全部数据将被清空并替换为备份内容，此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确认覆盖'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }

    // 执行导入
    setState(() => _busy = true);
    try {
      final appState = context.read<AppState>();
      final summary =
          await appState.importFromJson(raw, merge: mode == 'merge');
      if (!mounted) return;
      _toast('导入完成：$summary');
    } catch (e) {
      if (mounted) _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入导出')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 导出卡片
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_upload_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('导出备份',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '把全部数据（含已删除的计划）导出为 JSON 文件，'
                    '通过系统分享保存到微信、网盘或本机文件。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('导出并分享'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 导入卡片
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_download_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('导入恢复',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择之前导出的 JSON 备份文件恢复数据。'
                    '可选择覆盖（清空后恢复）或合并（保留现有、跳过重复）。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件导入'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}