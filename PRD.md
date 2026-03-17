# CrewMan 产品需求文档 (PRD)

**版本:** 1.0  
**日期:** 2026-03-17  
**状态:** 规划中  
**项目:** CrewMan - Zig 编写的 CLI 任务管理工具

---

## 1. 产品概述

### 1.1 产品定位

CrewMan 是一个轻量级的命令行任务管理工具，专为个人开发者和小型团队设计。它采用 Zig 语言编写，使用 SQLite 作为本地数据存储，提供快速、简洁的任务管理体验。

### 1.2 核心价值

- **轻量高效**: 基于 Zig 语言开发，执行效率高，资源占用低
- **本地优先**: 所有数据存储在本地 SQLite 数据库，无云端依赖，保护隐私
- **简洁 CLI**: 直观的命令行界面，快速上手
- **团队协作**: 支持成员 (crew) 管理，任务分配，跟踪进度
- **看板视图**: 可视化项目进度，清晰了解任务状态

### 1.3 目标用户

- 个人开发者
- 小型开发团队 (2-10 人)
- 喜欢 CLI 工具的技术人员
- 需要轻量级任务管理方案的团队

---

## 2. 用户故事

### 2.1 场景一：个人任务管理

作为个人用户，我希望能：
- 创建多个独立的项目来分类管理任务
- 为每个项目添加任务，设置优先级
- 查看任务列表，了解当前待办事项
- 更新任务状态（待处理 → 进行中 → 已完成）
- 查看项目进度统计

### 2.2 场景二：团队协作

作为团队负责人，我希望能：
- 添加团队成员（Crew），指定成员类型（如：开发者、设计师、测试工程师）
- 将任务分配给特定成员
- 查看所有成员的任务分配情况
- 追踪项目整体进度

### 2.3 场景三：进度可视化

作为项目经理，我希望能：
- 通过看板视图查看各项目进度
- 查看任务统计数据（总数、完成数、进行中数）
- 了解各项目的完成百分比

---

## 3. 功能需求

### 3.1 项目管理 (Project)

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 创建项目 | 使用 `project init <name> [-d <description>]` 创建新项目 | ✅ 已实现 | P0 |
| 列出项目 | 使用 `project list` 或 `project ls` 列出所有项目 | ✅ 已实现 | P0 |
| 删除项目 | 使用 `project delete <id>` 或 `project rm <id>` 删除项目（级联删除任务） | ✅ 已实现 | P0 |
| 项目描述 | 创建项目时可添加描述 | ✅ 已实现 | P1 |
| 项目编辑 | 编辑项目名称和描述 | 🔄 规划中 | P2 |
| 项目切换 | 设置当前活跃项目 | 🔄 规划中 | P2 |
| 项目导出 | 导出项目数据为 JSON/CSV | 🔄 规划中 | P3 |

**命令行示例：**

```bash
# 创建项目
crewman project init "Website Redesign" -d "Redesign company website"

# 列出项目
crewman project list

# 删除项目
crewman project delete 1
```

### 3.2 任务管理 (Task)

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 创建任务 | 使用 `task add <title> [-p <project_id>] [-d <description>] [-P <priority>]` 创建任务 | ✅ 已实现 | P0 |
| 列出任务 | 使用 `task list [project_id]` 列出任务 | ✅ 已实现 | P0 |
| 更新状态 | 使用 `task move <id> <status>` 更新任务状态 | ✅ 已实现 | P0 |
| 删除任务 | 使用 `task delete <id>` 删除任务 | ✅ 已实现 | P0 |
| 分配成员 | 使用 `task assign <task_id> <crew_id>` 分配任务给成员 | ✅ 已实现 | P0 |
| 任务优先级 | 支持 0-3 级优先级（低、中、高、紧急） | ✅ 已实现 | P1 |
| 任务描述 | 创建任务时可添加详细描述 | ✅ 已实现 | P1 |
| 编辑任务 | 编辑任务标题、描述、优先级 | 🔄 规划中 | P2 |
| 任务标签 | 为任务添加标签 | 🔄 规划中 | P2 |
| 任务截止日 | 设置任务截止日期 | 🔄 规划中 | P2 |
| 批量操作 | 批量更新任务状态 | 🔄 规划中 | P3 |
| 任务搜索 | 按关键词搜索任务 | 🔄 规划中 | P3 |

**任务状态：**

- `pending` - 待处理
- `in_progress` - 进行中
- `done` - 已完成
- `cancelled` - 已取消

**优先级级别：**

- 0: 🔵 Low (低)
- 1: 🟡 Medium (中)
- 2: 🟠 High (高)
- 3: 🔴 Urgent (紧急)

**命令行示例：**

```bash
# 添加任务
crewman task add "Design homepage mockup" -p 1 -d "Create initial design" -P 2

# 列出所有任务
crewman task list

# 列出指定项目任务
crewman task list 1

# 更新任务状态
crewman task move 1 in_progress

# 删除任务
crewman task delete 1

# 分配任务给成员
crewman task assign 1 2
```

