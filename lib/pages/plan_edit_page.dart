// 计划编辑页：新增/编辑计划。
// 表单按「基本信息 / 打卡安排 / 打卡目标」三组卡片排版。
// 颜色支持预设色板 + 自定义调色（HSV 滑块）。
// 校验提示为居中浮动气泡，1.5 秒自动消失，不阻挡操作。

import 'dart:async';

import 'package:flutter/material.dart' hide DateUtils;
import 'package:provider/provider.dart';

import '../db/app_state.dart';
import '../models/goal.dart';
import '../models/plan.dart';
import '../utils/date_utils.dart';
import '../utils/icon_map.dart';

// 预设可选颜色（按色环顺序排列）
const List<Color> presetColors = [
  Colors.red,
  Colors.orange,
  Colors.amber,
  Colors.green,
  Colors.teal,
  Colors.blue,
  Colors.indigo,
  Colors.purple,
  Colors.pink,
  Colors.brown,
];

class PlanEditPage extends StatefulWidget {
  const PlanEditPage({super.key, this.plan});

  final Plan? plan; // 传入则为编辑，不传为新增

  @override
  State<PlanEditPage> createState() => _PlanEditPageState();
}

class _PlanEditPageState extends State<PlanEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _timesController;

  late int _color; // 当前选中的颜色 ARGB
  late String _icon; // 当前选中的图标 key
  late String _repeatType; // daily / weekly / flex
  late Set<int> _days; // 每周固定哪几天
  TimeOfDay? _reminder; // 提醒时间（仅记录）
  String _goalMode = 'none'; // none / frequency / total
  String _goalPeriod = GoalPeriod.month; // 周期目标的周期
  String _goalUnit = GoalUnit.day; // 计数单位：天 / 次
  bool _multiPerDay = false; // 每天是否可打卡多次
  String? _deadline; // 总量目标的截止日期

  OverlayEntry? _toastEntry; // 当前显示的浮动提示

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    // 编辑模式下读出已有目标和计划信息做预填
    final goal =
        plan == null ? null : context.read<AppState>().goalOf(plan.id!);

    _nameController = TextEditingController(text: plan?.name ?? '');
    _timesController =
        TextEditingController(text: goal == null ? '' : '${goal.totalTimes}');
    _color = plan?.color ?? presetColors[5].toARGB32();
    _icon = plan?.icon ?? defaultIconKey;
    _repeatType = plan?.repeatType ?? RepeatType.daily;
    _days = {...?plan?.repeatDays};
    _multiPerDay = plan?.multiPerDay ?? false;
    if (plan?.reminderHour != null) {
      _reminder = TimeOfDay(
        hour: plan!.reminderHour!,
        minute: plan.reminderMinute ?? 0,
      );
    }
    if (goal != null) {
      _goalMode = goal.type;
      if (goal.period != null) _goalPeriod = goal.period!;
      _goalUnit = goal.effectiveUnit;
      _deadline = goal.deadlineDate;
    }
  }

  @override
  void dispose() {
    // 页面销毁时统一释放控制器
    _nameController.dispose();
    _timesController.dispose();
    _toastEntry?.remove();
    super.dispose();
  }

  // 当前颜色是否为自定义色（不在预设色板中）
  bool get _isCustomColor =>
      !presetColors.any((c) => c.toARGB32() == _color);

  // 居中浮动提示气泡：无按钮、不阻挡操作，1.5 秒后自动消失
  void _toast(String msg) {
    // 已有提示先移除，避免叠加
    _toastEntry?.remove();
    _toastEntry = null;

    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Text(
                    msg,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    // 自动消失
    Timer(const Duration(milliseconds: 1500), () {
      if (_toastEntry == entry) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  // 选择提醒时间
  Future<void> _pickReminder() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _reminder ?? TimeOfDay.now(),
    );
    if (t != null) setState(() => _reminder = t);
  }

  // 选择截止日期
  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate:
          _deadline != null ? DateUtils.parse(_deadline!) : now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => _deadline = DateUtils.toKey(d));
  }

  // 自定义颜色对话框（HSV 三滑块）
  Future<void> _pickCustomColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) =>
          _ColorPickerDialog(initial: HSVColor.fromColor(Color(_color))),
    );
    if (picked != null) setState(() => _color = picked.toARGB32());
  }

  // 根据当前表单状态构造 Goal
  Goal _buildGoal(int planId, int times) {
    return Goal(
      planId: planId,
      type: _goalMode == 'frequency' ? GoalType.frequency : GoalType.total,
      period: _goalMode == 'frequency' ? _goalPeriod : null,
      totalTimes: times,
      deadlineDate: _goalMode == 'total' ? _deadline : null,
      startDate: DateUtils.today(),
      unit: _goalUnit,
    );
  }

  // 保存（新增或更新）
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('请输入计划名称');
      return;
    }
    if (_repeatType == RepeatType.weekly && _days.isEmpty) {
      _toast('请至少选择一个周期');
      return;
    }
    var times = 0;
    if (_goalMode != 'none') {
      times = int.tryParse(_timesController.text) ?? 0;
      if (times <= 0) {
        _toast('请输入有效的目标数量');
        return;
      }
    }

    final appState = context.read<AppState>();
    final plan = Plan(
      id: widget.plan?.id,
      name: name,
      color: _color,
      icon: _icon,
      repeatType: _repeatType,
      repeatDays: _days.toList()..sort(),
      multiPerDay: _multiPerDay,
      reminderHour: _reminder?.hour,
      reminderMinute: _reminder?.minute,
      createdAt: widget.plan?.createdAt ?? appState.nowStamp(),
    );

    if (widget.plan == null) {
      // 新增计划
      final id = await appState.addPlan(plan);
      if (_goalMode != 'none') {
        await appState.saveGoal(_buildGoal(id, times));
      }
    } else {
      // 编辑计划；目标改为"无"时删除旧目标
      await appState.editPlan(plan);
      if (_goalMode == 'none') {
        await appState.removeGoal(plan.id!);
      } else {
        await appState.saveGoal(_buildGoal(plan.id!, times));
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // 分组卡片：图标 + 标题 + 内容
  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  // 小节标签
  Widget _label(String text) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_color);
    // 单位文字，随"按天计/按次计"切换
    final unitChar = _goalUnit == GoalUnit.day ? '天' : '次';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan == null ? '添加计划' : '编辑计划'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ===== 基本信息 =====
          _section(
            context,
            icon: Icons.edit_note,
            title: '基本信息',
            children: [
              // 计划名称
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '计划名称',
                  hintText: '例如：晨跑、背单词',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              _label('颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  // 预设色板
                  for (final c in presetColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c.toARGB32()),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: _color == c.toARGB32()
                              ? Border.all(
                                  width: 3,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline)
                              : null,
                        ),
                      ),
                    ),
                  // 自定义颜色入口（彩虹调色盘）
                  GestureDetector(
                    onTap: _pickCustomColor,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isCustomColor ? color : null,
                        gradient: _isCustomColor
                            ? null
                            : const SweepGradient(colors: [
                                Colors.red,
                                Colors.orange,
                                Colors.yellow,
                                Colors.green,
                                Colors.cyan,
                                Colors.blue,
                                Colors.purple,
                                Colors.red,
                              ]),
                        border: _isCustomColor
                            ? Border.all(
                                width: 3,
                                color:
                                    Theme.of(context).colorScheme.outline)
                            : Border.all(
                                width: 1.5,
                                color:
                                    Theme.of(context).colorScheme.outline),
                      ),
                      child: _isCustomColor
                          ? null
                          : const Icon(Icons.add,
                              size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _label('图标'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in iconMap.entries)
                    GestureDetector(
                      onTap: () => setState(() => _icon = e.key),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: _icon == e.key
                            ? color
                            : color.withValues(alpha: 0.12),
                        child: Icon(
                          e.value,
                          size: 20,
                          color: _icon == e.key ? Colors.white : color,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ===== 打卡安排 =====
          _section(
            context,
            icon: Icons.event_repeat,
            title: '打卡安排',
            children: [
              _label('重复规则'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('每天'),
                    selected: _repeatType == RepeatType.daily,
                    onSelected: (_) =>
                        setState(() => _repeatType = RepeatType.daily),
                  ),
                  ChoiceChip(
                    label: const Text('每周固定几天'),
                    selected: _repeatType == RepeatType.weekly,
                    onSelected: (_) =>
                        setState(() => _repeatType = RepeatType.weekly),
                  ),
                  ChoiceChip(
                    label: const Text('不固定'),
                    selected: _repeatType == RepeatType.flex,
                    onSelected: (_) =>
                        setState(() => _repeatType = RepeatType.flex),
                  ),
                ],
              ),
              if (_repeatType == RepeatType.flex)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '不固定打卡：任何一天都能打卡，适合搭配"每月至少 N 天"的周期目标',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_repeatType == RepeatType.weekly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text('周${'一二三四五六日'[i - 1]}'),
                        selected: _days.contains(i),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _days.add(i);
                          } else {
                            _days.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // 提醒时间（仅记录，不弹系统通知）
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('提醒时间'),
                subtitle: Text(_reminder == null
                    ? '未设置（仅记录，不弹系统通知）'
                    : _reminder!.format(context)),
                value: _reminder != null,
                onChanged: (on) async {
                  if (on) {
                    await _pickReminder();
                  } else {
                    setState(() => _reminder = null);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ===== 打卡目标 =====
          _section(
            context,
            icon: Icons.track_changes,
            title: '打卡目标',
            children: [
              _label('目标类型'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('无'),
                    selected: _goalMode == 'none',
                    onSelected: (_) => setState(() => _goalMode = 'none'),
                  ),
                  ChoiceChip(
                    label: const Text('周期目标'),
                    selected: _goalMode == 'frequency',
                    onSelected: (_) => setState(() {
                      _goalMode = 'frequency';
                      _goalUnit = GoalUnit.day; // 周期目标默认按天计
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('总量目标'),
                    selected: _goalMode == 'total',
                    onSelected: (_) => setState(() {
                      _goalMode = 'total';
                      _goalUnit = GoalUnit.time; // 总量目标默认按次计
                    }),
                  ),
                ],
              ),
              if (_goalMode == 'frequency') ...[
                const SizedBox(height: 12),
                _label('统计周期'),
                const SizedBox(height: 8),
                // 周期选择
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in const [
                      (GoalPeriod.week, '每周至少'),
                      (GoalPeriod.month, '每月至少'),
                      (GoalPeriod.year, '每年至少'),
                    ])
                      ChoiceChip(
                        label: Text(p.$2),
                        selected: _goalPeriod == p.$1,
                        onSelected: (_) =>
                            setState(() => _goalPeriod = p.$1),
                      ),
                  ],
                ),
              ],
              if (_goalMode != 'none') ...[
                const SizedBox(height: 12),
                _label('计数单位'),
                const SizedBox(height: 8),
                // 计数单位：按天 / 按次（一天最多打一次，数值相同，说法不同）
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('按天计'),
                      selected: _goalUnit == GoalUnit.day,
                      onSelected: (_) =>
                          setState(() => _goalUnit = GoalUnit.day),
                    ),
                    ChoiceChip(
                      label: const Text('按次计'),
                      selected: _goalUnit == GoalUnit.time,
                      onSelected: (_) =>
                          setState(() => _goalUnit = GoalUnit.time),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 目标数量
                TextField(
                  controller: _timesController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _goalMode == 'frequency'
                        ? '每个周期至少几$unitChar'
                        : '总共计划几$unitChar',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText: unitChar,
                  ),
                ),
              ],
              if (_goalMode == 'frequency' &&
                  _goalUnit == GoalUnit.time) ...[
                const SizedBox(height: 8),
                // 按次计时，可选择每天是否允许打卡多次
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('每天可打卡多次'),
                  subtitle: Text(_multiPerDay
                      ? '开启：每天可以打卡多次，按次数累计'
                      : '关闭：每天最多打卡一次'),
                  value: _multiPerDay,
                  onChanged: (v) => setState(() => _multiPerDay = v),
                ),
              ],
              if (_goalMode == 'total') ...[
                const SizedBox(height: 8),
                // 截止日期（可选）
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.event),
                  title: Text(_deadline == null
                      ? '设置截止日期（可选）'
                      : '截止 $_deadline'),
                  trailing: _deadline == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _deadline = null),
                        ),
                  onTap: _pickDeadline,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          // 保存按钮
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(widget.plan == null ? '创建计划' : '保存修改'),
          ),
        ],
      ),
    );
  }
}

