// 统计详情页：本月目标进度环、月度达标连续、累计打卡总览（可按计划查看）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/goal.dart';
import '../models/plan.dart';
import '../utils/icon_map.dart';

// ============ 本月目标（进度环） ============

// 每个计划一个圆形进度环 + 最近几个周期迷你条形
class GoalHistoryPage extends StatelessWidget {
  const GoalHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // 有周期目标的计划
    final items = <(Plan, Goal)>[];
    for (final p in appState.plans) {
      final g = appState.goalOf(p.id!);
      if (g != null && g.type == GoalType.frequency) {
        items.add((p, g));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('本月目标')),
      body: items.isEmpty
          ? const Center(child: Text('还没有设置周期目标'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final (p, g) in items)
                  _GoalRingCard(plan: p, goal: g),
              ],
            ),
    );
  }
}

// 单个计划的目标进度卡：进度环 + 达标徽章 + 迷你历史条形
class _GoalRingCard extends StatelessWidget {
  const _GoalRingCard({required this.plan, required this.goal});

  final Plan plan;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final color = Color(plan.color);
    final bodySmall = theme.textTheme.bodySmall;

    // 当前周期完成情况
    final done = appState.goalDoneCount(plan, goal);
    final target = goal.totalTimes;
    final met = done >= target;
    final progress = target <= 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    final remain = (target - done).clamp(0, target);
    final unit = goal.unitText;

    // 全部历史周期（旧 -> 新，用于可滑动条形）
    final history = appState
        .goalPeriodHistory(
            plan, goal, count: appState.goalPeriodCount(plan, goal))
        .reversed
        .toList();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 进度环
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withValues(alpha: 0.12),
                        color: color,
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$done',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: color),
                            ),
                            Text('/$target $unit', style: bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 计划信息 + 达标徽章
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text('每个周期至少 $target $unit',
                          style: bodySmall),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: met
                              ? Colors.green.withValues(alpha: 0.12)
                              : color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              met
                                  ? Icons.check_circle
                                  : Icons.timelapse,
                              size: 14,
                              color: met ? Colors.green : color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              met ? '已达标' : '还差 $remain $unit',
                              style: TextStyle(
                                fontSize: 12,
                                color: met ? Colors.green : color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 历史周期迷你条形（可左右滑动，默认定位到最新）
            _HistoryBars(
              history: history,
              target: target,
              color: color,
              period: goal.period,
            ),
          ],
        ),
      ),
    );
  }
}

// 可横向滑动的历史周期条形：旧 -> 新，默认定位到最新周期
class _HistoryBars extends StatefulWidget {
  const _HistoryBars({
    required this.history,
    required this.target,
    required this.color,
    required this.period,
  });

  final List<(DateTime, int)> history; // 旧 -> 新
  final int target;
  final Color color;
  final String? period;

  @override
  State<_HistoryBars> createState() => _HistoryBarsState();
}

class _HistoryBarsState extends State<_HistoryBars> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // 首帧后滚动到最右（最新周期）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients &&
          _controller.position.maxScrollExtent > 0) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });

    return SizedBox(
      height: 62,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (anchor, d) in widget.history)
              SizedBox(
                width: 30,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 18,
                      height: widget.target <= 0
                          ? 4
                          : ((d / widget.target) * 36).clamp(4.0, 36.0),
                      decoration: BoxDecoration(
                        color: d >= widget.target
                            ? widget.color
                            : widget.color.withValues(alpha: 0.25),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _shortLabel(widget.period, anchor),
                      style: TextStyle(fontSize: 10, color: outline),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 周期起始日 -> 短标签
  String _shortLabel(String? period, DateTime anchor) {
    switch (period) {
      case GoalPeriod.week:
        return '${anchor.month}/${anchor.day}';
      case GoalPeriod.year:
        return '${anchor.year}';
      default:
        return '${anchor.month}月';
    }
  }
}

// ============ 月度达标连续 ============

// 连续达成周期目标的统计
class StreakDetailPage extends StatelessWidget {
  const StreakDetailPage({super.key});

  // 周期单位词
  String _periodWord(String? period) {
    switch (period) {
      case GoalPeriod.week:
        return '周';
      case GoalPeriod.year:
        return '年';
      default:
        return '个月';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    // 有周期目标的计划
    final items = <(Plan, Goal)>[];
    for (final p in appState.plans) {
      final g = appState.goalOf(p.id!);
      if (g != null && g.type == GoalType.frequency) {
        items.add((p, g));
      }
    }
    final best = items.fold<int>(0, (m, e) {
      final s = appState.goalStreak(e.$1, e.$2);
      return s > m ? s : m;
    });
    // 没有设置周期目标的计划
    final noGoal = appState.plans.where((p) {
      final g = appState.goalOf(p.id!);
      return g == null || g.type != GoalType.frequency;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('达标连续')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 总览卡
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events,
                      color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          items.isEmpty
                              ? '0'
                              : '$best ${_periodWord(items.first.$2.period)}',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('全部计划中的最长达标连续',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 各计划明细
          for (final (p, g) in items)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Color(p.color).withValues(alpha: 0.15),
                  child:
                      Icon(iconForKey(p.icon), color: Color(p.color)),
                ),
                title: Text(p.name),
                subtitle: Text(
                    '当前连续 ${appState.goalStreak(p, g)} ${_periodWord(g.period)}'),
                trailing: Text(
                    '最长 ${appState.bestGoalStreak(p, g)} ${_periodWord(g.period)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          // 未设置目标的计划
          for (final p in noGoal)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Color(p.color).withValues(alpha: 0.15),
                  child:
                      Icon(iconForKey(p.icon), color: Color(p.color)),
                ),
                title: Text(p.name),
                subtitle: const Text('未设置周期目标'),
              ),
            ),
          if (appState.plans.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无计划'),
              ),
            ),
        ],
      ),
    );
  }
}

