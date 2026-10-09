---
name: port-config-audit
version: 1.1.0
created: 2026-08-30
last_used: 2026-10-03
usage_count: 0
tags: [engineering, port, config, audit, toolbox-hub, tts-mvp]
scope: project
overlap_with: [process-tree-cleanup, tts-mvp-provider-integration]
---

# port-config-audit

审计端口配置的一致性，确保 `tools.json`、`config.yaml`、`launcher.py` 三者端口一致。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："端口冲突"、"端口检查"、"端口审计"
- 用户说："tools.json 不一致"、"config 端口"
- 启动工具时遇到端口已被占用
- 修改了 `tools.json` 或 `config.yaml` 后
- 添加新工具到 toolbox_hub

## 核心问题

**toolbox_hub 中端口配置分散在多个文件**：

| 文件 | 端口字段 | 用途 |
|------|----------|------|
| `toolbox_hub/tools.json` | `url` / `health_url` | UI 显示和健康检查 |
| `toolbox_hub/config.yaml` | `backend_port` / `frontend_port` | 配置中心 |
| `toolbox_hub/launchers/*.py` | `--port XXXX` / `PORT = XXXX` | 启动器传递给子进程 |
| `toolbox_hub/main.py` | 读取 config 后传递 | 应用入口 |

**典型错误模式**：

```yaml
# config.yaml
ciallo:
  backend_port: 8000
  frontend_port: 3000
```

```json
// tools.json
{
  "id": "ciallo",
  "url": "http://localhost:8001",  ← 不一致！
  "health_url": "http://localhost:8001/health"
}
```

```python
# launchers/ciallo.py
subprocess.Popen(["uvicorn", "main:app", "--port", "8000"])  ← 又一个不一致
```

**后果**：

- UI 显示的端口无法访问
- 健康检查失败
- force_stop 找不到正确端口
- 用户看到的端口与实际不一致

**违反案例**（来自历史对话）：

| 对话 | 问题 | 后果 |
|------|------|------|
| `83a486f6` (8/5) | launcher 硬编码 8000/3000 | 与 config.yaml 8001 不一致 |
| `f52889b4` (8/4) | 8000 占用、3000 漂移 | 端口冲突 |
| `7375f444` (8/10) | toolbox 端口冲突 | 多进程残留 |
| `481c9fc8` (8/4) | 5050 多进程占用 | 启动失败 |

## 标准审计流程

```
1. 收集所有端口配置
   ├─ 读取 config.yaml（单一来源）
   ├─ 读取 tools.json
   ├─ 扫描 launchers/*.py
   └─ 扫描 main.py
       ↓
2. 提取端口号
       ↓
3. 对比一致性
       ↓
4. 检查端口冲突
   ├─ 与正在运行的进程对比
   └─ 与历史占用记录对比
       ↓
5. 生成报告
       ↓
6. 提供修复建议
```

## 详细步骤

### Step 1：收集端口配置

#### 1.1 config.yaml（权威源）

```yaml
# toolbox_hub/config.yaml
ciallo:
  backend_port: 8000
  frontend_port: 3000
  startup_grace_seconds: 12.0

md_editor:
  backend_port: 8001
  frontend_port: 5173
```

#### 1.2 tools.json

```json
[
  {
    "id": "ciallo",
    "name": "Ciallo",
    "url": "http://localhost:8000",
    "health_url": "http://localhost:8000/health"
  }
]
```

#### 1.3 launchers/*.py

```python
# launchers/ciallo.py
def start_backend(working_dir):
    cmd = ["uvicorn", "app.main:app", "--port", "8000", "--host", "0.0.0.0"]
    # 关键：8000 必须与 config.yaml 一致
```

#### 1.4 main.py 或启动入口

```python
# 启动时读取 config 后传递给子进程
config = load_config()
backend_port = config["ciallo"]["backend_port"]
launcher_cmd = ["python", "launchers/ciallo.py", "--backend-port", str(backend_port)]
```

### Step 2：端口号提取

**从 config.yaml 提取**：

```python
import yaml
with open("config.yaml") as f:
    config = yaml.safe_load(f)

for tool_id, tool_config in config.items():
    if "backend_port" in tool_config:
        ports = {
            "backend": tool_config["backend_port"],
            "frontend": tool_config.get("frontend_port")
        }
```

