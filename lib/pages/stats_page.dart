// 统计页：本周/本月完成率、最长连续打卡、累计打卡次数，
// 以及各计划完成次数对比柱状图（fl_chart）。

import 'package:flutter/material.dart' hide DateUtils;
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 对比图的统计周期：'week' / 'month'
  String _period = 'week';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final plans = appState.plans;
    final now = DateUtils.dateOnly(DateTime.now());

    // 各项指标
    final weekRate = appState.weekCompletionRate();
    final monthRate = appState.monthCompletionRate();
    final bestStreak = appState.maxStreak();
    final totalCheckIns = appState.records.length;

    // 选中周期内各计划的打卡次数
    final range = DateUtils.periodRange(_period, now);
    final counts = [
      for (final p in plans) appState.countInRange(p, range.$1, range.$2)
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('统计'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 完成率指标卡
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: '本周完成率',
                  value: '${(weekRate * 100).round()}%',
                  progress: weekRate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: '本月完成率',
                  value: '${(monthRate * 100).round()}%',
                  progress: monthRate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 连续天数 / 累计次数
          Row(
            children: [
              Expanded(
                child: _StatTile(label: '最长连续打卡', value: '$bestStreak 天'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: '累计打卡', value: '$totalCheckIns 次'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 对比图标题 + 周期切换
          Row(
            children: [
              Text('各计划完成对比',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              ChoiceChip(
                label: const Text('本周'),
                selected: _period == 'week',
                onSelected: (_) => setState(() => _period = 'week'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('本月'),
                selected: _period == 'month',
                onSelected: (_) => setState(() => _period = 'month'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 柱状图
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: plans.isEmpty
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: Text('暂无计划')),
                    )
                  : _buildBarChart(context, plans, counts),
            ),
          ),
        ],
      ),
    );
  }

  // 各计划完成次数对比柱状图；柱子颜色随计划颜色
  Widget _buildBarChart(BuildContext context, List<Plan> plans,
      List<int> counts) {
    final maxCount = counts.fold(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount <= 3 ? 4 : maxCount + 1).toDouble();
    // 纵轴刻度间隔：数量少时按 1 递增，多时按 1/4 量程取整
    final yInterval = maxY <= 8 ? 1.0 : (maxY / 4).ceilToDouble();
    // 计划较多时图表加宽并支持横向滚动
    final screenWidth = MediaQuery.of(context).size.width;
    final chartWidth =
        plans.length <= 4 ? screenWidth - 64 : plans.length * 72.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: chartWidth,
        height: 240,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barGroups: [
              for (var i = 0; i < plans.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: counts[i].toDouble(),
                      color: Color(plans[i].color),
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ],
                ),
            ],
            titlesData: FlTitlesData(
              topTitles: AxisTitles(),
              rightTitles: AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: yInterval,
                  getTitlesWidget: (v, meta) => Text(
                    v.toInt().toString(),
                    style:
                        const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= plans.length) {
                      return const SizedBox.shrink();
                    }
                    // 计划名超长时截断
                    final name = plans[idx].name;
                    final label = name.length <= 3
                        ? name
                        : '${name.substring(0, 2)}…';
                    return SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(label,
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

// 指标卡：标签 + 大数字，可选进度条
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.progress});

  final String label;
  final String value;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}