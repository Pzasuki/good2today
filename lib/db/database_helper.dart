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

  // ============ 打卡记录 CRUD ============

  Future<List<Record>> getRecords() async {
    final db = await database;
    final rows = await db.query('record');
    return rows.map(Record.fromMap).toList();
  }

  // 查询某天的所有打卡记录
  Future<List<Record>> getRecordsByDate(String date) async {
    final db = await database;
    final rows = await db.query('record', where: 'date = ?', whereArgs: [date]);
    return rows.map(Record.fromMap).toList();
  }

  // 查询某计划的所有打卡记录
  Future<List<Record>> getRecordsByPlan(int planId) async {
    final db = await database;
    final rows = await db.query('record', where: 'plan_id = ?', whereArgs: [planId]);
    return rows.map(Record.fromMap).toList();
  }

  // 查询某个计划某天是否有记录
  Future<Record?> getRecord(int planId, String date) async {
    final db = await database;
    final rows = await db.query('record',
        where: 'plan_id = ? AND date = ?', whereArgs: [planId, date], limit: 1);
    if (rows.isEmpty) return null;
    return Record.fromMap(rows.first);
  }

  // 新增打卡记录
  Future<int> insertRecord(Record record) async {
    final db = await database;
    return db.insert('record', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 更新记录（如修改备注）
  Future<void> updateRecord(Record record) async {
    final db = await database;
    await db.update('record', record.toMap(), where: 'id = ?', whereArgs: [record.id]);
  }

  // 删除打卡记录
  Future<void> deleteRecord(int id) async {
    final db = await database;
    await db.delete('record', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 导入 / 导出支持 ============

  // 查询所有计划（含已归档，导出用）
  Future<List<Plan>> getAllPlans() async {
    final db = await database;
    final rows = await db.query('plan', orderBy: 'id ASC');
    return rows.map(Plan.fromMap).toList();
  }

  // 清空所有表（覆盖导入前调用）
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('record');
    await db.delete('goal');
    await db.delete('plan');
  }

  // 某计划是否已存在（合并导入去重用）
  Future<bool> planExists(int id) async {
    final db = await database;
    final rows =
        await db.query('plan', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  // 某计划是否已有目标
  Future<bool> goalExistsForPlan(int planId) async {
    final db = await database;
    final rows = await db
        .query('goal', where: 'plan_id = ?', whereArgs: [planId], limit: 1);
    return rows.isNotEmpty;
  }

  // 插入打卡记录；若同计划同日期已存在则跳过，返回新 id 或 null
  Future<int?> insertRecordIfAbsent(Record record) async {
    final db = await database;
    return db.insert('record', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
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