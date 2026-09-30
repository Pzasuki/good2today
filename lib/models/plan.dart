// 计划模型：一条待打卡的事项。
// 字段对应数据库 plan 表。

// 重复规则类型
class RepeatType {
  // 每天
  static const String daily = 'daily';
  // 每周固定几天
  static const String weekly = 'weekly';
  // 不固定：任何一天都可打卡，靠周期目标（如每月至少 N 天）约束
  static const String flex = 'flex';
}

class Plan {
  final int? id;
  final String name; // 计划名称
  final int color; // 颜色 ARGB 值
  final String icon; // 图标 key（见 icon_map.dart）
  final String repeatType; // RepeatType.daily / weekly / flex
  final List<int> repeatDays; // 每周固定几天（周一=1..周日=7），daily 为空
  final bool multiPerDay; // 每天是否可打卡多次（按次计目标时用）
  final int? reminderHour; // 提醒小时（仅记录）
  final int? reminderMinute; // 提醒分钟（仅记录）
  final String createdAt; // 创建时间 yyyy-MM-dd HH:mm
  final int archived; // 1=软删除（归档），0=正常

  const Plan({
    this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.repeatType,
    this.repeatDays = const [],
    this.multiPerDay = false,
    this.reminderHour,
    this.reminderMinute,
    required this.createdAt,
    this.archived = 0,
  });

  // 从数据库中读取一行构造 Plan
  factory Plan.fromMap(Map<String, Object?> map) {
    return Plan(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as int? ?? 0,
      icon: map['icon'] as String? ?? 'flag',
      repeatType: map['repeat_type'] as String? ?? RepeatType.daily,
      repeatDays: _parseRepeatDays(map['repeat_days'] as String?),
      multiPerDay: (map['multi_per_day'] as int? ?? 0) == 1,
      reminderHour: map['reminder_hour'] as int?,
      reminderMinute: map['reminder_minute'] as int?,
      createdAt: map['created_at'] as String? ?? '',
      archived: map['archived'] as int? ?? 0,
    );
  }

  // 转成数据库可写入的 Map
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'repeat_type': repeatType,
      'repeat_days': _encodeRepeatDays(repeatDays),
      'multi_per_day': multiPerDay ? 1 : 0,
      'reminder_hour': reminderHour,
      'reminder_minute': reminderMinute,
      'created_at': createdAt,
      'archived': archived,
    };
  }

  // 把 List<int> 存成数据库字符串，例如 '1,3,5'
  static String _encodeRepeatDays(List<int> days) => days.join(',');

  // 从数据库字符串解析回 List<int>
  static List<int> _parseRepeatDays(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map(int.parse).toList();
  }

  // 该计划某天是否需要打卡？
  // flex（不固定）任何一天都可以打卡，但不计入完成率的应打卡统计
  bool shouldCheckIn(DateTime day) {
    switch (repeatType) {
      case RepeatType.daily:
      case RepeatType.flex:
        return true;
      case RepeatType.weekly:
        return repeatDays.contains(day.weekday);
      default:
        return false;
    }
  }

  // 拷贝并修改部分字段（用于编辑计划）
  Plan copyWith({
    String? name,
    int? color,
    String? icon,
    String? repeatType,
    List<int>? repeatDays,
    bool? multiPerDay,
    int? reminderHour,
    int? reminderMinute,
    int? archived,
  }) {
    return Plan(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      repeatType: repeatType ?? this.repeatType,
      repeatDays: repeatDays ?? this.repeatDays,
      multiPerDay: multiPerDay ?? this.multiPerDay,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      createdAt: createdAt,
      archived: archived ?? this.archived,
    );
  }

  // 重复规则的展示文字，如 "每天"、"不固定打卡" 或 "周一 周三"
  String repeatDescription() {
    if (repeatType == RepeatType.daily) return '每天';
    if (repeatType == RepeatType.flex) return '不固定打卡';
    const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
    return repeatDays.map((d) => '周${weekNames[d - 1]}').join(' ');
  }
}