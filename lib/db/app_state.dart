// AppState：全局状态，注入数据库并提供业务逻辑。
// 页面通过 context.watch<AppState>() 读取与调用。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'database_helper.dart';
import '../models/plan.dart';
import '../models/goal.dart';
import '../models/record.dart';
import '../utils/app_themes.dart';
import '../utils/date_utils.dart';

class AppState extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // 数据缓存
  List<Plan> _plans = [];
  List<Goal> _goals = [];
  List<Record> _records = [];

  bool _loaded = false;
  bool get loaded => _loaded;

  // 当前主题配色 key（持久化在设置表）
  String _themeKey = 'indigo';
  String get themeKey => _themeKey;

  // 当前主题的种子色，MaterialApp 用它生成整套配色
  Color get themeSeed => themeByKey(_themeKey).seed;

  // 切换主题颜色（先更新 UI 再持久化）
  Future<void> setThemeKey(String key) async {
    _themeKey = key;
    notifyListeners();
    await _db.setSetting('theme_key', key);
  }

  List<Plan> get plans => List.unmodifiable(_plans);
  List<Goal> get goals => List.unmodifiable(_goals);
  List<Record> get records => List.unmodifiable(_records);

  // 初始化：加载设置与数据
  Future<void> init() async {
    _themeKey = await _db.getSetting('theme_key') ?? 'indigo';
    await reload();
  }

  // 重新从数据库加载所有数据
  Future<void> reload() async {
    _plans = await _db.getPlans();
    _goals = await _db.getGoals();
    _records = await _db.getRecords();
    _loaded = true;
    notifyListeners();
  }

  // ============ 计划操作 ============

  // 新增计划，返回其 id
  Future<int> addPlan(Plan plan) async {
    final id = await _db.insertPlan(plan);
    await reload();
    return id;
  }

  // 编辑计划
  Future<void> editPlan(Plan plan) async {
    await _db.updatePlan(plan);
    await reload();
  }

  // 软删除计划
  Future<void> archivePlan(int id) async {
    await _db.archivePlan(id);
    await reload();
  }

  // ============ 目标操作 ============

  // 保存目标（同一计划已存在则更新）
  Future<void> saveGoal(Goal goal) async {
    final existing = await _db.getGoalForPlan(goal.planId);
    if (existing == null) {
      await _db.insertGoal(goal);
    } else {
      await _db.updateGoal(goal.copyWith(id: existing.id));
    }
    await reload();
  }

  // 删除某计划的目标
  Future<void> removeGoal(int planId) async {
    final existing = await _db.getGoalForPlan(planId);
    if (existing != null) {
      await _db.deleteGoal(existing.id!);
      await reload();
    }
  }

  // ============ 打卡操作 ============

  // 判断某计划某天是否已打卡
  bool hasRecord(int planId, String date) =>
      _records.any((r) => r.planId == planId && r.date == date);

  // 查询某计划某天的记录（可能为 null）
  Record? recordOf(int planId, String date) {
    for (final r in _records) {
      if (r.planId == planId && r.date == date) return r;
    }
    return null;
  }

  // 某计划某天的打卡次数（0 = 未打卡）
  int checkCount(int planId, String date) =>
      recordOf(planId, date)?.count ?? 0;

  // 点按打卡：普通计划 = 打卡/取消切换；开启"每天可多次"的计划 = 次数 +1
  Future<void> tapCheckIn(Plan plan, String date) async {
    final existing = recordOf(plan.id!, date);
    if (existing == null) {
      await _db.insertRecord(Record(
        planId: plan.id!,
        date: date,
        count: 1,
        createdAt: nowStamp(),
      ));
    } else if (plan.multiPerDay) {
      // 每天可多次：次数累加
      await _db.updateRecord(existing.copyWith(count: existing.count + 1));
    } else {
      // 普通计划：再点一次取消打卡
      await _db.deleteRecord(existing.id!);
    }
    await reload();
  }

  // 减少一次打卡（每天可多次的计划用）；减到 0 时删除记录
  Future<void> removeOneCheckIn(Plan plan, String date) async {
    final existing = recordOf(plan.id!, date);
    if (existing == null) return;
    if (existing.count <= 1) {
      await _db.deleteRecord(existing.id!);
    } else {
      await _db.updateRecord(existing.copyWith(count: existing.count - 1));
    }
    await reload();
  }

  // 设置备注；该天没有记录且备注为空时不创建空记录
  Future<void> setNote(int planId, String date, String note) async {
    final existing = recordOf(planId, date);
    final trimmed = note.trim();
    if (existing == null) {
      if (trimmed.isEmpty) return; // 没打卡也没写内容，不生成记录
      await _db.insertRecord(Record(
        planId: planId,
        date: date,
        note: trimmed,
        createdAt: nowStamp(),
      ));
    } else {
      // 只改备注（copyWith 保留 count 等其他字段；空串表示清空备注）
      await _db.updateRecord(
        existing.copyWith(note: trimmed.isEmpty ? '' : trimmed),
      );
    }
    await reload();
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
  Goal? goalOf(int planId) {
    for (final g in _goals) {
      if (g.planId == planId) return g;
    }
    return null;
  }

  // 某计划已打卡的日期集合
  Set<String> recordDatesOf(int planId) =>
      _records.where((r) => r.planId == planId).map((r) => r.date).toSet();

  // 某天的所有打卡记录（日历圆点/明细用）
  List<Record> recordsOn(String date) =>
      _records.where((r) => r.date == date).toList();

  // 按 ID 查找计划（找不到返回 null）
  Plan? planById(int? id) {
    if (id == null) return null;
    for (final p in _plans) {
      if (p.id == id) return p;
    }
    return null;
  }

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
        hasRecord(plan.id!, DateUtils.toKey(day))) {
      count++;
      day = DateUtils.addDays(day, -1);
    }
    return count;
  }

  // 某计划总打卡次数（含一天多次的累计）
  int totalCount(int planId) => _records
      .where((r) => r.planId == planId)
      .fold(0, (sum, r) => sum + r.count);

  // 目标已完成数量：按天计 = 有记录的天数；按次计 = 打卡次数累计
  int goalDoneCount(Plan plan, Goal goal) {
    final byDay = goal.effectiveUnit == GoalUnit.day;
    if (goal.type == GoalType.frequency) {
      final now = DateTime.now();
      final range =
          DateUtils.periodRange(goal.period ?? GoalPeriod.month, now);
      final startKey = DateUtils.toKey(range.$1);
      final endKey = DateUtils.toKey(range.$2);
      if (byDay) {
        // 按天计：统计区间内有记录的天数（一天打多次也算一天）
        return _records
            .where((r) =>
                r.planId == plan.id &&
                r.date.compareTo(startKey) >= 0 &&
                r.date.compareTo(endKey) <= 0)
            .map((r) => r.date)
            .toSet()
            .length;
      }
      return countInRange(plan, range.$1, range.$2);
    }
    // 总量目标
    return byDay
        ? recordDatesOf(plan.id!).length
        : totalCount(plan.id!);
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
    for (final r in _records) {
      if (r.planId == plan.id &&
          r.date.compareTo(startKey) >= 0 &&
          r.date.compareTo(endKey) <= 0) {
        c += r.count;
      }
    }
    return c;
  }

  // 本周（周一到今天）完成率：应打卡 vs 已打卡
  double weekCompletionRate() {
    final now = DateTime.now();
    final monday = DateUtils.addDays(now, -(now.weekday - 1));
    return _periodCompletionRate(monday, now);
  }

  // 本月（1号到今天）完成率
  double monthCompletionRate() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    return _periodCompletionRate(first, now);
  }

  // 计算某区间完成率：所有有效计划的应打卡天数合计为分母
  double _periodCompletionRate(DateTime start, DateTime end) {
    var expected = 0;
    var done = 0;
    for (final plan in _plans) {
      // 不固定打卡的计划没有"应打卡日"，不计入完成率分母
      if (plan.repeatType == RepeatType.flex) continue;
      for (var d = DateUtils.dateOnly(start);
          !d.isAfter(DateUtils.dateOnly(end));
          d = DateUtils.addDays(d, 1)) {
        if (plan.shouldCheckIn(d)) {
          expected++;
          if (hasRecord(plan.id!, DateUtils.toKey(d))) done++;
        }
      }
    }
    if (expected == 0) return 0;
    return done / expected;
  }

  // 某计划历史上最长的连续打卡天数
  int maxStreakOf(Plan plan) {
    final dates = recordDatesOf(plan.id!).toList()..sort();
    if (dates.isEmpty) return 0;
    var best = 0;
    var cur = 0;
    // 从第一次打卡那天逐天走到今天：
    // 应打卡且打了 → 连续 +1；应打卡却没打 → 连续清零；非打卡日不影响
    var day = DateUtils.parse(dates.first);
    final today = DateUtils.dateOnly(DateTime.now());
    while (!day.isAfter(today)) {
      if (plan.shouldCheckIn(day)) {
        if (hasRecord(plan.id!, DateUtils.toKey(day))) {
          cur++;
          if (cur > best) best = cur;
        } else {
          cur = 0;
        }
      }
      day = DateUtils.addDays(day, 1);
    }
    return best;
  }

  // 所有计划中的历史最长连续天数
  int maxStreak() {
    var best = 0;
    for (final plan in _plans) {
      final s = maxStreakOf(plan);
      if (s > best) best = s;
    }
    return best;
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
  // 返回导入摘要文字。
  Future<String> importFromJson(String raw, {required bool merge}) async {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('plans')) {
      throw const FormatException('不是有效的打卡备份文件');
    }
    final plans = [
      for (final item in decoded['plans'] as List? ?? [])
        Plan.fromMap(item as Map<String, Object?>),
    ];
    final goals = [
      for (final item in decoded['goals'] as List? ?? [])
        Goal.fromMap(item as Map<String, Object?>),
    ];
    final records = [
      for (final item in decoded['records'] as List? ?? [])
        Record.fromMap(item as Map<String, Object?>),
    ];

    // 覆盖模式先清空现有数据
    if (!merge) {
      await _db.clearAll();
    }

    var planCount = 0;
    for (final p in plans) {
      if (p.id == null) continue;
      if (merge && await _db.planExists(p.id!)) continue;
      await _db.insertPlan(p);
      planCount++;
    }
    var goalCount = 0;
    for (final g in goals) {
      if (merge && await _db.goalExistsForPlan(g.planId)) continue;
      await _db.insertGoal(g);
      goalCount++;
    }
    var recordCount = 0;
    for (final r in records) {
      // 同计划同日期只保留一条，合并时自动去重
      if (await _db.insertRecordIfAbsent(r) != null) recordCount++;
    }
    await reload();
    return '计划 $planCount 个、目标 $goalCount 个、记录 $recordCount 条';
  }
}