---
name: process-tree-cleanup
version: 1.1.0
created: 2026-08-30
last_used: 2026-10-03
usage_count: 0
tags: [engineering, process, cleanup, windows, node, vite, python-sidecar]
scope: project
overlap_with: [port-config-audit, tts-mvp-provider-integration]
---

# process-tree-cleanup

深度清理进程树，特别是 Vite/esbuild/Node 等容易脱链的子进程。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："强制关闭不彻底"、"进程残留"、"清理进程树"
- 用户说："Vite 还在跑"、"端口仍被占用"
- 用户说："force-stop 不彻底"、"taskkill 杀不掉"
- 检测到 port 仍被 LISTENING 但 launcher 已退出

## 核心问题

Vite/esbuild 在 Windows 上启动时会**派生多个子进程**，形成如下进程树：

```
launcher.exe (PID 1000)
├─ python.exe (PID 1100)
│   └─ npm.cmd (PID 1200)
│       └─ node.exe (PID 1300)  ← npm 子进程
│           ├─ node.exe (PID 1400)  ← Vite 主进程
│           ├─ node.exe (PID 1500)  ← esbuild worker
│           └─ node.exe (PID 1600)  ← esbuild worker
```

`taskkill /F /T /PID 1000` 仅终止 PID 1100（python），不会跟随 npm → node 的链条。

## 标准清理流程

```
1. 识别所有目标进程
   ├─ 通过 launcher PID 查找进程树
   ├─ 通过端口查找监听进程
   └─ 通过进程名查找（如 node.exe）
       ↓
2. 收集所有相关 PIDs
   ├─ 启动器 PID
   ├─ 直接子进程 PIDs
   ├─ 端口监听 PIDs
   └─ 端口监听的父进程链
       ↓
3. 强制终止（taskkill /F /T /PID）
       ↓
4. 验证清理结果
   ├─ 端口已释放
   ├─ 进程已退出
   └─ 无残留
```

## 具体步骤

### 1. 识别目标进程

#### 1.1 通过 launcher 进程树

```powershell
# Windows: 查找 launcher 的所有后代进程
$launcherPid = 12345
wmic process where "ParentProcessId=$launcherPid" get ProcessId,Name
# 递归查找所有子进程
```

#### 1.2 通过端口监听进程

```powershell
# 查找占用端口的所有进程（包括父子链）
netstat -ano -p TCP | findstr ":3000"
# 输出示例：TCP 0.0.0.0:3000 0.0.0.0:0 LISTENING 12350
# PID 12350 = node.exe (Vite)
```

#### 1.3 通过进程名查找

```powershell
# 查找特定进程
tasklist /fi "imagename eq node.exe" /fo csv
tasklist /fi "imagename eq python.exe" /fo csv
```

**注意**：用进程名匹配要谨慎，避免误杀其他项目的进程。

### 2. 收集所有相关 PIDs

收集所有需要终止的 PID：

```powershell
$pidsToKill = @()

# 1. launcher 进程
$pidsToKill += $launcherPid

# 2. 直接子进程
$directChildren = Get-CimInstance Win32_Process -Filter "ParentProcessId=$launcherPid"
$pidsToKill += $directChildren.ProcessId

# 3. 端口监听进程
$portPids = netstat -ano -p TCP | findstr ":3000 :3001 :8000 :8001" | ForEach-Object {
    ($_ -split '\s+')[-1]
} | Sort-Object -Unique
$pidsToKill += $portPids

# 4. 端口监听的父进程链
foreach ($pid in $portPids) {
    $current = $pid
    while ($current -ne 0) {
        $pidsToKill += $current
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$current"
        $current = $parent.ParentProcessId
    }
}

$pidsToKill = $pidsToKill | Sort-Object -Unique
```

### 3. 强制终止

```powershell
foreach ($pid in $pidsToKill) {
    try {
        taskkill /F /T /PID $pid 2>$null
        Write-Host "Killed PID $pid"
    } catch {
        Write-Host "Failed to kill PID $pid (may already be dead)"
    }
}
```

**为什么用 taskkill 而不用 Stop-Process？**