// 自定义颜色对话框：色相 / 饱和度 / 亮度三个滑块 + 实时预览
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final HSVColor initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = widget.initial;

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 实时预览
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _color.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _slider(
            label: '色相',
            value: _hsv.hue,
            max: 360,
            trackColors: const [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
            onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
          ),
          _slider(
            label: '饱和度',
            value: _hsv.saturation,
            max: 1,
            trackColors: [
              _hsv.withSaturation(0).toColor(),
              _hsv.withSaturation(1).toColor(),
            ],
            onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          ),
          _slider(
            label: '亮度',
            value: _hsv.value,
            max: 1,
            trackColors: [
              Colors.black,
              _hsv.withValue(1).toColor(),
            ],
            onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('确定'),
        ),
      ],
    );
  }

  // 带渐变轨道的滑块（轨道透明化，用渐变 Container 垫底）
  Widget _slider({
    required String label,
    required double value,
    required double max,
    required List<Color> trackColors,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 渐变轨道
              Container(
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(colors: trackColors),
                ),
              ),
              // 透明轨道的滑块，只显示白色圆点
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  trackShape: const _TransparentTrackShape(),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: value.clamp(0, max),
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 透明轨道形状：滑块底下垫自定义渐变 Container，轨道本身不绘制
class _TransparentTrackShape extends RoundedRectSliderTrackShape {
  const _TransparentTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    double additionalActiveTrackHeight = 0,
    bool isDiscrete = false,
    bool isEnabled = false,
    required TextDirection textDirection,
  }) {
    // 不绘制轨道，只保留滑块圆点
  }
}