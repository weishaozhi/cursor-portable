---
name: new-machine-bootstrap
version: 1.0.0
created: 2026-10-06
last_used: 2026-10-06
usage_count: 0
tags: [workflow, bootstrap, setup-script, new-machine, deployment, graceful-degradation]
scope: project
overlap_with: [port-config-audit, process-tree-cleanup]
---

# new-machine-bootstrap

让项目能"克隆下来即可跑"——为 `d:\ai\projects\*` 下每个项目创建统一的 `setup.ps1`，并修正硬崩溃式启动使其优雅降级。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："新机器怎么跑"、"setup 脚本"、"一键启动"、"bootstrap"
- 用户引用 `setup.ps1` 或要求创建项目级 setup 脚本
- 需要让项目从 git clone 状态直接可运行
- `toolbox_hub` 的兄弟项目缺一个时 hub 启动崩溃（应当优雅降级）

## 核心问题

**新机器部署 4 大阻塞**（2026-10-06 对话 cbda31af 识别）：

### 阻塞 1：本地改动未推送 GitHub

```
git status:
  8 commits ahead of origin
  8 files uncommitted
  2 untracked files (e.g. launchers/tts_mvp.py)
```

→ 新机器 clone 下来丢失 force-stop、tts_mvp 配置等。

### 阻塞 2：兄弟项目不在 Git 上

```
auto_clicker/      → 有 remote
ciallo/            → 有 remote，但 24 文件未提交
md_editor/         → 有 remote
find_location/     → 有 remote
video_summarizer/  → git 仓库但没有 origin
video-subtitle-remover/  → 不是 git 仓库（GitHub API 拉的）
webm2mp4/          → 不是 git 仓库
```

→ 至少 2 个项目无法通过 git 获取。

### 阻塞 3：load_tools() 硬崩溃（最优先修复）

```python
# toolbox_hub/service_manager.py:80-82
working_dir = (base_dir / str(item["working_dir"])).resolve()
if not working_dir.is_dir():
    raise ConfigError(f"工具 {tool_id} 的工作目录不存在: {working_dir}")
```

main.py 在 `create_app()` 中调用，无 try/except。**任何一个**兄弟目录缺失，整个 hub 崩溃，不是降级部分可用。

### 阻塞 4：requirements.txt 太窄

hub 自身只有 3 个包（Flask / pytest / PyYAML），但 spawn 子进程时使用 **hub 的 Python 解释器**（`sys.executable`）。意味着 md_editor / ciallo / video_summarizer 后端的 Python 依赖（uvicorn 等）必须装到 hub 的 venv。

## 标准解法

### 步骤 1：修复 load_tools() 优雅降级

```python
# toolbox_hub/service_manager.py
working_dir = (base_dir / str(item["working_dir"])).resolve()
if not working_dir.is_dir():
    # 不抛异常，标记为不可用
    self._mark_tool_unavailable(tool_id, reason=f"工作目录不存在: {working_dir}")
    return  # 跳过该工具

# 同时 main.py 加 try/except 包裹 create_app 启动期
try:
    load_tools()
except ConfigError as e:
    logger.warning(f"部分工具加载失败: {e}")
    # 继续启动，标记为 unavailable
```

**效果**：缺失 1 个工具 → hub 启动，UI 显示该工具为灰色"不可用"。

### 步骤 2：为每个项目创建 setup.ps1

**统一接口**（5 个项目都遵循）：

```powershell
.\setup.ps1                  # 标准 bootstrap（创建 venv + 装依赖）
.\setup.ps1 -Reinstall       # 强制重建 venv
.\setup.ps1 -DryRun          # 预览操作，不实际执行
.\setup.ps1 -Help            # 显示用法
```

**项目特定 flag**：

| 项目 | 特殊 flag |
|------|----------|
| auto_clicker | (标准) |
| find_location | `-WithDev`（装 pytest） |
| md_editor | `-SkipFrontend`、`-Reinstall` |
| tts-mvp | (Vite + tsx) |
| ciallo | (Python + Node) |
| toolbox_hub | `-SkipVSR`、`-SkipClone`、`-UseMirror` |

### 步骤 3：setup.ps1 标准结构

```powershell
<#
.SYNOPSIS
    <项目名>一键启动脚本（Windows）

.DESCRIPTION
    1. 创建 .venv
    2. 安装 requirements.txt
    3. (Node 项目) 运行 npm install
    4. 复制 .env.example → .env（如不存在）

.PARAMETER Reinstall
    强制删除并重建 .venv

.PARAMETER DryRun
    预览操作，不实际执行

.PARAMETER Help
    显示此帮助

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Reinstall
#>
[CmdletBinding()]
param(
    [switch]$Reinstall,
    [switch]$DryRun,
    [switch]$Help,
    [switch]$SkipFrontend,
    [switch]$WithDev,
    [switch]$SkipClone,
    [switch]$SkipVSR,
    [switch]$UseMirror
)

if ($Help) { Get-Help $MyInvocation.MyCommand.Path; return }

# 检测 Python / Node 版本
$pythonVer = (& python --version) 2>$null
$nodeVer = (& node --version) 2>$null

# DryRun 模式
if ($DryRun) {
    Write-Host "[DryRun] 将执行的操作："
    Write-Host "  1. 创建 .venv"
    Write-Host "  2. python -m pip install -r requirements.txt"
    Write-Host "  3. ... (项目特定)"
    return
}

# Reinstall 模式
if ($Reinstall -and (Test-Path .venv)) {
    Remove-Item -Recurse -Force .venv
}

# 标准流程
if (-not (Test-Path .venv)) {
    python -m venv .venv
}
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt

if (Test-Path requirements-dev.txt) {
    if ($WithDev) {
        pip install -r requirements-dev.txt
    }
}

if (Test-Path package.json) {
    if (-not $SkipFrontend) {
        npm install
    }
}

if ((Test-Path .env.example) -and -not (Test-Path .env)) {
    Copy-Item .env.example .env
    Write-Host "已创建 .env（从 .env.example）"
}

Write-Host "[完成] 运行：.\.venv\Scripts\Activate.ps1; <启动命令>"
```