- `Stop-Process` 不会终止子进程
- `taskkill /F /T` 会终止进程树
- `/T` 参数：终止指定进程及其子进程

### 4. 验证清理结果

```powershell
# 等待 1 秒确保进程退出
Start-Sleep -Seconds 1

# 检查端口是否释放
$ports = @(3000, 3001, 8000, 8001)
foreach ($port in $ports) {
    $listening = netstat -ano -p TCP | findstr ":$port " | findstr "LISTENING"
    if ($listening) {
        Write-Host "WARNING: Port $port still LISTENING: $listening"
    } else {
        Write-Host "OK: Port $port is free"
    }
}

# 检查残留进程
$nodeProcs = tasklist /fi "imagename eq node.exe" /fo csv
Write-Host "Remaining node.exe: $($nodeProcs.Count - 1) processes"
```

## 标准实现模板（Python）

放在 `toolbox_hub/service_manager.py` 中：

```python
import os
import subprocess
import time

def _get_process_tree(pid):
    """获取进程及其所有后代 PIDs"""
    pids = {pid}
    try:
        if os.name == "nt":
            # Windows: 使用 wmic 或 PowerShell
            result = subprocess.run(
                ["powershell", "-Command",
                 f"Get-CimInstance Win32_Process -Filter 'ParentProcessId={pid}' | Select-Object -ExpandProperty ProcessId"],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.strip().split('\n'):
                if line.strip().isdigit():
                    child_pid = int(line.strip())
                    pids.update(_get_process_tree(child_pid))
        else:
            # Unix: 使用 ps
            result = subprocess.run(
                ["pgrep", "-P", str(pid)],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.strip().split('\n'):
                if line.strip().isdigit():
                    child_pid = int(line.strip())
                    pids.update(_get_process_tree(child_pid))
    except Exception:
        pass
    return pids


def _get_port_pids(ports):
    """获取监听指定端口的所有 PIDs"""
    pids = set()
    for port in ports:
        try:
            if os.name == "nt":
                result = subprocess.run(
                    ["netstat", "-ano", "-p", "TCP"],
                    capture_output=True, text=True, timeout=5
                )
                for line in result.stdout.split('\n'):
                    if f":{port} " in line and "LISTENING" in line:
                        parts = line.split()
                        if parts and parts[-1].isdigit():
                            pids.add(int(parts[-1]))
        except Exception:
            pass
    return pids


def _force_kill_tree(launcher_pid, ports):
    """强制杀死整个进程树"""
    all_pids = _get_process_tree(launcher_pid)
    port_pids = _get_port_pids(ports)
    all_pids.update(port_pids)

    for pid in all_pids:
        try:
            if os.name == "nt":
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(pid)],
                    capture_output=True, timeout=3
                )
        except Exception:
            pass


def force_stop(self, tool_id):
    """强制停止指定工具"""
    config = self._get_tool_config(tool_id)
    launcher_pid = self._get_launcher_pid(tool_id)
    ports = [config["backend_port"], config["frontend_port"]]

    # 1. 尝试正常关闭
    self._terminate(launcher_pid)

    # 2. 等待 1 秒
    time.sleep(1.0)

    # 3. 强制清理进程树
    _force_kill_tree(launcher_pid, ports)

    # 4. 验证清理
    time.sleep(0.5)
    remaining = _get_port_pids(ports)
    if remaining:
        # 二次清理
        for pid in remaining:
            try:
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(pid)],
                    capture_output=True, timeout=3
                )
            except Exception:
                pass

    return True
```

## 实际案例

### 案例 1：toolbox_hub 强关闭后端口仍被占用

来源：对话 `ace6b132-62aa-43bf-8731-6b4d71c912b3`

**问题**：点击"强制关闭"后，ciallo 前端页面（3000 端口）仍可访问

**诊断**：

```powershell
# 发现多个 Vite 孤儿进程
netstat -ano -p TCP | findstr ":3000 :3001 :3002 :3003 :3004 :3005 :3006"
# 输出：
# TCP 0.0.0.0:3000 LISTENING 12345
# TCP 0.0.0.0:3001 LISTENING 12346
# TCP 0.0.0.0:3002 LISTENING 12347
# ...
```