**从 tools.json 提取**：

```python
import json
import re

with open("tools.json") as f:
    tools = json.load(f)

for tool in tools:
    url = tool.get("url", "")
    health_url = tool.get("health_url", "")
    ports = {
        "url_port": int(re.search(r":(\d+)", url).group(1)) if url else None,
        "health_port": int(re.search(r":(\d+)", health_url).group(1)) if health_url else None
    }
```

**从 launcher 提取**：

```python
import re

launcher_content = open(f"launchers/{tool_id}.py").read()
ports = re.findall(r"--port\s+(\d+)|PORT\s*=\s*(\d+)", launcher_content)
# 或更精确的匹配
backend_port = re.search(r"--backend-port[=\s]+(\d+)", launcher_content)
frontend_port = re.search(r"--frontend-port[=\s]+(\d+)", launcher_content)
```

### Step 3：对比一致性

**对比矩阵**：

| 工具 | config.yaml | tools.json | launcher.py | 状态 |
|------|------------|-----------|-------------|------|
| ciallo | 8000/3000 | 8000/3000 | 8000/3000 | ✓ 一致 |
| md_editor | 8001/5173 | 8001/5173 | 8001/5173 | ✓ 一致 |
| video_summarizer | 8002/5174 | 8002/5174 | 8002/5174 | ✗ launcher 是 8003 |

**一致性规则**：

```
config.yaml 端口 == tools.json 端口 == launcher.py 端口
       ↓
强制约束：三者必须一致
单一来源：config.yaml 是唯一权威
```

### Step 4：端口冲突检查

```powershell
# 检查端口是否被占用
netstat -ano -p TCP | findstr "LISTENING" | ForEach-Object {
    $line = $_
    if ($line -match ":(\d+)\s") {
        $port = $matches[1]
        # 与配置的端口对比
    }
}
```

**冲突分类**：

| 状态 | 含义 | 处理 |
|------|------|------|
| LISTENING | 端口被占用 | 询问用户：强制清理 / 更换端口 |
| TIME_WAIT | 刚释放但未完全释放 | 等待 60 秒 |
| ESTABLISHED | 已建立连接 | 警告但不阻止 |
| 未占用 | 可用 | 正常 |

### Step 5：生成报告

```markdown
## 端口配置审计报告

**审计时间**：YYYY-MM-DD
**审计工具**：N 个

### 一致性检查

| 工具 | config.yaml | tools.json | launcher.py | 状态 |
|------|------------|-----------|-------------|------|
| ciallo | 8000/3000 | 8000/3000 | 8000/3000 | ✓ |
| md_editor | 8001/5173 | 8001/5173 | 8001/5173 | ✓ |

### 冲突检查

| 工具 | backend | frontend | 状态 |
|------|---------|----------|------|
| ciallo | 8000 | 3000 | ✗ 端口 8000 被 PID 12345 占用 |

### 问题清单

1. **HIGH**：ciallo launcher 端口与 config.yaml 不一致
   - launcher: 8003
   - config.yaml: 8000
   - tools.json: 8000

2. **MEDIUM**：端口 8000 被其他项目占用
   - 占用进程：node.exe (PID 12345)
   - 建议：使用 process-tree-cleanup 技能清理

### 修复建议

1. 修改 launcher.py 使用 config 中的端口
2. 或修改 config.yaml / tools.json 与 launcher 一致
```

### Step 6：修复建议

根据不一致类型提供不同建议：

**类型 1：launcher 硬编码但与 config 不一致**

```python
# 修改 launcher.py 使用 config
import argparse
import yaml

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend-port", type=int, required=True)
    parser.add_argument("--frontend-port", type=int, required=True)
    args = parser.parse_args()

    # 使用 args.backend_port 而不是硬编码
    cmd = ["uvicorn", "app.main:app", "--port", str(args.backend_port)]
```

**类型 2：tools.json 写错端口**

```json
// 修改 url 和 health_url 与 config.yaml 一致
{
  "id": "ciallo",
  "url": "http://localhost:8000",  // 与 config.yaml backend_port 一致
  "health_url": "http://localhost:8000/health"
}
```

**类型 3：config.yaml 端口被占用**

```yaml
# 更换为可用端口
ciallo:
  backend_port: 8010  # 从 8000 改为 8010
  frontend_port: 3010  # 从 3000 改为 3010
```

