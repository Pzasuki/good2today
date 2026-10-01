// 首页：显示今天需要打卡的计划，点击即可打卡/取消。
// 卡片支持长按编辑、左滑删除。

import 'package:flutter/material.dart' hide DateUtils;
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';
import '../widgets/habit_card.dart';
import 'plan_edit_page.dart';
import 'plan_manage_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final today = DateUtils.today();

    // 今天需要打卡的计划（按重复规则过滤）
    final todayPlans = appState.plans
        .where((p) => p.shouldCheckIn(DateTime.now()))
        .toList();

    // 今日完成统计
    final doneCount =
        todayPlans.where((p) => appState.hasRecord(p.id!, today)).length;
    final totalCount = todayPlans.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日打卡'),
        centerTitle: true,
        actions: [
          // 计划管理入口
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '管理计划',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlanManagePage()),
            ),
          ),
        ],
      ),
      body: ListView(
        // 底部留白避开浮动玻璃导航栏
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // 顶部：日期 + 完成率
          _Header(today: today, doneCount: doneCount, totalCount: totalCount),
          const SizedBox(height: 12),
          if (todayPlans.isEmpty)
            const _EmptyHint()
          else
            ...todayPlans.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SwipablePlanCard(plan: p),
                )),
        ],
      ),
      // 添加计划入口：跳转到完整的计划编辑页（垫高避开玻璃导航栏）
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlanEditPage()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('添加计划'),
        ),
      ),
    );
  }
}

// 首页打卡卡片包装：长按进入编辑，左滑删除计划（带确认）
class _SwipablePlanCard extends StatelessWidget {
  const _SwipablePlanCard({required this.plan});

  final Plan plan;

  // 删除确认对话框
  Future<bool> _confirmDelete(BuildContext context) async {
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
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Dismissible(
      key: ValueKey('plan-${plan.id}'),
      direction: DismissDirection.endToStart, // 只响应左滑
      // 松手后先弹确认，同意才真正删除
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => appState.archivePlan(plan.id!),
      // 左滑露出的红色删除背景
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: GestureDetector(
        // 长按进入编辑页
        onLongPress: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlanEditPage(plan: plan)),
        ),
        child: HabitCard(plan: plan),
      ),
    );
  }
}

// 顶部统计区：日期 + 今日完成 x/y
class _Header extends StatelessWidget {
  const _Header({
    required this.today,
    required this.doneCount,
    required this.totalCount,
  });

  final String today;
  final int doneCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    today,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '完成 $doneCount / $totalCount',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            // 今日完成圆环
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: totalCount == 0
                        ? 0
                        : (doneCount / totalCount).clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.surface,
                    color: theme.colorScheme.primary,
                  ),
                  Center(
                    child: Text(
                      totalCount == 0
                          ? '0%'
                          : '${(doneCount * 100 / totalCount).round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 空状态提示
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.event_available,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            '今天没有需要打卡的计划',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}