### 步骤 4：README 添加 Quick Start

每个项目 README 顶部加：

```markdown
> **TL;DR / Quick Start (Windows)**
>
> ```powershell
> .\setup.ps1
> ```
>
> Creates `.venv` at repo root and installs all Python deps. Use `.\setup.ps1 -Reinstall`
> to force a fresh venv, `-DryRun` to preview, `-Help` for all options.
```

## 实际案例

### 案例 1：toolbox_hub 5 项目 bootstrap（2026-10-06，对话 cbda31af）

**任务**：让 5 个项目（auto_clicker / find_location / md_editor / tts-mvp / ciallo）能"克隆即跑"。

**实施**：

1. 读取每个项目的 `requirements.txt` / `package.json` / `.gitignore` / `.env.example`
2. 为每个项目生成符合统一接口的 `setup.ps1`
3. 5 个 `setup.ps1` dry-run 全部通过：
   - Python 3.14.7 检测 ✓
   - Node 24.18.0 检测 ✓
   - venv 位置正确 ✓
   - 已有 venv 时跳过 ✓

4. 修改 `load_tools()` 优雅降级（不再硬崩溃）
5. 添加 4 个 README callout（auto_clicker / find_location / md_editor / toolbox_hub）

**结果**：新机器 clone 后只需：

```powershell
git clone https://github.com/user/auto_clicker.git
cd auto_clicker
.\setup.ps1
.\.venv\Scripts\python.exe app.py
```

### 案例 2：toolbox_hub 优雅降级修复

**问题**：`load_tools()` 在缺失 working_dir 时抛 ConfigError，main.py 没有 try/except，导致 hub 完全无法启动。

**修复**：

```python
# service_manager.py 改为
working_dir = (base_dir / str(item["working_dir"])).resolve()
if not working_dir.is_dir():
    self._mark_tool_unavailable(tool_id, reason=f"工作目录不存在: {working_dir}")
    continue  # 跳过该工具，不抛异常

# main.py 加保护
def create_app():
    try:
        load_tools()
    except ConfigError as e:
        logger.warning(f"部分工具加载失败，已降级: {e}")
    # 继续构建 app
    ...
```

**效果**：缺失 7 个兄弟目录中的任意 1-6 个，hub 仍可启动，该工具标记为"不可用"。

## 注意事项

### 必须遵守

- **强制** setup.ps1 必须支持 `-DryRun`、`-Help` flag
- **强制** setup.ps1 检测已有 .venv 时不重建（除非 `-Reinstall`）
- **强制** README 添加 Quick Start callout
- **强制** 服务发现 / 加载机制使用优雅降级而非抛异常
- **禁止** setup.ps1 默认做破坏性操作（rm -rf 等）
- **禁止** 把 setup.ps1 设计成只在新机器运行（本地开发也要用）

### 推荐实践

- 每个项目的 setup.ps1 风格保持一致（统一接口）
- dry-run 模式是验收脚本的核心，所有项目都必须通过
- 项目特定 flag 加在标准 flag 之后，便于发现
- 在脚本顶部写明 requirements（Python 3.10+, Node 20+ 等）
- 启动命令统一放在脚本末尾输出
- toolbox_hub 的 README 指向其自身的 setup.ps1，而非子项目

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 不同项目 setup 脚本风格各异 | 难记忆、难维护 | 统一接口（`-Reinstall`、`-DryRun`、`-Help`） |
| setup 失败抛出未捕获异常 | 用户不知如何修复 | try/catch + 友好错误信息 |
| 把所有 setup 揉在一个脚本 | 一个失败全部失败 | 每个项目独立 |
| README 不写 Quick Start | 用户不知道有 setup.ps1 | 顶部 TL;DR 段 |
| 用 try/except 吞掉错误 | 隐藏配置问题 | 警告日志 + 标记工具不可用 |
| service_manager 任意一个错就抛 | hub 完全起不来 | 标记 unavailable + 继续 |

## 关联技能

- `port-config-audit` — 启动时端口一致性
- `process-tree-cleanup` — 启动前清理残留进程
- `project-handle-resolution` — 跨项目操作时解析 `@xxx`

## 关联规则

- `toolbox_hub\config.yaml` — hub 配置
- `toolbox_hub\tools.json` — 工具清单
- 各项目 `requirements.txt` — Python 依赖
- 各项目 `package.json` — Node 依赖
- 各项目 `.env.example` — 配置模板

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-06 | 创建技能 | cbda31af 对话：5 项目 setup.ps1 + load_tools 优雅降级 |