并同步修改 tools.json 和 launcher。

## 标准实现脚本

`scripts/audit_ports.py`：

```python
#!/usr/bin/env python3
"""端口配置审计脚本"""
import yaml
import json
import re
import subprocess
import sys
from pathlib import Path


def load_config(config_path="toolbox_hub/config.yaml"):
    with open(config_path) as f:
        return yaml.safe_load(f)


def load_tools_json(tools_path="toolbox_hub/tools.json"):
    with open(tools_path) as f:
        return json.load(f)


def extract_launcher_ports(launcher_path):
    """从 launcher.py 提取端口配置"""
    content = Path(launcher_path).read_text(encoding="utf-8")
    ports = {}
    m = re.search(r"--backend-port[=\s]+(\d+)", content)
    if m:
        ports["backend"] = int(m.group(1))
    m = re.search(r"--frontend-port[=\s]+(\d+)", content)
    if m:
        ports["frontend"] = int(m.group(1))
    # 兼容硬编码
    if "backend" not in ports:
        m = re.search(r"uvicorn.*--port\s+(\d+)", content)
        if m:
            ports["backend"] = int(m.group(1))
    return ports


def check_port_listening(port):
    """检查端口是否被占用"""
    if sys.platform == "win32":
        result = subprocess.run(
            ["netstat", "-ano", "-p", "TCP"],
            capture_output=True, text=True
        )
        for line in result.stdout.split('\n'):
            if f":{port} " in line and "LISTENING" in line:
                return True
    return False


def audit():
    config = load_config()
    tools = load_tools_json()

    issues = []

    for tool in tools:
        tool_id = tool["id"]
        # 1. 从 config.yaml 提取端口
        cfg = config.get(tool_id, {})
        cfg_backend = cfg.get("backend_port")
        cfg_frontend = cfg.get("frontend_port")

        # 2. 从 tools.json 提取端口
        url = tool.get("url", "")
        m = re.search(r":(\d+)", url)
        tj_backend = int(m.group(1)) if m else None

        # 3. 从 launcher 提取端口
        launcher_path = f"toolbox_hub/launchers/{tool_id}.py"
        if Path(launcher_path).exists():
            launcher_ports = extract_launcher_ports(launcher_path)
            ln_backend = launcher_ports.get("backend")
        else:
            ln_backend = None

        # 4. 对比一致性
        if cfg_backend != tj_backend:
            issues.append({
                "tool": tool_id,
                "type": "inconsistency",
                "detail": f"config={cfg_backend}, tools.json={tj_backend}"
            })

        if ln_backend and cfg_backend != ln_backend:
            issues.append({
                "tool": tool_id,
                "type": "inconsistency",
                "detail": f"config={cfg_backend}, launcher={ln_backend}"
            })

        # 5. 检查端口占用
        if cfg_backend and check_port_listening(cfg_backend):
            issues.append({
                "tool": tool_id,
                "type": "port_in_use",
                "detail": f"backend port {cfg_backend} is LISTENING"
            })

        if cfg_frontend and check_port_listening(cfg_frontend):
            issues.append({
                "tool": tool_id,
                "type": "port_in_use",
                "detail": f"frontend port {cfg_frontend} is LISTENING"
            })

    # 输出报告
    print("=" * 60)
    print("端口配置审计报告")
    print("=" * 60)

    if not issues:
        print("✓ 所有端口配置一致且无冲突")
        return 0

    for issue in issues:
        severity = "HIGH" if issue["type"] == "inconsistency" else "MEDIUM"
        print(f"[{severity}] {issue['tool']}: {issue['detail']}")

    return 1


if __name__ == "__main__":
    sys.exit(audit())
```

## 实际案例

### 案例 1：ciallo 端口不一致修复

来源：对话 `83a486f6-d128-4740-b340-d874408508e7`

**问题**：

```yaml
# config.yaml
ciallo:
  backend_port: 8000
```

```json
// tools.json
{
  "id": "ciallo",
  "url": "http://localhost:8001"  // 不一致！
}
```

**审计发现**：

```
[HIGH] ciallo: config=8000, tools.json=8001
```

**修复**：

```json
// 修改 tools.json
{
  "id": "ciallo",
  "url": "http://localhost:8000",
  "health_url": "http://localhost:8000/health"
}
```

**结果**：端口一致，启动器找到正确的进程。

