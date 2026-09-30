// 计划管理页：查看所有计划，点击进入编辑，可删除（软删除/归档）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/plan.dart';
import '../utils/icon_map.dart';
import 'plan_edit_page.dart';

class PlanManagePage extends StatelessWidget {
  const PlanManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final plans = appState.plans;

    return Scaffold(
      appBar: AppBar(title: const Text('管理计划')),
      body: plans.isEmpty
          ? const Center(child: Text('还没有计划，去首页添加一个吧'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: plans.length,
              itemBuilder: (context, i) {
                final plan = plans[i];
                final color = Color(plan.color);
                final summary = appState
                    .goalSummary(plan, appState.goalOf(plan.id!));
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(iconForKey(plan.icon), color: color),
                    ),
                    title: Text(plan.name),
                    subtitle: Text(summary == null
                        ? plan.repeatDescription()
                        : '${plan.repeatDescription()} · $summary'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => PlanEditPage(plan: plan)),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除',
                      onPressed: () =>
                          _confirmDelete(context, appState, plan),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // 删除确认对话框（软删除，历史记录保留）
  Future<void> _confirmDelete(
      BuildContext context, AppState appState, Plan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${plan.name}」？'),
        content: const Text('计划将不再显示，历史打卡记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await appState.archivePlan(plan.id!);
    }
  }
}