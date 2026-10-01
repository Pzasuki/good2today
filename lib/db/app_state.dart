// AppState：全局状态，注入数据库并提供业务逻辑。
// 页面通过 context.watch<AppState>() 读取与调用。

import 'dart:convert';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import '../models/plan.dart';
import '../models/goal.dart';
import '../models/record.dart';
import '../utils/date_utils.dart';

class AppState extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // 数据缓存（就地更新，对外只读）
  final List<Plan> _plans = [];
  final List<Goal> _goals = [];
  final List<Record> _records = [];

  // 只读视图：构造一次常驻，getter 调用零分配；列表就地更新时视图始终同步
  late final List<Plan> _plansView = UnmodifiableListView(_plans);
  late final List<Goal> _goalsView = UnmodifiableListView(_goals);
  late final List<Record> _recordsView = UnmodifiableListView(_records);

  // 派生索引：reload 后重建，单记录操作通过 _syncRecord 增量维护。
  // 让高频查询（打卡判断、日历格子、连续天数等）从全表扫描降为 O(1)。
  final Map<int, Plan> _plansById = {}; // planId -> Plan
  final Map<int, Goal> _goalsByPlan = {}; // planId -> Goal
  // dateKey -> planId -> Record
  final Map<String, Map<int, Record>> _recordsByDate = {};
  final Map<int, List<Record>> _recordsByPlan = {}; // planId -> records

  // 当前主题配色 key（持久化在设置表）
  String _themeKey = 'indigo';
  String get themeKey => _themeKey;

  // 切换主题颜色（先更新 UI 再持久化）
  Future<void> setThemeKey(String key) async {
    _themeKey = key;
    notifyListeners();
    await _db.setSetting('theme_key', key);
  }

  List<Plan> get plans => _plansView;
  List<Goal> get goals => _goalsView;
  List<Record> get records => _recordsView;

  // 初始化：加载设置与数据
  Future<void> init() async {
    _themeKey = await _db.getSetting('theme_key') ?? 'indigo';
    await reload();
  }

  // 重新从数据库加载所有数据并重建索引。
  // 列表就地更新（clear + addAll），保证对外只读视图的引用始终有效。
  Future<void> reload() async {
    // 三张表并行查询
    final plansFuture = _db.getPlans();
    final goalsFuture = _db.getGoals();
    final recordsFuture = _db.getRecords();
    _plans
      ..clear()
      ..addAll(await plansFuture);
    _goals
      ..clear()
      ..addAll(await goalsFuture);
    _records
      ..clear()
      ..addAll(await recordsFuture);
    _rebuildIndexes();
    notifyListeners();
  }

  void _rebuildIndexes() {
    _plansById.clear();
    for (final p in _plans) {
      if (p.id != null) _plansById[p.id!] = p;
    }
    _goalsByPlan.clear();
    for (final g in _goals) {
      _goalsByPlan.putIfAbsent(g.planId, () => g);
    }
    _recordsByDate.clear();
    _recordsByPlan.clear();
    for (final r in _records) {
      _recordsByDate.putIfAbsent(r.date, () => {})[r.planId] = r;
      _recordsByPlan.putIfAbsent(r.planId, () => []).add(r);
    }
  }

  // 用数据库返回的权威状态同步内存缓存（record 为 null 表示该天已无记录）。
  // 返回是否有实际变化。
  bool _syncRecord(int planId, String date, Record? record) {
    final byDate = _recordsByDate.putIfAbsent(date, () => {});
    final old = byDate[planId];
    if (record == null) {
      byDate.remove(planId);
      if (byDate.isEmpty) _recordsByDate.remove(date);
      if (old == null) return false;
      _records.remove(old);
      _recordsByPlan[planId]?.remove(old);
      return true;
    }
    byDate[planId] = record;
    if (old != null) {
      final idx = _records.indexOf(old);
      if (idx >= 0) _records[idx] = record;
      final planList = _recordsByPlan[planId];
      if (planList != null) {
        final pidx = planList.indexOf(old);
        if (pidx >= 0) planList[pidx] = record;
      }
    } else {
      _records.add(record);
      _recordsByPlan.putIfAbsent(planId, () => []).add(record);
    }
    return true;
  }

  // ============ 计划 / 目标操作 ============

  // 保存计划与目标（供编辑页的新增/编辑/清除目标统一使用）：
  // 一次写库、一次 reload。goal 为 null 表示不设置目标（已有的会被删除）；
  // goal 的 planId 会被覆盖为实际计划 id（其 id 应为 null，由自增分配）。
  // 返回计划 id。
  Future<int> savePlanWithGoal(Plan plan, Goal? goal) async {
    var planId = plan.id;
    if (planId == null) {
      planId = await _db.insertPlan(plan);
    } else {
      await _db.updatePlan(plan);
    }
    final existing = await _db.getGoalForPlan(planId);
    if (goal == null) {
      // 目标改为"无"：删除旧目标
      if (existing != null) await _db.deleteGoal(existing.id!);
    } else if (existing == null) {
      await _db.insertGoal(goal.copyWith(planId: planId));
    } else {
      await _db.updateGoal(goal.copyWith(id: existing.id, planId: planId));
    }
    await reload();
    return planId;
  }

  // 软删除计划
  Future<void> archivePlan(int id) async {
    await _db.archivePlan(id);
    await reload();
  }

  // ============ 打卡操作 ============

  // 某计划某天是否有记录（含"纯备注"记录）
  bool hasRecord(int planId, String date) =>
      _recordsByDate[date]?.containsKey(planId) ?? false;

  // 某计划某天是否已打卡（纯备注记录 count=0 不算）
  bool isDone(int planId, String date) =>
      (_recordsByDate[date]?[planId]?.count ?? 0) > 0;

  // 查询某计划某天的记录（可能为 null）
  Record? recordOf(int planId, String date) => _recordsByDate[date]?[planId];

  // 某计划某天的打卡次数（0 = 未打卡）
  int checkCount(int planId, String date) =>
      recordOf(planId, date)?.count ?? 0;

  // 点按打卡：普通计划 = 打卡/取消切换；开启"每天可多次"的计划 = 次数 +1。
  // 写库在数据库事务内以实际状态为准（连点安全），完成后只同步内存缓存，
  // 不再全量 reload。
  Future<void> tapCheckIn(Plan plan, String date) async {
    final Record? result;
    if (plan.multiPerDay) {
      result = await _db.incrementRecord(plan.id!, date, nowStamp());
    } else {
      result = await _db.toggleRecord(plan.id!, date, nowStamp());
    }
    if (_syncRecord(plan.id!, date, result)) notifyListeners();
  }

  // 减少一次打卡（每天可多次的计划用）；减到 0 时删除记录，有备注则保留为纯备注
  Future<void> removeOneCheckIn(Plan plan, String date) async {
    final result = await _db.decrementRecord(plan.id!, date);
    if (_syncRecord(plan.id!, date, result)) notifyListeners();
  }

  // 设置备注；没打卡只写备注 = 生成 count=0 的"纯备注"记录，不计入完成数
  // 与连续天数。该天没有记录且备注为空时不创建记录。
  Future<void> setNote(int planId, String date, String note) async {
    final result = await _db.setNoteRecord(planId, date, note.trim(), nowStamp());
    if (_syncRecord(planId, date, result)) notifyListeners();
  }

  // 当前时间戳 yyyy-MM-dd HH:mm
  String nowStamp() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '${DateUtils.toKey(now)} $h:$m';
  }

  // ============ 查询 / 统计 ============

  // 某计划的目标（可能为 null）
  Goal? goalOf(int planId) => _goalsByPlan[planId];

  // 某计划已打卡（count>0）的日期集合
  Set<String> recordDatesOf(int planId) => {
        for (final r in _recordsByPlan[planId] ?? const <Record>[])
          if (r.count > 0) r.date,
      };

  // 某天的所有打卡记录（日历圆点/明细用）
  List<Record> recordsOn(String date) =>
      _recordsByDate[date]?.values.toList() ?? const [];

  // 按 ID 查找计划（找不到返回 null）
  Plan? planById(int? id) => id == null ? null : _plansById[id];

  // 某计划从某天往回的连续天数（只统计该计划应打卡的日子）
  int streakDays(Plan plan, {DateTime? anchor}) {
    var day = DateUtils.dateOnly(anchor ?? DateTime.now());
    var count = 0;
    // 若当天不是应打卡日，则从昨天开始算
    if (!plan.shouldCheckIn(day)) {
      day = DateUtils.addDays(day, -1);
    }
    // 逐天往前数，遇到未打卡的应打卡日即停
    while (plan.shouldCheckIn(day) &&
        isDone(plan.id!, DateUtils.toKey(day))) {
      count++;
      day = DateUtils.addDays(day, -1);
    }
    return count;
  }

  // 某计划总打卡次数（含一天多次的累计）
  int totalCount(int planId) {
    var sum = 0;
    for (final r in _recordsByPlan[planId] ?? const <Record>[]) {
      sum += r.count;
    }
    return sum;
  }

  // 目标在某周期内的实际完成数量（anchor 为该周期内任意一天）
  // 按天计 = 区间内有记录的天数；按次计 = 打卡次数累计
  int goalDoneInPeriod(Plan plan, Goal goal, DateTime anchor) {
    final range =
        DateUtils.periodRange(goal.period ?? GoalPeriod.month, anchor);
    if (goal.effectiveUnit == GoalUnit.day) {
      return daysInRange(plan, range.$1, range.$2);
    }
    return countInRange(plan, range.$1, range.$2);
  }

  // 目标在当前周期的实际完成数量
  int goalDoneCount(Plan plan, Goal goal) {
    // 总量目标：按天计 = 全部有记录天数；按次计 = 总次数
    if (goal.type == GoalType.total) {
      return goal.effectiveUnit == GoalUnit.day
          ? recordDatesOf(plan.id!).length
          : totalCount(plan.id!);
    }
    return goalDoneInPeriod(plan, goal, DateTime.now());
  }

  // 周期起始日（anchor 所在周期的第一天）
  DateTime _periodStart(String period, DateTime anchor) {
    switch (period) {
      case GoalPeriod.week:
        return DateUtils.dateOnly(
            DateUtils.addDays(anchor, -(anchor.weekday - 1)));
      case GoalPeriod.year:
        return DateTime(anchor.year, 1, 1);
      default:
        return DateTime(anchor.year, anchor.month, 1);
    }
  }

  // 下一个周期的起始日
  DateTime _nextPeriodStart(String period, DateTime anchor) {
    final start = _periodStart(period, anchor);
    switch (period) {
      case GoalPeriod.week:
        return DateUtils.addDays(start, 7);
      case GoalPeriod.year:
        return DateTime(start.year + 1, 1, 1);
      default:
        return DateTime(start.year, start.month + 1, 1);
    }
  }

  // 上一个周期的起始日
  DateTime _previousPeriodStart(String period, DateTime anchor) {
    final start = _periodStart(period, anchor);
    return _periodStart(period, DateUtils.addDays(start, -1));
  }

  // 连续达成目标的周期数；当前周期未达标不视为中断
  int goalStreak(Plan plan, Goal goal) {
    if (goal.totalTimes <= 0) return 0;
    final period = goal.period ?? GoalPeriod.month;
    final now = DateUtils.dateOnly(DateTime.now());
    var count = 0;
    var anchor = _periodStart(period, now);
    // 当前周期（进行中）已达标才计入
    if (goalDoneInPeriod(plan, goal, anchor) >= goal.totalTimes) {
      count++;
    }
    // 从上一个完整周期往回数，遇到未达标即停
    anchor = _previousPeriodStart(period, anchor);
    while (goalDoneInPeriod(plan, goal, anchor) >= goal.totalTimes) {
      count++;
      anchor = _previousPeriodStart(period, anchor);
      if (anchor.isBefore(DateTime(2000, 1, 1))) break; // 防御
    }
    return count;
  }

  // 历史上最长的连续达标周期数
  int bestGoalStreak(Plan plan, Goal goal) {
    if (goal.totalTimes <= 0) return 0;
    final period = goal.period ?? GoalPeriod.month;
    final dates = recordDatesOf(plan.id!).toList()..sort();
    if (dates.isEmpty) return 0;
    var anchor = _periodStart(period, DateUtils.parse(dates.first));
    final now = DateUtils.dateOnly(DateTime.now());
    var cur = 0;
    var best = 0;
    while (!anchor.isAfter(now)) {
      if (goalDoneInPeriod(plan, goal, anchor) >= goal.totalTimes) {
        cur++;
        if (cur > best) best = cur;
      } else {
        cur = 0;
      }
      anchor = _nextPeriodStart(period, anchor);
    }
    return best;
  }

  // 目标最近 count 个周期的完成情况（从新到旧，返回周期起始日与完成数）
  List<(DateTime, int)> goalPeriodHistory(Plan plan, Goal goal,
      {int count = 12}) {
    final period = goal.period ?? GoalPeriod.month;
    var anchor = _periodStart(period, DateUtils.dateOnly(DateTime.now()));
    final out = <(DateTime, int)>[];
    for (var i = 0; i < count; i++) {
      out.add((anchor, goalDoneInPeriod(plan, goal, anchor)));
      anchor = _previousPeriodStart(period, anchor);
    }
    return out;
  }

  // 从最早记录所在周期到当前周期的周期总数
  int goalPeriodCount(Plan plan, Goal goal) {
    final period = goal.period ?? GoalPeriod.month;
    final dates = recordDatesOf(plan.id!).toList()..sort();
    if (dates.isEmpty) return 1;
    final start = _periodStart(period, DateUtils.parse(dates.first));
    final current = _periodStart(period, DateUtils.dateOnly(DateTime.now()));
    var count = 1;
    var cursor = start;
    while (cursor.isBefore(current)) {
      cursor = _nextPeriodStart(period, cursor);
      count++;
      if (count > 1200) break; // 防御
    }
    return count;
  }

  // 目标的展示文案，如 "本月 3/12 天"；无目标返回 null
  String? goalSummary(Plan plan, Goal? goal) {
    if (goal == null || goal.totalTimes <= 0) return null;
    final done = goalDoneCount(plan, goal);
    final unit = goal.unitText;
    if (goal.type == GoalType.frequency) {
      final label = switch (goal.period) {
        GoalPeriod.week => '本周',
        GoalPeriod.year => '今年',
        _ => '本月',
      };
      // 达到目标数量时标记已达标
      final met = done >= goal.totalTimes;
      return '$label $done/${goal.totalTimes} $unit${met ? ' · 已达标' : ''}';
    }
    // 总量目标：显示累计数，有截止日期时附加剩余天数
    var s = '累计 $done/${goal.totalTimes} $unit';
    if (goal.deadlineDate != null) {
      final days = DateUtils
          .parse(goal.deadlineDate!)
          .difference(DateUtils.dateOnly(DateTime.now()))
          .inDays;
      if (days >= 0) s += ' · 剩 $days 天';
    }
    return s;
  }

  // 目标完成进度 0.0 ~ 1.0；无目标返回 null
  double? goalProgress(Plan plan, Goal? goal) {
    if (goal == null || goal.totalTimes <= 0) return null;
    return (goalDoneCount(plan, goal) / goal.totalTimes).clamp(0.0, 1.0);
  }

  // 某计划在 [start, end] 区间内打卡次数（含一天多次的累计）
  int countInRange(Plan plan, DateTime start, DateTime end) {
    final startKey = DateUtils.toKey(start);
    final endKey = DateUtils.toKey(end);
    var c = 0;
    for (final r in _recordsByPlan[plan.id] ?? const <Record>[]) {
      if (r.date.compareTo(startKey) >= 0 &&
          r.date.compareTo(endKey) <= 0) {
        c += r.count;
      }
    }
    return c;
  }

  // 某计划在区间内的打卡天数（一天多次也算一天；纯备注不算）
  int daysInRange(Plan plan, DateTime start, DateTime end) {
    final startKey = DateUtils.toKey(start);
    final endKey = DateUtils.toKey(end);
    final dates = <String>{};
    for (final r in _recordsByPlan[plan.id] ?? const <Record>[]) {
      if (r.count > 0 &&
          r.date.compareTo(startKey) >= 0 &&
          r.date.compareTo(endKey) <= 0) {
        dates.add(r.date);
      }
    }
    return dates.length;
  }

  // ============ 导入 / 导出 ============

  // 生成备份 JSON 字符串（含已归档计划）
  // 带两空格缩进、按稳定顺序排列，方便人工查看和 diff
  Future<String> exportToJson() async {
    final plans = await _db.getAllPlans();
    // 目标按所属计划排序，记录按日期再按计划排序
    final goals = [..._goals]..sort((a, b) => a.planId.compareTo(b.planId));
    final records = [..._records]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.planId.compareTo(b.planId);
      });
    final data = {
      'app': 'daily_log',
      'formatVersion': 1,
      'exportedAt': nowStamp(),
      'plans': [for (final p in plans) p.toMap()],
      'goals': [for (final g in goals) g.toMap()],
      'records': [for (final r in records) r.toMap()],
    };
    // 缩进输出；Dart 的 jsonEncode 不转义中文，可直接阅读
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // 从 JSON 字符串导入；merge=true 合并（跳过重复），false 覆盖（清空后导入）。
  // 解析阶段逐条校验，损坏/非法的数据跳过而不是让整个导入失败或污染后续页面；
  // 实际写入在数据库单事务内完成（原子性）。返回导入摘要文字。
  Future<String> importFromJson(String raw, {required bool merge}) async {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('plans')) {
      throw const FormatException('不是有效的打卡备份文件');
    }

    var skipped = 0;
    bool isValidDate(String s) {
      try {
        DateUtils.parse(s);
        return true;
      } catch (_) {
        return false;
      }
    }

    final plans = <Plan>[];
    for (final item in decoded['plans'] as List? ?? []) {
      try {
        final p = Plan.fromMap(item as Map<String, Object?>);
        if (p.id == null) {
          skipped++;
          continue;
        }
        // repeatDays 只保留 1~7，避免脏数据导致展示"周几"时越界
        plans.add(p.copyWith(
          repeatDays: [for (final d in p.repeatDays) if (d >= 1 && d <= 7) d],
        ));
      } catch (_) {
        skipped++;
      }
    }

    final goals = <Goal>[];
    for (final item in decoded['goals'] as List? ?? []) {
      try {
        final g = Goal.fromMap(item as Map<String, Object?>);
        if (g.totalTimes < 0 ||
            (g.deadlineDate != null && !isValidDate(g.deadlineDate!))) {
          skipped++;
          continue;
        }
        goals.add(g);
      } catch (_) {
        skipped++;
      }
    }

    final records = <Record>[];
    for (final item in decoded['records'] as List? ?? []) {
      try {
        final r = Record.fromMap(item as Map<String, Object?>);
        // 日期必须合法（统计/日历按日期解析），次数不能为负；count=0 是纯备注记录
        if (r.count < 0 || !isValidDate(r.date)) {
          skipped++;
          continue;
        }
        records.add(r);
      } catch (_) {
        skipped++;
      }
    }

    final (planCount, goalCount, recordCount, orphanCount) =
        await _db.importAll(
            plans: plans, goals: goals, records: records, merge: merge);
    skipped += orphanCount;
    await reload();
    final base = '计划 $planCount 个、目标 $goalCount 个、记录 $recordCount 条';
    return skipped > 0 ? '$base（跳过无效数据 $skipped 条）' : base;
  }
}