### 案例 2：toolbox_hub 启动失败

来源：对话 `481c9fc8-46d8-4e1e-ac41-857b83cd5da1`

**问题**：端口 5050 被 3 个 LISTENING 进程占用（PID 30008、11828、26516）

**审计发现**：

```
[MEDIUM] toolbox_hub: port 5050 is LISTENING (3 processes)
```

**修复**：使用 `process-tree-cleanup` 技能清理所有占用进程。

## 注意事项

### 必须遵守

- **强制** config.yaml 是端口唯一来源
- **强制** launcher 从命令行参数读取端口（不硬编码）
- **强制** tools.json 端口与 config.yaml 一致
- **禁止** 在多个文件中硬编码同一端口
- **禁止** 在 launcher 中使用 magic number

### 推荐实践

- 端口冲突时优先清理而非换端口
- 端口变更时同步修改所有 3 个文件
- 定期运行端口审计（每周/每月）
- 端口被占时记录到 ISS

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| launcher 硬编码端口 | 配置漂移 | 命令行参数传入 |
| tools.json 与 config 不一致 | UI 显示错误 | 严格同步 |
| 端口冲突就换端口 | 端口碎片化 | 清理占用进程 |
| 多个文件硬编码同一端口 | 一改全改 | 单一来源 |

## 关联技能

- `process-tree-cleanup` - 清理占用端口的进程
- `toolbox-integration` - 工具接入规范
- `tts-mvp-provider-integration` - tts-mvp 多端口架构（8787 + 9880/9881/9882）

## TTS-MVP 多端口矩阵（2026-10-03 追加）

tts-mvp 项目使用**多进程分层架构**，每个 provider 占用独立端口。审计时必须把整个端口矩阵视为单一配置单元。

| 进程 | 端口 | 启动者 | 启动依赖 |
|------|------|--------|----------|
| Node API（Express） | 8787 | `npm run dev:server` | 启动最后 |
| GPT-SoVITS API_v2 | 9880 | `api_v2.py -p 9880 -c configs/tts_infer_v1.yaml` | 需 90 秒加载模型 |
| GPT-SoV sidecar | 9881 | `python gpt_sovits_server.py` | 依赖 9880 |
| Qwen3-TTS sidecar | 9882 | `python qwen3_tts_server.py` | 独立 |
| 新增 provider | 9883+ | `python {name}_server.py` | 端口矩阵下一个空闲端口 |

**审计要点**：

1. **端口不重叠**：8787、9880、9881、9882、9883 互不冲突
2. **sidecar 端口与 Node API 同步**：通过 `.env` 中 `*_URL=http://127.0.0.1:PORT` 关联
3. **启动顺序**：必须 9880 → 9881 → 8787（参见 `tts-mvp-provider-integration` 技能）
4. **健康检查路径**：`toolbox_hub/tools.json` 中 `health_url` 必须指向 sidecar 的 `/health` 端点

**典型错误**（2026-09-08 修复）：

```
Node API（8787）找不到 GPT-SoVITS sidecar
   ↓
排查 .env 中 GPT_SOVITS_URL
   ↓
发现 URL 写死为 http://127.0.0.1:9880
   ↓
正确：http://127.0.0.1:9881（sidecar，而非 API）
```

**审计脚本扩展**：

```python
# 加入 tts-mvp 端口矩阵
TTS_PORTS = {
    "node-api": 8787,
    "gpt-sovits-api": 9880,
    "gpt-sovits-sidecar": 9881,
    "qwen3-tts-sidecar": 9882,
}

# 读取 tts-mvp/.env 验证 URL
env = read_env("tts-mvp/.env")
for key, expected_port in TTS_PORTS.items():
    url = env.get(f"{key.upper().replace('-', '_')}_URL", "")
    if expected_port and f":{expected_port}" not in url:
        issues.append({
            "tool": "tts-mvp",
            "type": "url_port_mismatch",
            "detail": f"{key} 期望端口 {expected_port}, .env 中 URL={url}"
        })
```

## 关联规则

- `toolbox-integration.md` § 3 端口管理
- `architecture.md` § 6 配置管理

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 创建技能 | 4+ 次端口配置不一致对话 |
| 2026-10-03 | 追加 tts-mvp 多端口矩阵 | 11+ 次 TTS provider 集成对话 |