**解决**：

1. 收集所有监听 3000-3006 的 PIDs
2. 对每个 PID 执行 `taskkill /F /T /PID`
3. 验证端口释放

**结果**：所有端口释放，孤儿进程消失

### 案例 2：5+ 轮强关闭都无法彻底退出 ciallo

来源：对话 `85d14443-a718-4a71-996d-23b1f82f0518`

**问题**：连续 5 轮"启动→强关闭"后仍有残留

**根因**：

```
原 force_stop 实现：
1. terminate launcher
2. SystemExit(0)  ← 立即退出 launcher 自身
3. Vite/esbuild 成为孤儿进程继续运行
```

**解决**：

```python
# 修改后的 force_stop
def force_stop(self, tool_id):
    launcher_pid = self._get_launcher_pid(tool_id)
    ports = [config.backend_port, config.frontend_port]

    # 1. 优雅终止（最多 3 秒）
    self._terminate(launcher_pid)
    time.sleep(3.0)

    # 2. 强制清理进程树（关键步骤）
    _force_kill_tree(launcher_pid, ports)

    # 3. 验证
    time.sleep(1.0)
    remaining = _get_port_pids(ports)
    if remaining:
        # 二次清理
        for pid in remaining:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)],
                         capture_output=True, timeout=3)
```

## 注意事项

### 必须遵守

- **必须**清理 launcher 的整个进程树（包括孙子进程）
- **必须**用 `taskkill /F /T /PID`（不是 Stop-Process）
- **必须**验证清理结果（端口释放、进程退出）
- **禁止**使用 `taskkill /IM node.exe /F`（会误杀其他项目）
- **禁止**在清理不彻底时退出 launcher

### 推荐实践

- 启动器退出前必须清理子进程
- 清理失败时记录日志
- 提供详细日志给用户查看
- 配置合理的超时时间（terminate 3s + force kill 5s）

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 仅 terminate launcher | Vite/esbuild 残留 | 必须清理整个进程树 |
| 用 `taskkill /IM node.exe` | 误杀其他项目的 node | 用 PID 精确清理 |
| 不验证端口 | 用户发现仍可访问 | 清理后必须验证 |
| 清理失败就退出 | 残留进程继续运行 | 二次清理 + 重试 |
| launcher 自身在子进程退出前退出 | 子进程成孤儿 | launcher 必须等待清理完成 |

## 调试工具

### 查看进程树

```powershell
# 查看指定 PID 的进程树
$rootPid = 12345
wmic process where "ProcessId=$rootPid" get Name,ProcessId,ParentProcessId,CommandLine /format:list
```

### 查看端口监听

```powershell
netstat -ano -p TCP | findstr "LISTENING"
```

### 查看进程命令行

```powershell
# 查看进程的命令行（用于识别 Vite/esbuild）
wmic process where "ProcessId=12345" get CommandLine /format:list
```

### 强制清理脚本

`scripts/force_cleanup.ps1`：

```powershell
param(
    [int[]]$Ports,
    [string]$ProcessName
)

# 1. 查找端口占用
foreach ($port in $Ports) {
    $pids = netstat -ano -p TCP | findstr ":$port " | ForEach-Object {
        ($_ -split '\s+')[-1]
    } | Sort-Object -Unique

    foreach ($pid in $pids) {
        Write-Host "Killing PID $pid on port $port"
        taskkill /F /T /PID $pid
    }
}

# 2. 按进程名清理（谨慎）
if ($ProcessName) {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Killing $($_.Name) PID $($_.Id)"
        Stop-Process -Id $_.Id -Force
    }
}

# 3. 验证
Start-Sleep -Seconds 2
foreach ($port in $Ports) {
    $listening = netstat -ano -p TCP | findstr ":$port " | findstr "LISTENING"
    if ($listening) {
        Write-Host "WARNING: Port $port still LISTENING"
    } else {
        Write-Host "OK: Port $port is free"
    }
}
```

## 关联技能

