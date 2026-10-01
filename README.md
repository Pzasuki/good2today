# 打卡记录（Daily Log）

一款纯本地的习惯打卡 App：创建计划、每天打卡、用日历回看与补卡、用统计追踪连续与目标完成情况。无需注册登录，所有数据只保存在手机本地。

基于 Flutter 构建，Material 3 设计，支持深色模式与多套主题配色，界面为中文。

## 功能

### 今日打卡
- 首页只显示今天需要打卡的计划（按重复规则过滤），顶部圆环显示当日完成率。
- 点卡片即打卡，再点取消；开启"每天可打卡多次"的计划点按累加次数，可用 − 按钮减一次。
- 卡片上直接展示目标进度（如"本月 3/12 天"）或连续打卡天数。
- 长按进入编辑，左滑删除（软删除，历史记录保留）。

### 计划与目标
- 重复规则三种：**每天**、**每周固定几天**、**不固定**（任何一天都可打，适合搭配周期目标）。
- 可设置提醒时间（仅作记录展示，不弹系统通知）、计划颜色（预设色板 + HSV 自定义调色）与图标（12 种）。
- 目标两种类型，计数单位可选"按天 / 按次"：
  - **周期目标**：每周 / 每月 / 每年至少 N 天（或 N 次）；
  - **总量目标**：总共完成 N，可选截止日期。
- "每天可打卡多次"与"按次计"目标配合，适合一天多组的训练类计划。

### 日历
- 月视图，有打卡的日期用该天各计划的颜色画饼图填充，一眼看出哪天打了、打了几个。
- 点任意日期查看当天计划明细，可直接**补打卡**、修改打卡次数、写备注（备注可以只写文字不打卡）。

### 统计
- 总览卡：本月目标达标数、最长达标连续周期、累计打卡次数。
- 各计划完成次数对比柱状图，可切换本周 / 本月。
- 详情页：目标进度环 + 历史各周期迷你条形图、连续达标明细、累计数据总览（可按计划下钻、按月分色查看）。

### 设置与数据
- 7 套主题配色，点击即全局生效；深色模式跟随系统。
- **导出**：全部数据（含已删除的计划）导出为带缩进的 JSON 文件，通过系统分享保存到微信、网盘等。
- **导入**：从 JSON 备份恢复，支持**合并**（保留现有、自动去重）或**覆盖**（清空后完全恢复，二次确认）。导入在单个事务内完成并逐条校验，无效数据会被跳过并在结果中提示。

## 技术栈

| 类别 | 选型 |
|------|------|
| 框架 | Flutter（Dart 3，Material 3） |
| 状态管理 | provider（`AppState` 全局 `ChangeNotifier`） |
| 本地存储 | sqflite（SQLite，应用私有目录） |
| 日历 | table_calendar |
| 图表 | fl_chart |
| 其他 | intl（zh_CN 日期格式化）、share_plus（导出分享）、file_picker（导入选文件） |

## 项目结构

```
lib/
├── main.dart                  # 入口：Provider 注入、Material 3 主题（按主题 key 缓存）
├── db/
│   ├── app_state.dart         # 全局状态：数据缓存 + 派生索引 + 业务逻辑（打卡/统计/导入导出）
│   └── database_helper.dart   # SQLite 单例：建表/迁移、单记录原子操作、事务化导入
├── models/
│   ├── plan.dart              # 计划（名称/颜色/图标/重复规则/每天多次/提醒时间）
│   ├── goal.dart              # 目标（周期目标 / 总量目标，按天或按次计）
│   └── record.dart            # 打卡记录（某计划某天一条，count 为当日次数，可带备注）
├── pages/
│   ├── home_shell.dart        # 底部玻璃导航栏 + PageView（四页状态保持）
│   ├── today_page.dart        # 今日打卡
│   ├── calendar_page.dart     # 日历（月视图、补卡、备注）
│   ├── stats_page.dart        # 统计总览 + 对比图
│   ├── stats_detail_pages.dart# 目标历史 / 达标连续 / 累计数据三个详情页
│   ├── plan_edit_page.dart    # 计划编辑（颜色/图标/规则/目标，浮动气泡校验）
│   ├── plan_manage_page.dart  # 计划管理
│   ├── settings_page.dart     # 设置（主题、入口）
│   └── export_import_page.dart# 导入导出
├── widgets/
│   ├── habit_card.dart        # 打卡卡片
│   └── progress_bar.dart      # 进度条
└── utils/
    ├── app_themes.dart        # 主题配色预设
    ├── date_utils.dart        # 日期工具（本地 yyyy-MM-dd 主键、周期区间）
    └── icon_map.dart          # 图标 key → IconData 映射
```

