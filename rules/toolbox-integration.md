# RULE: Toolbox Hub 工具接入规范

## 触发条件
- 新工具接入 toolbox_hub
- 修改 `tools.d/<id>.json`
- 创建或修改启动器（`launchers/<id>.py`）
- 调试工具启动/停止问题
- 改 `scripts/add_tool.py` 的 schema / CLI flag

## 架构（3 层）

```
┌─ hub (Flask, main.py + service_manager.py)
│     调度层：读 tools.d/*.json、spawn control 子进程
│
├─ control (每个工具 1 个，launchers/control_service.py)
│     进程管理层：spawn 工具本体、做 health check、force_kill
│     监听 8901-8999 的 control 端口（hub 通过 HTTP 调它）
│
└─ 工具本体（单进程 / 双进程 / GUI）
      单进程：直接 spawn（如 auto_clicker、find_location）
      双进程：通过 launchers/<id>.py 包装器拉起（如 tts_mvp / ciallo）
      GUI：直接 spawn（如 video_subtitle_remover）
```

`tools.d/<id>.json` 里有两个 argv 字段，**别搞混**：

| 字段 | 谁 spawn | 路径基准 | 例子 |
|---|---|---|---|
| `command` | hub spawn control_service.py | 相对 `hub_root` | `["python", "launchers/control_service.py", "--tool-id", <id>, "--config", "tools.d/<id>.json", "--control-port", <port>]` |
| `tool_command` | control spawn 工具本体 | 相对 `tool_working_dir` | `["python", "main.py"]` / `["python", "launchers/<id>.py"]` |

## 强制约束

### 1. 命令模式选择

**单进程工具**（如 auto_clicker / find_location）：
- `tools.d/<id>.json` 中 `tool_command` 直接指向启动脚本
- `tool_working_dir` 指向工具项目根目录
- 不需要编写 launcher

**多进程工具**（如 md_editor / ciallo，backend + frontend）：
- **必须**在 `launchers/<id>.py` 编写包装器
- `tool_command` 指向包装器（`["python", "launchers/<id>.py"]`，靠 control_service hub_dir 兜底找到）
- `tool_working_dir` 指向工具项目根目录

**GUI 工具**（如 video_subtitle_remover）：
- `tool_command` 用工具自带的 venv 解释器（`[".venv\\Scripts\\python.exe", "gui.py"]`）
- `url` 填 GitHub 主页（不是 web URL），`health_url` 填 `null`

### 2. `tools.d/<id>.json` 字段约束（schema 真相源）

| 字段 | 必填 | 约束 |
|------|------|------|
| `id` | ✅ | 全局唯一，小写 + 下划线，与项目目录名一致 |
| `name` | ✅ | UI 显示名称 |
| `description` | ✅ | 功能描述（卡片副标题） |
| `category` | ✅ | 分类（见 prd.md 已有分类） |
| `icon` | ✅ | 单字符 emoji |
| `type` | ✅ | `single_web` / `double_process` / `gui` |
| `working_dir` | ✅ | 相对 toolbox_hub 根目录，必须存在；service_manager 用作 `_resolve_command` 的 base_dir |
| `command` | ✅ | **hub spawn control_service.py 的 argv**；第二项必须是 `"launchers/control_service.py"`（相对 `hub_root`），**禁止**带 `../`（ISS-021） |
| `tool_command` | ✅ | **control spawn 工具本体的 argv**；首项 `"python"` 自动替换为当前解释器；第二项相对 `tool_working_dir` |
| `tool_working_dir` | ✅ | control 跑工具本体时的 cwd（通常与 `working_dir` 相同） |
| `url` | ✅ | 必须包含端口；**端口必须全局唯一**；GUI 工具填 GitHub 主页 |
| `health_url` | ✅（有 web 界面） | 健康检查端点（通常是 backend 的 /health）；GUI 填 `null` |
| `ports.backend` / `ports.frontend` / `ports.web` | double_process / single_web | 全局唯一；不可与现有工具冲突 |
| `ports.control` | ✅ | **必须落在 8901-8999 区间**（control 协议约定）；add_tool 自动从已有占用里挑最小空闲；越界 / 冲突 `SystemExit` |

**schema 3 同步（不可违反）**：

