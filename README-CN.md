# crewman-zig

[English README](README.md)

`crewman-zig` 是一个本地优先的 CLI 任务管理工具，使用 Zig 编写，并以 SQLite 作为底层存储。

## 当前状态

这个仓库现在已经具备可用的 MVP CLI。

- CLI 可以稳定构建，主要的 CRUD 和工作流命令已经实现。
- 程序启动时会自动创建并升级本地 SQLite schema。
- 已实现的命令包括：`project init`、`project list`、`project delete`、`task add`、`task list`、`task move`、`task delete`、`task assign`、`task depend`、`task deps`、`task run`、`crew add`、`crew list`、`crew delete`、`agent add`、`agent list`、`agent delete`、`board` 和 `stats`。
- `task run` 当前会把生成的任务 prompt 作为配置好的 agent 命令的最后一个参数传入，并将采集到的 `stdout` / `stderr` 存入 `agent_runs`。

核心表包括：

- `projects(id, name, description, created_at)`
- `tasks(id, title, description, status, priority, project_id, crew_id, created_at)`
- `crews(id, name, type, description, created_at)`
- `agents(...)` 以及后续功能使用的 run / skill 相关表

## 环境要求

- 推荐使用 Zig 0.15.x
- 本地需要可用的系统 `sqlite3` 库

## 构建与运行

```bash
zig build
./zig-out/bin/crewman help
./zig-out/bin/crewman project init demo -d "Demo project"
./zig-out/bin/crewman task add "Implement parser" -p 1 -P 2
./zig-out/bin/crewman stats
```

运行完整测试套件：

```bash
zig build test
```

你仍然可以直接运行原始 Zig 测试目标：

```bash
zig test src/root.zig
```

但标准入口应当使用 `zig build test`。

## 代码结构

- `src/main.zig`：CLI 入口和命令分发
- `src/commands.zig`：命令处理逻辑和终端输出
- `src/db.zig`：SQLite 连接、初始化和迁移辅助逻辑
- `src/integration_test.zig`：基于临时 SQLite 数据库的端到端测试
- `src/models.zig`：共享枚举和数据结构
- `src/root.zig`：测试入口，会导入集成测试
- `build.zig`：可执行文件和测试的构建定义
- `PRD.md`：产品需求与规划文档

## 测试说明

集成测试会直接调用真实命令函数，并使用临时数据库文件，而不是仓库根目录下的 `.crewman.db`。当前覆盖范围包括：

- 项目创建
- 任务创建、状态更新和分配
- 依赖创建与循环依赖拦截
- agent 创建与 `task run`
- 对任务、agent、运行记录和技能表的 SQLite 持久化结果校验

如果你新增了 CLI 功能，优先扩展 `src/integration_test.zig`，直接校验最终数据库状态。

## 开发说明

- 提交前执行 `zig fmt src/*.zig build.zig`
- 忽略 `zig-out/`、`.zig-cache/` 和本地 `.crewman.db` 这类生成文件
- CLI 行为和 schema 变更必须保持一致；当前 `db.init()` 是增量表结构和列迁移的入口
- 测试必须通过 `db.setPath(...)` 或等价方式使用隔离数据库，不能复用仓库根目录下的 `.crewman.db`
