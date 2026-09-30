// 打卡记录模型：某计划某天的打卡情况。
// count > 1 表示开启"每天可多次"的计划当天打了多次。

class Record {
  final int? id;
  final int planId; // 所属计划 ID
  final String date; // 打卡日期 yyyy-MM-dd（本地日期）
  final String? note; // 备注
  final int count; // 当天打卡次数（最少 1）
  final String createdAt; // 创建时间 yyyy-MM-dd HH:mm

  const Record({
    this.id,
    required this.planId,
    required this.date,
    this.note,
    this.count = 1,
    this.createdAt = '',
  });

  factory Record.fromMap(Map<String, Object?> map) {
    return Record(
      id: map['id'] as int?,
      planId: map['plan_id'] as int? ?? 0,
      date: map['date'] as String? ?? '',
      note: map['note'] as String?,
      count: map['count'] as int? ?? 1,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'plan_id': planId,
      'date': date,
      'note': note,
      'count': count,
      'created_at': createdAt,
    };
  }

  Record copyWith({
    int? id,
    int? planId,
    String? date,
    String? note,
    int? count,
    String? createdAt,
  }) {
    return Record(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      date: date ?? this.date,
      note: note ?? this.note,
      count: count ?? this.count,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}