| 真相源 | 位置 | 同步要求 |
|---|---|---|
| argparse 定义 | `scripts/add_tool.py::build_parser` | 改字段先改这里 |
| JSON 渲染模板 | `scripts/_add_tool_templates.py::render_tool_json` | 跟 argparse 同步 |
| 文档字段表 | `docs/project/integration-checklist.md` §2 | 跟代码同步 |

**三处必须一起改**，否则后人按错表手写就会踩 ISS-021 同类 bug。

**禁止手写** `tools.d/<id>.json`：所有字段由 `python -m scripts.add_tool` 生成。`tests/test_add_tool.py` 锁定了 schema 真相，手写会被回归测试逮住。

### 3. 端口管理（单一来源原则）

**config.yaml 是工具端口（backend / frontend / web）的唯一来源**：

```yaml
<tool_id>:
  backend_port: 8000
  frontend_port: 5173
  startup_grace_seconds: 12.0
```

**约束**：
- tools.d/<id>.json 的 `url` / `health_url` 端口**必须**与 config.yaml 一致
- 启动器从 `config_loader.get_config().<tool_id>.backend_port` 读取
- **禁止**在 tools.d/<id>.json 或启动器中硬编码端口号

**control 端口（8901-8999）由 add_tool 自动分配**：无需写到 config.yaml；`ports.control` 是其唯一载体；add_tool 扫已有占用自动从 8901 开始挑最小空闲。

### 4. 启动器模板（多进程工具必需）

启动器 `launchers/<id>.py` **必须实现**：

#### 4.1 子进程清理函数
```python
def _force_kill_children(children, launcher_pid):
    """强制杀死所有子进程及其衍生进程（Vite/esbuild 可能脱链）。"""
    if os.name == "nt":
        try:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(launcher_pid)],
                          capture_output=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired, FileNotFoundError):
            for child in children:
                if child.poll() is None:
                    try:
                        subprocess.run(["taskkill", "/F", "/T", "/PID", str(child.pid)],
                                      capture_output=True, timeout=3)
                    except Exception:
                        pass
    else:
        try:
            os.killpg(os.getpgid(launcher_pid), signal.SIGKILL)
        except OSError:
            pass
```

#### 4.2 优雅关闭处理
```python
def _shutdown(children, signum, frame):
    """收到 SIGTERM/SIGINT：terminate 1 秒后必须强制 kill 整进程树。"""
    for child in children:
        if child.poll() is None:
            try:
                child.terminate()
            except OSError:
                pass
    time.sleep(1.0)
    _force_kill_children(children, os.getpid())
    raise SystemExit(0)
```

#### 4.3 主循环异常退出处理
```python
while True:
    time.sleep(2.0)
    if not all(p.poll() is None for p in children):
        # 任一子进程退出 → 强制 kill 整个树
        _force_kill_children(children, os.getpid())
        return 1
```

#### 4.4 日志管理
- 子进程日志写入 `toolbox_hub/logs/<id>/{backend,frontend}.log`
- 使用 `_pump()` 线程实时读取子进程 stdout/stderr
- 日志目录不存在时自动创建

### 5. 安全原则（绝对禁止违反）

#### 不可越界规则
- **绝不修改**兄弟项目的代码或数据
- 启动器只能通过**原生命令**拉起兄弟工具（如 `python run.py`、`npm run dev`）
- 配置失败时仅提示用户，允许重试
- 调度失败不回退兄弟项目的状态

#### 进程隔离
- 使用 `CREATE_NEW_PROCESS_GROUP`（Windows）避免 Ctrl+C 传播
- 不使用全局 `taskkill /IM node.exe` 兜底（会误杀其他应用）
- 端口冲突时报错，不自动选择其他端口

### 6. 接入后必做自检（人工验证）

```powershell
# 1. 在 toolbox_hub UI 中执行 5 轮启停
# 启动 → 强关 → 启动 → 强关 → 启动

# 2. 检查端口是否回到初始值
netstat -ano -p TCP | findstr ":<port>"

# 3. 检查是否有僵尸进程
tasklist /fi "imagename eq node.exe"
tasklist /fi "imagename eq python.exe"

# 4. 查看启动器日志确认走了 _force_kill_children
Get-Content toolbox_hub\logs\<id>.log -Tail 50
```

**任一项异常 → 不得合并，回到启动器实现检查**

### 7. ISS 跟踪（必须）

每次接入新工具 / 修 hub bug，在 `toolbox_hub/docs/project/project_state.md` 登记：

