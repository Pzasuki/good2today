// 打卡卡片：首页展示单个计划，点击即可打卡/取消。
// 开启"每天可多次"的计划：点按 = 次数 +1，圆圈内显示当日次数，
// 旁边出现 − 按钮可减一次。

import 'package:flutter/material.dart' hide DateUtils;
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';
import '../utils/icon_map.dart';
import 'progress_bar.dart';

class HabitCard extends StatelessWidget {
  const HabitCard({super.key, required this.plan});

  final Plan plan;

  // 重复规则 + 提醒时间的展示文字
  String _repeatText() {
    var base = plan.repeatDescription();
    if (plan.reminderHour != null) {
      final hh = plan.reminderHour.toString().padLeft(2, '0');
      final mm = (plan.reminderMinute ?? 0).toString().padLeft(2, '0');
      base += ' · 提醒 $hh:$mm';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final today = DateUtils.today();

    // 当日打卡次数（普通计划只有 0 或 1）
    final count = appState.checkCount(plan.id!, today);
    final done = count > 0;

    // 目标进度与展示文案
    final goal = appState.goalOf(plan.id!);
    final progress = appState.goalProgress(plan, goal);
    final summary = appState.goalSummary(plan, goal);

    final streak = appState.streakDays(plan);

    // 计划的主题色
    final color = Color(plan.color);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => appState.tapCheckIn(plan, today),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 左侧：彩色图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconForKey(plan.icon), color: color),
              ),
              const SizedBox(width: 12),
              // 中间：名称 + 重复规则 + 目标进度/连续天数
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.repeat,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _repeatText(),
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (summary != null && progress != null) ...[
                      ProgressBar(progress: progress, color: color),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else
                      Text(
                        '连续 $streak 天',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 减一次按钮（每天可多次且当天已打卡时显示）
              if (plan.multiPerDay && count > 0) ...[
                GestureDetector(
                  onTap: () => appState.removeOneCheckIn(plan, today),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.remove,
                        size: 18, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // 打卡状态圈（多次计划内显示当日次数）
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? color : Colors.transparent,
                  border: Border.all(
                    color: done ? color : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: !done
                    ? null
                    : plan.multiPerDay
                        ? Center(
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const Icon(Icons.check,
                            color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}