### 3.3 成员管理 (Crew)

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 添加成员 | 使用 `crew add <name> <type> [-d <description>]` 添加成员 | ✅ 已实现 | P0 |
| 列出成员 | 使用 `crew list` 或 `crew ls` 列出所有成员 | ✅ 已实现 | P0 |
| 删除成员 | 使用 `crew delete <id>` 删除成员（自动解除任务分配） | ✅ 已实现 | P0 |
| 成员类型 | 支持不同类型的成员（开发者、设计师、测试等） | ✅ 已实现 | P1 |
| 编辑成员 | 编辑成员信息 | 🔄 规划中 | P2 |
| 成员头像 | 为成员设置头像/头像 URL | 🔄 规划中 | P3 |
| 成员角色 | 扩展角色系统 | 🔄 规划中 | P3 |

**命令行示例：**

```bash
# 添加成员
crewman crew add "Alice" "developer" -d "Backend specialist"

# 列出成员
crewman crew list

# 删除成员
crewman crew delete 1
```

### 3.4 看板视图 (Board)

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 进度看板 | 使用 `board` 命令显示各项目进度 | ✅ 已实现 | P0 |
| 项目统计 | 显示每个项目的总任务数、已完成数、进行中数 | ✅ 已实现 | P0 |
| 进度条 | 可视化显示项目完成进度 | ✅ 已实现 | P1 |
| 详细看板 | 按状态分组显示任务 | 🔄 规划中 | P2 |
| 成员看板 | 按成员查看任务分配情况 | 🔄 规划中 | P2 |
| 拖拽移动 | TUI 界面中拖拽移动任务 | 🔄 规划中 | P3 |

**命令行示例：**

```bash
# 查看看板
crewman board
```

**输出示例：**

```
📊 Progress Board
────────────────────────────────────────────────────────────
Project              Total  Done  In Progress  Progress
────────────────────────────────────────────────────────────
Website Redesign      10     4         3      [███░░░░░░░░░░░░░░] 40%
Mobile App            15     8         5      [████████░░░░░░░░░] 53%
```

### 3.5 统计功能 (Stats)

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 全局统计 | 使用 `stats` 命令显示全局统计数据 | ✅ 已实现 | P0 |
| 项目统计 | 按项目统计任务数量 | ✅ 已实现 | P0 |
| 状态分布 | 按状态统计任务数量 | ✅ 已实现 | P1 |
| 成员统计 | 统计成员任务分配情况 | 🔄 规划中 | P2 |
| 时间统计 | 按时间段统计任务完成情况 | 🔄 规划中 | P3 |
| 效率分析 | 团队效率分析报告 | 🔄 规划中 | P3 |

**命令行示例：**

```bash
# 查看统计
crewman stats
```

**输出示例：**

```
📈 Statistics

  📁 Projects:     3
  📋 Tasks:       25
    ⭕ Pending:     8
    🔄 In Progress: 12
    ✅ Done:        5
    ❌ Cancelled:   0
  🤖 Crews:       4
```

### 3.6 未来规划功能

| 功能 | 描述 | 状态 | 优先级 |
|------|------|------|--------|
| 子任务 | 支持创建子任务 | 🔄 规划中 | P2 |
| 任务评论 | 为任务添加评论 | 🔄 规划中 | P2 |
| 依赖关系 | 任务间依赖管理 | 🔄 规划中 | P2 |
| 周期性任务 | 创建重复性任务 | 🔄 规划中 | P3 |
| 提醒通知 | 任务截止提醒 | 🔄 规划中 | P3 |
| 数据同步 | 云端同步（可选） | 🔄 规划中 | P3 |
| TUI 界面 | 交互式终端用户界面 | 🔄 规划中 | P3 |
| 插件系统 | 支持插件扩展 | 🔄 规划中 | P3 |

---

## 4. 技术架构

### 4.1 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| 编程语言 | **Zig** | 系统级编程语言，高性能、低依赖 |
| 数据库 | **SQLite** | 嵌入式关系型数据库，本地存储 |
| 构建工具 | **Zig Build** | Zig 内置构建系统 |
| C 绑定 | **libsqlite3** | SQLite C 库绑定 |

### 4.2 架构设计

```
┌─────────────────────────────────────────────┐
│                CLI Layer                    │
│         (commands.zig / main.zig)           │
├─────────────────────────────────────────────┤
│              Business Logic                 │
│              (models.zig)                    │
├─────────────────────────────────────────────┤
│               Data Layer                     │
│                (db.zig)                      │
├─────────────────────────────────────────────┤
│             SQLite Database                  │
│            (.crewman.db)                     │
└─────────────────────────────────────────────┘
```

### 4.3 数据库结构