```markdown
#### ISS-<NN> 🟨 <一句话标题>
- **现象**：<可观察到的现象>
- **根因**：<底层原因>
- **证据**：<日志 / netstat / 复现步骤>
- **解决方式**：<具体修改 + 涉及的 schema / 文件>
- **回归**：<测试用例 / 验证步骤>
```

自检通过后改为 🟩。

## 禁止行为（反模式）

| 反模式 | 后果 | 根因案例 |
|--------|------|---------|
| 启动器只 `terminate()` 就 `SystemExit` | npm/node/esbuild 残留 | ISS-006 |
| tools.d/<id>.json 硬编码端口 | force_stop 找不到正确端口 | - |
| 把兄弟项目代码搬进 toolbox_hub/ | 兄弟项目更新后失效 | - |
| 多个工具绑同一端口 | force_stop 杀错进程 | - |
| 主循环里"子进程退出"只 `terminate()` 另一个 | Vite worker 脱链残留 | ISS-006 |
| 启动器不记录子进程日志路径 | 出问题无法定位 | - |
| **`command[1]` 写带 `../` 的相对路径** | hub spawn 找不到 control 进程，returncode=2 | **ISS-021** |
| **手写 `tools.d/<id>.json` 的 `command` / `tool_command` / `tool_working_dir` / `ports.control`** | 极易抄错（ISS-021 复现） | **ISS-021** |
| **Popen 依赖隐式 cwd 找相对脚本** | 父目录深度变化即失配 | **ISS-021** |
| **让 control_service 硬编码 `uvicorn main:app` / `npm run dev`** | 对非标布局（tts_mvp / Qwen3-TTS）失效 | **ISS-021** |
| **绕开 add_tool 的 control 端口自动分配** | 端口冲突静默 | **ISS-021** |
| **改 schema 只改一处**（argparse / 模板 / 文档脱节） | 后人按错表手写就踩坑 | **ISS-021** |

## 测试要求

### 单元测试（`tests/test_<id>_launcher.py`）
- `_resolve_paths()` 返回的目录必须存在
- `_resolve_python()` 优先级：`.venv/Scripts/python.exe` → `venv/` → 当前解释器

### 集成测试
运行完整测试套件：
```powershell
cd toolbox_hub
python -m pytest tests/ -v
```

### schema 回归测试
- `tests/test_add_tool.py` 锁定 `tools.d/<id>.json` 的字段形态（`command` 不带 `../` / `ports.control` 在 8901-8999 / 冲突 / 越界拒绝 / 自动分配）—— **改 schema 必须同步加测试**

## Fresh-clone 通用性（最重要）

任何改动都必须满足：**一个新用户 clone 仓库后，不改任何环境变量、不改任何路径、不跑任何 host-specific 脚本就能让 hub 跑起来**。

提交前自检清单：
- [ ] 改动里没有任何 `../` 前缀出现在 `command` / `tool_command` 字段
- [ ] 没有 `C:\Users\` / `/Users/` / `D:/ai/` 等绝对路径（除非是 `tool_command` 里用户显式指定的 venv 解释器）
- [ ] `tools.d/*.json` 全部由 `add_tool` 生成（diff 显示是 regen 而非手改）
- [ ] `integration-checklist.md` §2 字段表与 `tools.d/*.json` 实际字段一致
- [ ] `python -m pytest tests/ -q` 全绿
- [ ] `project_state.md` 已知问题区有对应 ISS 编号（如未记录则补一条）

## 参考文档
- `toolbox_hub/docs/project/integration-checklist.md` - 完整接入流程 + 字段表真相源
- `toolbox_hub/docs/project/control-protocol.md` - control 端口范围 / 协议
- `toolbox_hub/docs/project/arch.md` - 架构说明
- `toolbox_hub/launchers/md_editor.py` - 启动器参考实现
- `toolbox_hub/.cursor/skills/toolbox-hub-onboarding/SKILL.md` - 工具接入与诊断 skill

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 初始化规则集 | 首次发布 |
| 2026-10-09 | 加入 3 层架构 + command/tool_command 拆分 + control 8901-8999 + schema 3 同步 + 反模式表增 ISS-021 + fresh-clone 通用性原则 | ISS-021 修复（8 份手写 tools.d/*.json `../launchers/...` 路径错位 + 双进程工具硬编码脆性） |