## 数据设计

数据库 `daily_log.db` 共 4 张表（当前版本 5）：

- **plan** 计划表：重复规则（daily / weekly / flex，weekly 存"1,3,5"式星期串）、颜色 ARGB、图标 key、每天多次开关、提醒时间、`archived` 软删除标记。
- **goal** 目标表：每个计划一条。`frequency`（周期 + 数量）或 `total`（数量 + 可选截止日）；`unit` 为 day / time。
- **record** 打卡记录表：`UNIQUE(plan_id, date)`，同一天同计划最多一条；`count` 记录当日打卡次数；`count = 0` 表示**纯备注记录**（写了备注但当天未打卡，不计入完成数与连续天数）。
- **settings** 键值表：主题色等配置。

几个约定：

- 日期统一用**本地时区**的 `yyyy-MM-dd` 字符串作主键与比较，避免时区/跨天问题。
- 删除计划是软删除（`archived = 1`），历史记录保留。
- `AppState` 在内存中持有全部数据并维护按计划/按日期的派生索引：打卡等高频操作走数据库**事务内原子读写**后只同步内存缓存，不再全量刷新；导入导出、计划编辑等低频操作才整体 reload。

## 备份文件格式

导出的 JSON 大致如下（两空格缩进，按稳定顺序排列，可直接阅读与 diff）：

```json
{
  "app": "daily_log",
  "formatVersion": 1,
  "exportedAt": "2026-10-01 12:00",
  "plans":   [ { "id": 1, "name": "晨跑", "color": 4283215696, "...": "..." } ],
  "goals":   [ { "plan_id": 1, "type": "frequency", "period": "month", "total_times": 12 } ],
  "records": [ { "plan_id": 1, "date": "2026-10-01", "count": 1, "note": null, "created_at": "2026-10-01 08:30" } ]
}
```

导入时：计划按 id 去重、目标按所属计划去重、记录按 (plan_id, date) 去重；`planId` 指向不存在计划的孤儿数据、非法日期与负次数会被跳过。

## 开发与构建

环境要求：Flutter SDK（Dart `^3.13.4`）、Android 工具链。Android 侧 `compileSdk` 固定为 36（file_picker 的传递依赖要求），包名 `com.pzasuki.goodtoday`。

```bash
flutter pub get          # 拉取依赖
flutter run              # 连接设备/模拟器调试运行
flutter analyze          # 静态检查
flutter test             # 单元/组件测试
```

打包 release 安装包：

```bash
flutter build apk --release              # 通用 APK
flutter build apk --release --split-per-abi   # 按 CPU 架构拆分（体积更小，手机装 arm64 包即可）
```

产物位于 `build/app/outputs/flutter-apk/`：

- `app-release.apk` — 通用包
- `app-arm64-v8a-release.apk` — arm64 拆分包（近几年的手机用这个）

安装到已连接的设备：`flutter install --release` 或 `adb install -r <apk 路径>`。

版本号统一在 `pubspec.yaml` 的 `version` 字段维护，构建时自动打入安装包。

## License

[MIT](LICENSE) © 2026 Pzasuki