- `port-config-audit` - 端口配置审计
- `toolbox-integration` - 工具接入规范（待创建）
- `tts-mvp-provider-integration` - tts-mvp Python sidecar 进程管理

## Python Sidecar 进程清理模式（2026-10-03 追加）

tts-mvp 中的每个 TTS provider 都通过 **Python sidecar** 暴露 HTTP 接口（端口 9881、9882 等）。这些 sidecar 与 Node API 不同：

- 启动在**专用 conda 环境**（如 `C:\Users\wsz\miniconda3\envs\gpt-sovits\`）
- **模型加载耗时长**（GPT-SoVITS 需 90 秒）
- 重启后必须重新加载模型

### Sidecar 进程树结构

```
conda env python.exe (parent)
├─ python.exe (gpt_sovits_server.py, PID 1000)
│   ├─ python.exe (GPT-SoVITS model load, PID 1010)
│   └─ python.exe (HTTP server, PID 1020)
```

### Sidecar 重启专用流程

当 Node API（8787）报"fetch failed"或类似 sidecar 连接错误时：

```powershell
# 1. 定位 sidecar（按端口）
$port = 9881  # gpt-sovits sidecar
$pid = (netstat -ano | findstr ":$port.*LISTENING" | ForEach-Object {
    ($_ -split '\s+')[-1]
}) | Select-Object -First 1

# 2. 清理进程树（强制）
if ($pid) {
    taskkill /F /T /PID $pid
}

# 3. 等待模型卸载路径
Start-Sleep -Seconds 3

# 4. 重启 sidecar（重新加载模型，GPT-SoVITS 需 90 秒）
cd /d D:\ai\projects\tts-mvp
C:\Users\wsz\miniconda3\envs\gpt-sovits\python.exe python\gpt_sovits_server.py `
    > D:\ai\projects\tts-mvp\python\gpt-sovits-sidecar.log 2>&1

# 5. 轮询健康检查（而非固定 sleep）
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 5
        if ($r.ok) {
            $ready = $true
            break
        }
    } catch {
        # 还没就绪
    }
}
```

### 关键差异（与 Node/Vite 模式）

| 维度 | Node/Vite | Python Sidecar |
|------|-----------|----------------|
| 启动时间 | 1-5 秒 | 5-90 秒（取决于是否需加载模型） |
| 健康检查端点 | 通常无 | 必须实现 `/health` |
| 重启策略 | 直接 kill 后启动 | 需等待 `/health` 返回 `ok: true` |
| 日志重定向 | `npm.log` | 必须重定向到 `*.log`（模型加载慢需观察进度） |
| 验证方式 | 检查端口 LISTENING | 检查端口 + 调用 `/health` |

### Sidecar 残留问题（来自历史对话）

**场景**：`@tts-mvp` Node API 报 "fetch failed"（2026-09-07，对话 `4a88a259`）

**根因**：Qwen3-TTS sidecar（9882）崩溃但端口未释放。

**修复**：

```powershell
# 找占用进程
netstat -ano | findstr ":9882.*LISTENING"
# 输出：PID 12345

# 检查是否为僵尸
Get-Process -Id 12345
# 若响应但无响应，强制清理
taskkill /F /T /PID 12345

# 检查 conda 父进程（可能被 taskkill 遗漏）
Get-CimInstance Win32_Process -Filter "ParentProcessId=12345" | Select-Object ProcessId, Name
```

### 已知 Sidecar 端口清单

| Provider | 健康路径 | 清理命令模板 |
|-----------|---------|------------|
| gpt-sovits | `http://127.0.0.1:9881/health` | `taskkill /F /T /PID <PID>` |
| qwen3-tts | `http://127.0.0.1:9882/health` | 同上 |

每次新增 provider 时按 `tts-mvp-provider-integration` 技能扩展此表。

## 关联规则

- `toolbox-integration.md` § 4.1 子进程清理函数
- `architecture.md` § 7 进程管理

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 创建技能 | 5+ 次进程清理失败对话 |
| 2026-10-03 | 追加 Python Sidecar 清理模式 | tts-mvp Qwen3-TTS / GPT-SoVITS sidecar 重启场景 |