```sql
-- 项目表
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 任务表
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    status TEXT DEFAULT 'pending',
    priority INTEGER DEFAULT 0,
    project_id INTEGER,
    crew_id INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
);

-- 成员表
CREATE TABLE IF NOT EXISTS crews (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    description TEXT DEFAULT '',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### 4.4 模块说明

| 文件 | 职责 |
|------|------|
| `main.zig` | 程序入口，命令行参数解析，命令路由 |
| `commands.zig` | 各命令的具体实现逻辑 |
| `models.zig` | 数据模型定义（Project、Task、Crew、TaskStatus、Priority） |
| `db.zig` | 数据库初始化、连接管理、SQL 语句执行 |

### 4.5 命令行接口设计

```
crewman <command> [subcommand] [options]

Commands:
  project  - 项目管理
  task     - 任务管理
  crew     - 成员管理
  board    - 看板视图
  stats    - 统计数据
  help     - 帮助信息
```

---

## 5. 非功能需求

### 5.1 性能需求

- **启动时间**: 程序启动时间应小于 100ms
- **响应速度**: 命令执行响应时间应小于 200ms
- **数据库查询**: 单次查询时间应小于 50ms（10,000 条记录以内）
- **内存占用**: 正常运行内存占用应小于 50MB

### 5.2 可用性需求

- **跨平台**: 支持 Linux、macOS、Windows
- **零配置**: 开箱即用，无需额外配置
- **错误处理**: 清晰的错误提示信息
- **用户反馈**: 操作成功/失败有明显反馈

### 5.3 数据安全

- **本地存储**: 数据完全存储在本地，不上传云端
- **隐私保护**: 无需网络连接，保护用户隐私
- **数据备份**: 支持数据库文件手动备份
- **级联删除**: 删除项目时自动清理相关任务

### 5.4 可扩展性

- **模块化设计**: 各功能模块解耦，便于扩展
- **配置化**: 支持配置文件自定义设置
- **插件预留**: 预留插件系统接口（未来规划）

### 5.5 兼容性

- **SQLite 版本**: 兼容 SQLite 3.x
- **Zig 版本**: 兼容 Zig 0.11.x 及以上
- **操作系统**: Linux (glibc/musl)、macOS、Windows

---

## 6. 里程碑规划

### 6.1 版本路线图

```
v1.0.0 (MVP)
├── 项目管理（创建、列表、删除）
├── 任务管理（创建、列表、更新状态、删除、分配）
├── 成员管理（创建、列表、删除）
├── 看板视图（项目进度）
├── 统计数据（全局统计）
└── 基础帮助文档
```

```
v1.1.0 (Enhancement)
├── 任务优先级增强
├── 任务描述支持
├── 成员类型增强
├── 进度条可视化
├── 项目描述
└── 命令行帮助完善
```

```
v1.2.0 (TUI)
├── 交互式 TUI 界面
├── 看板视图增强（按状态分组）
├── 任务拖拽移动
├── 成员任务视图
└── 搜索功能
```

```
v2.0.0 (Collaboration)
├── 子任务支持
├── 任务评论
├── 任务依赖
├── 周期性任务
├── 标签系统
└── 截止日期提醒
```

```
v2.1.0 (Ecosystem)
├── 数据导出（JSON/CSV）
├── 数据导入
├── 插件系统
├── 主题定制
├── 云端同步（可选）
└── 效率分析报告
```

### 6.2 发布计划

| 版本 | 目标 | 预计时间 |
|------|------|----------|
| v1.0.0 | MVP 版本，核心功能可用 | 2026 Q2 |
| v1.1.0 | 增强版本用户体验 | 2026 Q3 |
| v1.2.0 | TUI 交互界面 | 2026 Q4 |
| v2.0.0 | 协作功能增强 | 2027 Q1 |
| v2.1.0 | 生态扩展 | 2027 Q2 |

---

## 7. 附录

### 7.1 安装说明

```bash
# 克隆项目
git clone https://github.com/yourusername/crewman-zig.git
cd crewman-zig

# 构建
zig build

# 运行
./zig-out/bin/crewman
```

### 7.2 快速开始

```bash
# 1. 创建项目
crewman project init "My Project"

# 2. 添加成员
crewman crew add "Alice" "developer"
crewman crew add "Bob" "designer"

# 3. 添加任务
crewman task add "Design mockup" -p 1 -P 2
crewman task add "Write code" -p 1 -P 1

# 4. 分配任务
crewman task assign 1 1  # 分配给 Alice

# 5. 查看进度
crewman board
crewman stats

# 6. 更新状态
crewman task move 1 done
```

### 7.3 数据位置

- 数据库文件: `.crewman.db`（当前工作目录）
- 缓存目录: `.zig-cache/`

### 7.4 参考资料

- Zig 语言官方文档: https://ziglang.org/
- SQLite 文档: https://www.sqlite.org/docs.html

---

**文档版本历史**

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| 1.0 | 2026-03-17 | 初始版本 |

---

*本文档为 CrewMan 产品需求文档，定义了产品的功能、技术和规划方向。*
