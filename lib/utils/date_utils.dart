// 日期工具：统一用本地日期字符串 yyyy-MM-dd 作主键，避免时区导致跨天错误。
import 'package:intl/intl.dart';

class DateUtils {
  // 日期格式化器，用于生成 yyyy-MM-dd 字符串（本地时区）
  static final DateFormat _format = DateFormat('yyyy-MM-dd');

  // 把 DateTime 转成本地日期字符串，如 2026-09-29
  static String toKey(DateTime d) => _format.format(d);

  // 把日期字符串解析回本地 DateTime（当天 00:00）
  static DateTime parse(String key) => _format.parseStrict(key);

  // 今天的本地日期字符串
  static String today() => toKey(DateTime.now());

  // 把日期加减 n 天，返回新 DateTime
  static DateTime addDays(DateTime d, int n) => d.add(Duration(days: n));

  // 某天是星期几（ISO：周一=1..周日=7）
  static int weekday(DateTime d) => d.weekday;

  // 某天是否在给定星期集合中（weekdays 存 1..7）
  static bool inWeekdays(DateTime d, Set<int> weekdays) =>
      weekdays.contains(d.weekday);

  // 把普通日期时间戳转成仅日期部分（当天 00:00），用于比较
  static DateTime dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  // 返回包含 now 的周期区间（起、止），period = week / month / year
  // 用于统计"本周/本月/今年"的打卡次数
  static (DateTime, DateTime) periodRange(String period, DateTime now) {
    switch (period) {
      case 'week':
        // 周一为一周开始
        final monday = dateOnly(addDays(now, -(now.weekday - 1)));
        return (monday, addDays(monday, 6));
      case 'year':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
      default: // month
        // 下月 0 号 = 本月最后一天
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0)
        );
    }
  }
}