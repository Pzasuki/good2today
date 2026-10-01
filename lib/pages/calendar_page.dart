// 日历页：月视图查看每天的打卡情况，可补打卡、添加备注。
// 点某天 → 下方列出该天相关计划；点行打卡/取消（过去的日子即补打卡）；
// 点备注图标写备注。

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' hide DateUtils;
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../db/app_state.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';
import '../utils/icon_map.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // 当前聚焦的月份与选中的日期（均为本地日期的 0 点）
  DateTime _focusedDay = DateUtils.dateOnly(DateTime.now());
  DateTime? _selectedDay = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final selected = _selectedDay ?? _focusedDay;
    final selKey = DateUtils.toKey(selected);

    // 该天相关计划：当天该打卡的，或当天已有记录的（如补打卡过的）
    final dayPlans = appState.plans
        .where((p) =>
            p.shouldCheckIn(selected) || appState.hasRecord(p.id!, selKey))
        .toList();
    final doneCount =
        dayPlans.where((p) => appState.hasRecord(p.id!, selKey)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        centerTitle: true,
        actions: [
          // 回到今天
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '回到今天',
            onPressed: () {
              final now = DateUtils.dateOnly(DateTime.now());
              setState(() {
                _focusedDay = now;
                _selectedDay = now;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 月历：有打卡的日子用计划颜色饼图填充整个圆形
          TableCalendar(
            firstDay: DateTime(2020, 1, 1),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _focusedDay,
            locale: 'zh_CN',
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, focused) => setState(() {
              _selectedDay = sel;
              _focusedDay = focused;
            }),
            onPageChanged: (focused) => _focusedDay = focused,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) =>
                  _dayCell(context, appState, day, focusedDay),
            ),
          ),
          const Divider(height: 1),
          // 选中日期 + 完成统计
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${selected.month}月${selected.day}日',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '完成 $doneCount / ${dayPlans.length}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // 该天的计划打卡明细
          Expanded(
            child: dayPlans.isEmpty
                ? Center(
                    child: Text(
                      '这一天没有可打卡的计划',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: dayPlans.length,
                    itemBuilder: (context, i) {
                      final plan = dayPlans[i];
                      final record = appState.recordOf(plan.id!, selKey);
                      final count = record?.count ?? 0;
                      final done = count > 0;
                      final noteText = record?.note;
                      final hasNote =
                          noteText != null && noteText.isNotEmpty;
                      final color = Color(plan.color);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Icon(iconForKey(plan.icon), color: color),
                        ),
                        title: Text(plan.name),
                        subtitle: hasNote ? Text('备注：$noteText') : null,
                        // 点整行 = 打卡（多次计划次数 +1，普通计划切换；
                        // 过去的日子即补打卡）
                        onTap: () => appState.tapCheckIn(plan, selKey),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 备注入口
                            IconButton(
                              icon: Icon(
                                hasNote
                                    ? Icons.sticky_note_2
                                    : Icons.sticky_note_2_outlined,
                                size: 20,
                              ),
                              tooltip: '备注',
                              onPressed: () => _editNote(
                                  context, appState, plan, selKey),
                            ),
                            // 每天可多次的计划：减一次按钮
                            if (plan.multiPerDay && count > 0) ...[
                              GestureDetector(
                                onTap: () => appState
                                    .removeOneCheckIn(plan, selKey),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(Icons.remove,
                                      size: 16, color: Colors.grey),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            // 打卡状态圈（多次计划内显示当日次数）
                            GestureDetector(
                              onTap: () =>
                                  appState.tapCheckIn(plan, selKey),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: done ? color : Colors.transparent,
                                  border: Border.all(
                                    color: done
                                        ? color
                                        : Colors.grey.shade400,
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
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        : const Icon(Icons.check,
                                            color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 备注编辑对话框
  Future<void> _editNote(BuildContext context, AppState appState,
      Plan plan, String dateKey) async {
    final existing = appState.recordOf(plan.id!, dateKey);
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: existing?.note),
    );
    if (note == null) return; // 取消
    if (!mounted) return;
    await appState.setNote(plan.id!, dateKey, note);
  }

  // 单个日期格子：有打卡 → 计划颜色饼图填充圆形；无打卡 → 默认样式
  Widget _dayCell(BuildContext context, AppState appState, DateTime day,
      DateTime focusedDay) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = isSameDay(_selectedDay, day);
    final isToday = isSameDay(DateTime.now(), day);

    // 当天打卡的计划颜色（同一计划多次去重，多计划平分圆）
    final colors = <Color>[];
    for (final r in appState.recordsOn(DateUtils.toKey(day))) {
      final p = appState.planById(r.planId);
      final c = p == null ? const Color(0xFF9E9E9E) : Color(p.color);
      if (!colors.contains(c)) colors.add(c);
    }
    final hasRecords = colors.isNotEmpty;

    // 数字颜色：饼图上用白色；选中/今天用主色
    final textColor = hasRecords
        ? Colors.white
        : isSelected
            ? scheme.onPrimary
            : isToday
                ? scheme.primary
                : null;

    return Center(
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 选中/今天的外圈
            if (isSelected)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              )
            else if (isToday)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: scheme.primary, width: 1.2),
                ),
              ),
            // 填充层：颜色饼图 / 选中的实心圆
            if (hasRecords)
              SizedBox(
                width: 36,
                height: 36,
                child: CustomPaint(painter: _PiePainter(colors)),
              )
            else if (isSelected)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: hasRecords || isToday
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 日期格子的颜色饼图：多个计划时把圆形平分成几瓣
class _PiePainter extends CustomPainter {
  _PiePainter(this.colors);

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    // 单个颜色直接画整圆
    if (colors.length == 1) {
      paint.color = colors.first;
      canvas.drawCircle(rect.center, size.width / 2, paint);
      return;
    }
    // 多个颜色：从正上方开始平分扇形
    final sweep = 2 * math.pi / colors.length;
    var start = -math.pi / 2;
    for (final c in colors) {
      paint.color = c;
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter oldDelegate) =>
      !listEquals(oldDelegate.colors, colors);
}

// 备注输入对话框：控制器由本组件自己管理，随组件销毁释放
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({this.initial});

  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('备注'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: '记录一下这一天的情况…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // 返回 null = 取消
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}