// 数据库帮助类：负责创建/打开 SQLite 数据库，以及所有增删改查操作。
// 使用 sqflite，数据存储于应用私有目录。

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/plan.dart';
import '../models/goal.dart';
import '../models/record.dart';

class DatabaseHelper {
  // 单例，全局共享同一个数据库连接
  static final DatabaseHelper instance = DatabaseHelper._();

  DatabaseHelper._();

  Database? _db;

  // 打开（首次创建）数据库
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // 数据库文件放在应用的私有目录
    final path = p.join(await getDatabasesPath(), 'daily_log.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 建表
  Future<void> _onCreate(Database db, int version) async {
    // 计划表
    await db.execute('''
      CREATE TABLE plan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        icon TEXT NOT NULL DEFAULT 'flag',
        repeat_type TEXT NOT NULL DEFAULT 'daily',
        repeat_days TEXT NOT NULL DEFAULT '',
        multi_per_day INTEGER NOT NULL DEFAULT 0,
        reminder_hour INTEGER,
        reminder_minute INTEGER,
        created_at TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 目标表
    await db.execute('''
      CREATE TABLE goal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'total',
        period TEXT,
        unit TEXT,
        total_times INTEGER,
        deadline_date TEXT,
        start_date TEXT NOT NULL
      )
    ''');

    // 打卡记录表（同一天同一计划一条；count 记录当天打卡次数）
    await db.execute('''
      CREATE TABLE record (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        count INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        UNIQUE(plan_id, date)
      )
    ''');

    // 键值设置表（主题颜色等）
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // 数据库版本升级：按版本号逐段追加变更
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2：goal 表新增 period 列（周期目标的周期 week/month/year）
      await db.execute('ALTER TABLE goal ADD COLUMN period TEXT');
    }
    if (oldVersion < 3) {
      // v3：goal 表新增 unit 列（计数单位：天/次）
      await db.execute('ALTER TABLE goal ADD COLUMN unit TEXT');
    }
    if (oldVersion < 4) {
      // v4：plan 支持每天多次打卡，record 记录当天次数
      await db.execute(
          'ALTER TABLE plan ADD COLUMN multi_per_day INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE record ADD COLUMN count INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 5) {
      // v5：新增设置表（主题颜色等键值配置）
      await db.execute(
          'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    }
  }

  // ============ 计划 CRUD ============

  // 查询所有未归档的计划
  Future<List<Plan>> getPlans() async {
    final db = await database;
    final rows = await db.query('plan', where: 'archived = 0', orderBy: 'id ASC');
    return rows.map(Plan.fromMap).toList();
  }

  // 新增计划，返回自增 id
  Future<int> insertPlan(Plan plan) async {
    final db = await database;
    return db.insert('plan', plan.toMap());
  }

  // 更新计划
  Future<void> updatePlan(Plan plan) async {
    final db = await database;
    await db.update('plan', plan.toMap(), where: 'id = ?', whereArgs: [plan.id]);
  }

  // 软删除计划（archived = 1），保留历史记录
  Future<void> archivePlan(int id) async {
    final db = await database;
    await db.update('plan', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ============ 目标 CRUD ============

  Future<List<Goal>> getGoals() async {
    final db = await database;
    final rows = await db.query('goal');
    return rows.map(Goal.fromMap).toList();
  }

  Future<Goal?> getGoalForPlan(int planId) async {
    final db = await database;
    final rows = await db.query('goal', where: 'plan_id = ?', whereArgs: [planId], limit: 1);
    if (rows.isEmpty) return null;
    return Goal.fromMap(rows.first);
  }

  // 新增目标
  Future<int> insertGoal(Goal goal) async {
    final db = await database;
    return db.insert('goal', goal.toMap());
  }

  Future<void> updateGoal(Goal goal) async {
    final db = await database;
    await db.update('goal', goal.toMap(), where: 'id = ?', whereArgs: [goal.id]);
  }

  Future<void> deleteGoal(int id) async {
    final db = await database;
    await db.delete('goal', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 打卡记录 ============

  // 加载全部打卡记录
  Future<List<Record>> getRecords() async {
    final db = await database;
    final rows = await db.query('record');
    return rows.map(Record.fromMap).toList();
  }

  // ---- 单记录原子操作 ----
  // 打卡是最高频操作：在事务内按 (plan_id, date) 以数据库实际状态为准，
  // 返回操作后的权威记录，供上层同步内存缓存；连点/并发也不会基于旧状态误判。

  // 普通计划打卡切换：无记录 → 插入 count=1；纯备注记录(count=0) → 置 1；
  // 已打卡 → 删除。返回操作后的记录（null = 记录已删除）。
  Future<Record?> toggleRecord(int planId, String date, String createdAt) async {
    final db = await database;
    return db.transaction<Record?>((txn) async {
      final rows = await txn.query('record',
          where: 'plan_id = ? AND date = ?', whereArgs: [planId, date], limit: 1);
      if (rows.isEmpty) {
        final rec = Record(planId: planId, date: date, count: 1, createdAt: createdAt);
        final id = await txn.insert('record', rec.toMap());
        return rec.copyWith(id: id);
      }
      final existing = Record.fromMap(rows.first);
      if (existing.count <= 0) {
        // 纯备注记录：打卡 = 计为 1，保留备注
        final updated = existing.copyWith(count: 1);
        await txn.update('record', updated.toMap(),
            where: 'id = ?', whereArgs: [existing.id]);
        return updated;
      }
      await txn.delete('record', where: 'id = ?', whereArgs: [existing.id]);
      return null;
    });
  }

  // 每天可多次的计划：次数 +1（无记录则插入 count=1）。返回最新记录。
  Future<Record> incrementRecord(int planId, String date, String createdAt) async {
    final db = await database;
    return db.transaction<Record>((txn) async {
      final changed = await txn.rawUpdate(
          'UPDATE record SET count = count + 1 WHERE plan_id = ? AND date = ?',
          [planId, date]);
      if (changed == 0) {
        await txn.insert('record', {
          'plan_id': planId,
          'date': date,
          'count': 1,
          'created_at': createdAt,
        });
      }
      final rows = await txn.query('record',
          where: 'plan_id = ? AND date = ?', whereArgs: [planId, date], limit: 1);
      return Record.fromMap(rows.first);
    });
  }

  // 次数 -1：>1 自减；=1 时有备注退成纯备注记录（count=0），无备注删除。
  // 返回操作后的记录（null = 记录已删除）。
  Future<Record?> decrementRecord(int planId, String date) async {
    final db = await database;
    return db.transaction<Record?>((txn) async {
      final rows = await txn.query('record',
          where: 'plan_id = ? AND date = ?', whereArgs: [planId, date], limit: 1);
      if (rows.isEmpty) return null;
      final existing = Record.fromMap(rows.first);
      if (existing.count > 1) {
        final updated = existing.copyWith(count: existing.count - 1);
        await txn.update('record', updated.toMap(),
            where: 'id = ?', whereArgs: [existing.id]);
        return updated;
      }
      if ((existing.note ?? '').isNotEmpty) {
        // 保留备注，退成"纯备注"记录
        final updated = existing.copyWith(count: 0);
        await txn.update('record', updated.toMap(),
            where: 'id = ?', whereArgs: [existing.id]);
        return updated;
      }
      await txn.delete('record', where: 'id = ?', whereArgs: [existing.id]);
      return null;
    });
  }

  // 设置备注：无记录且备注非空 → 插入纯备注记录（count=0，不计入打卡）；
  // 备注清空且未打卡 → 记录失去意义，删除。返回操作后的记录（null = 无记录）。
  Future<Record?> setNoteRecord(
      int planId, String date, String note, String createdAt) async {
    final db = await database;
    return db.transaction<Record?>((txn) async {
      final rows = await txn.query('record',
          where: 'plan_id = ? AND date = ?', whereArgs: [planId, date], limit: 1);
      if (rows.isEmpty) {
        if (note.isEmpty) return null;
        final rec = Record(
            planId: planId, date: date, note: note, count: 0, createdAt: createdAt);
        final id = await txn.insert('record', rec.toMap());
        return rec.copyWith(id: id);
      }
      final existing = Record.fromMap(rows.first);
      if (note.isEmpty && existing.count <= 0) {
        // 未打卡且备注清空
        await txn.delete('record', where: 'id = ?', whereArgs: [existing.id]);
        return null;
      }
      final updated = existing.copyWith(note: note);
      await txn.update('record', updated.toMap(),
          where: 'id = ?', whereArgs: [existing.id]);
      return updated;
    });
  }

  // ============ 导入 / 导出支持 ============

  // 查询所有计划（含已归档，导出用）
  Future<List<Plan>> getAllPlans() async {
    final db = await database;
    final rows = await db.query('plan', orderBy: 'id ASC');
    return rows.map(Plan.fromMap).toList();
  }

  // 整体导入：单一事务内完成清空（覆盖模式）与全部插入，保证原子性——
  // 中途失败会整体回滚，不会留下半份数据。
  // merge=true 时已存在的计划/目标跳过，记录按 (plan_id, date) 去重；
  // planId 指向不存在计划的孤儿数据一律跳过。
  // 返回 (计划数, 目标数, 记录数, 跳过的孤儿数据条数)。
  Future<(int, int, int, int)> importAll({
    required List<Plan> plans,
    required List<Goal> goals,
    required List<Record> records,
    required bool merge,
  }) async {
    final db = await database;
    return db.transaction<(int, int, int, int)>((txn) async {
      if (!merge) {
        await txn.delete('record');
        await txn.delete('goal');
        await txn.delete('plan');
      }

      var planCount = 0;
      for (final p in plans) {
        if (p.id == null) continue;
        // 已存在（库中已有，或备份内重复 id）则跳过
        final rows = await txn.query('plan',
            where: 'id = ?', whereArgs: [p.id], limit: 1);
        if (rows.isNotEmpty) continue;
        await txn.insert('plan', p.toMap());
        planCount++;
      }

      // 目标/记录必须挂在真实存在的计划上（含已归档计划）
      final validPlanIds = {
        for (final row in await txn.query('plan', columns: ['id']))
          row['id'] as int,
      };

      var goalCount = 0;
      var orphanGoals = 0;
      for (final g in goals) {
        if (!validPlanIds.contains(g.planId)) {
          orphanGoals++;
          continue;
        }
        // 同一计划只保留一个目标；不带 id 插入，由数据库自增分配
        final rows = await txn.query('goal',
            where: 'plan_id = ?', whereArgs: [g.planId], limit: 1);
        if (rows.isNotEmpty) continue;
        await txn.insert(
            'goal',
            Goal(
              planId: g.planId,
              type: g.type,
              period: g.period,
              totalTimes: g.totalTimes,
              deadlineDate: g.deadlineDate,
              startDate: g.startDate,
              unit: g.unit,
            ).toMap());
        goalCount++;
      }

      var recordCount = 0;
      var orphanRecords = 0;
      for (final r in records) {
        if (!validPlanIds.contains(r.planId)) {
          orphanRecords++;
          continue;
        }
        // 同计划同日期只保留一条；事务内先查再插，判定可靠。
        // 不带 id 插入，由数据库自增分配
        final existing = await txn.query('record',
            where: 'plan_id = ? AND date = ?',
            whereArgs: [r.planId, r.date],
            limit: 1);
        if (existing.isNotEmpty) continue;
        await txn.insert('record', Record(
          planId: r.planId,
          date: r.date,
          note: r.note,
          count: r.count,
          createdAt: r.createdAt,
        ).toMap());
        recordCount++;
      }
      return (planCount, goalCount, recordCount, orphanGoals + orphanRecords);
    });
  }

  // 读取设置项（无则返回 null）
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db
        .query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // 写入设置项（已存在则覆盖）
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}