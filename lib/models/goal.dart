// 目标模型：绑定到某个计划，描述"计划打卡多少"。
// 支持两种形式：
//  1. frequency 周期目标：每周/每月/每年至少 N（周期内累计）
//  2. total 总量目标：总共 N，可选截止日期（如"30天内完成20次"）
// 计数单位可选"天"或"次"：一天最多打一次卡，两者数值相同，只是说法不同。

// 目标类型
class GoalType {
  // 周期目标：每周/每月/每年 N
  static const String frequency = 'frequency';
  // 总量目标：总共 N（可选截止日期）
  static const String total = 'total';
}

// 周期目标的周期
class GoalPeriod {
  static const String week = 'week';
  static const String month = 'month';
  static const String year = 'year';
}

// 计数单位
class GoalUnit {
  static const String day = 'day'; // 按天计
  static const String time = 'time'; // 按次计
}

class Goal {
  final int? id;
  final int planId; // 所属计划 ID
  final String type; // GoalType.frequency / total
  final String? period; // 周期目标的周期（week/month/year），total 为 null
  final int totalTimes; // 目标数值（frequency=每周期数量，total=总数量）
  final String? deadlineDate; // 总量目标的可选截止日期 yyyy-MM-dd
  final String startDate; // 目标起点 yyyy-MM-dd（预留）
  final String? unit; // GoalUnit.day / time；null 时按类型取默认

  const Goal({
    this.id,
    required this.planId,
    required this.type,
    this.period,
    required this.totalTimes,
    this.deadlineDate,
    this.startDate = '',
    this.unit,
  });

  // 实际生效的单位：未设置时周期目标默认按天、总量目标默认按次
  String get effectiveUnit =>
      unit ?? (type == GoalType.frequency ? GoalUnit.day : GoalUnit.time);

  // 单位文字：天 / 次
  String get unitText => effectiveUnit == GoalUnit.day ? '天' : '次';

  factory Goal.fromMap(Map<String, Object?> map) {
    // 兼容旧版本的 'count'/'deadline' 类型，统一按 total 处理
    final rawType = map['type'] as String? ?? GoalType.total;
    final type = rawType == GoalType.frequency ? rawType : GoalType.total;
    return Goal(
      id: map['id'] as int?,
      planId: map['plan_id'] as int? ?? 0,
      type: type,
      period: map['period'] as String?,
      totalTimes: map['total_times'] as int? ?? 0,
      deadlineDate: map['deadline_date'] as String?,
      startDate: map['start_date'] as String? ?? '',
      unit: map['unit'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'plan_id': planId,
      'type': type,
      'period': period,
      'total_times': totalTimes,
      'deadline_date': deadlineDate,
      'start_date': startDate,
      'unit': unit,
    };
  }

  Goal copyWith({
    int? id,
    int? planId,
    String? type,
    String? period,
    int? totalTimes,
    String? deadlineDate,
    String? startDate,
    String? unit,
  }) {
    return Goal(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      type: type ?? this.type,
      period: period ?? this.period,
      totalTimes: totalTimes ?? this.totalTimes,
      deadlineDate: deadlineDate ?? this.deadlineDate,
      startDate: startDate ?? this.startDate,
      unit: unit ?? this.unit,
    );
  }
}

// 聚合展示用的周期单位词（如"连续 3 个月"）。
// 各计划的周期不一致时用中性的"个周期"，避免拿某一个计划的周期
// 给所有计划的统计结果配单位。
String frequencyPeriodWord(Iterable<String?> periods) {
  final distinct = periods.whereType<String>().toSet();
  if (distinct.length != 1) return '个周期';
  return switch (distinct.first) {
    GoalPeriod.week => '周',
    GoalPeriod.year => '年',
    _ => '个月',
  };
}