// ============ 累计打卡总览 ============

// 历史总数据：全部概览 + 点击某个计划查看该计划的数据
class TotalStatsPage extends StatefulWidget {
  const TotalStatsPage({super.key, this.planId});

  final int? planId; // 传入则直接展示该计划的数据

  @override
  State<TotalStatsPage> createState() => _TotalStatsPageState();
}

class _TotalStatsPageState extends State<TotalStatsPage> {
  late final int? _planFilter = widget.planId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allRecords = appState.records;

    // 空状态
    if (allRecords.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('历史数据')),
        body: const Center(child: Text('还没有打卡记录')),
      );
    }

    final theme = Theme.of(context);
    // 筛选当前查看的计划（null = 全部）
    final filtered = _planFilter == null
        ? allRecords
        : allRecords.where((r) => r.planId == _planFilter).toList();
    final filterName = _planFilter == null
        ? null
        : appState.plans
            .where((p) => p.id == _planFilter)
            .map((p) => p.name)
            .firstOrNull;

    final totalTimes = filtered.fold<int>(0, (s, r) => s + r.count);
    final totalDays = filtered.map((r) => r.date).toSet().length;
    final firstDate = filtered.isEmpty
        ? '—'
        : filtered
            .map((r) => r.date)
            .reduce((a, b) => a.compareTo(b) < 0 ? a : b);

    // 按月、按计划统计（'yyyy-MM' -> planId -> 次数），用于分色堆叠条
    final monthlyByPlan = <String, Map<int, int>>{};
    for (final r in filtered) {
      final key = r.date.substring(0, 7);
      final byPlan = monthlyByPlan.putIfAbsent(key, () => {});
      byPlan[r.planId] = (byPlan[r.planId] ?? 0) + r.count;
    }
    // 最新月份排在最上面
    final monthKeys = monthlyByPlan.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    // 计划颜色映射（已归档的计划用灰色兜底）
    final colorById = {
      for (final p in appState.plans) p.id!: Color(p.color),
    };

    return Scaffold(
      appBar: AppBar(title: Text(filterName ?? '累计打卡')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 总览卡
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _numColumn('$totalTimes', '总打卡次数'),
                  _numColumn('$totalDays', '打卡天数'),
                  _numColumn(firstDate, '开始日期'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 按计划统计（只在"全部"时显示；点击进入单个计划）
          if (_planFilter == null) ...[
            Text('按计划', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...appState.plans.map((p) {
              final color = Color(p.color);
              final times = appState.totalCount(p.id!);
              final dates = appState.recordDatesOf(p.id!).toList()..sort();
              final days = dates.length;
              final last = dates.isEmpty ? '' : dates.last;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(iconForKey(p.icon), color: color),
                  ),
                  title: Text(p.name),
                  subtitle: Text('$times 次 · $days 天'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(last, style: theme.textTheme.bodySmall),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 18, color: theme.colorScheme.outline),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => TotalStatsPage(planId: p.id)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          Text('按月统计', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // 每月次数（按计划分色的堆叠条，颜色见上方"按计划"列表）
          if (monthKeys.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('该计划还没有打卡记录')),
            )
          else
            for (final key in monthKeys)
              _monthRow(context, key, monthlyByPlan[key]!, colorById),
        ],
      ),
    );
  }

  // 单月统计行：月份 + 总次数 + 按计划分色的堆叠条
  Widget _monthRow(BuildContext context, String key, Map<int, int> byPlan,
      Map<int, Color> colorById) {
    final theme = Theme.of(context);
    final total = byPlan.values.fold(0, (a, b) => a + b);
    // 按 planId 排序保证颜色顺序稳定
    final segments = byPlan.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_monthLabel(key))),
              Text('$total 次', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  for (final seg in segments)
                    Expanded(
                      flex: seg.value,
                      child: Container(
                        color: colorById[seg.key] ??
                            const Color(0xFF9E9E9E),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 数字指标列
  static Widget _numColumn(String value, String label) {
    return Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  // 'yyyy-MM' -> 'yyyy年M月'
  static String _monthLabel(String key) {
    final parts = key.split('-');
    return '${parts[0]}年${int.parse(parts[1])}月';
  }
}