---
name: disk-cleanup-tiered
version: 1.0.0
created: 2026-10-06
last_used: 2026-10-06
usage_count: 0
tags: [workflow, disk-cleanup, windows, safety, tier-based, junction]
scope: project
overlap_with: []
---

# disk-cleanup-tiered

按 Tier 分级安全策略清理 Windows 磁盘空间，避免误删正在被服务使用的文件。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："C盘满了"、"清理磁盘"、"看看哪些能删"、"瘦身"
- 用户提到 `disk-cleanup.ps1` 或 `C:\Users\wsz\Desktop\disk-cleanup.ps1`
- C 盘空闲空间 < 10 GB 或类似告警
- 需要迁移大文件到 E 盘

## 核心问题

**Windows 清理的常见陷阱**：

| 陷阱 | 后果 |
|------|------|
| 删除 `C:\Users\wsz\.cache\huggingface` 下模型 | GPT-SoVITS / Qwen3-TTS 服务崩溃 |
| 删除 `miniconda3\envs\qwen3-tts` | TTS 服务 Python 环境丢失 |
| 删除 `C:\Users\wsz\AppData\Local\Cursor` | Cursor IDE 配置丢失 |
| 移动正在被占用的文件 | 服务报错或下次启动失败 |
| 直接 `rm -rf` 大文件夹 | 不可逆损失 |

**绝对不能动的目录清单**（C 盘上）：

| 路径 | 原因 |
|------|------|
| `C:\Users\wsz\.cache\huggingface\` | GPT-SoVITS / Qwen3-TTS 在用 |
| `C:\Users\wsz\.cache\modelscope\` | 同上 |
| `C:\Users\wsz\miniconda3\envs\qwen3-tts\` | Python 解释器 + PyTorch + 模型 |
| `C:\Users\wsz\AppData\Local\Google\Chrome\User Data\Default\` | Profile（1 小时内用过） |
| `C:\Users\wsz\AppData\Roaming\Cursor\` | Cursor 状态库 |

**判断标准**：访问时间 < 24 小时 或 服务端口正在使用。

## Tier 分级策略

### Tier 1 — A 类（安全缓存，可直接删）

**特点**：删除后自动重新生成，零数据风险。

| 项目 | 路径 | 典型大小 |
|------|------|----------|
| NVIDIA 着色器缓存 | `C:\Users\wsz\AppData\Local\NVIDIA\GLCache` + `DXCache` | 4.3 GB |
| Chrome 内置 AI 模型 | `C:\...\Chrome OptGuideOnDeviceModel` | 4.0 GB |
| 剪映预览缓存 | `C:\Users\wsz\AppData\Local\JianyingPro\Cache` | 2.2 GB |
| 剪映 CEF 缓存 | `JianyingPro\CEFCache` | 1.4 GB |
| NVIDIA 旧驱动包 | `C:\ProgramData\NVIDIA Corporation\Downloader` | 1.5 GB |
| npm 缓存 | `%APPDATA%\npm-cache` | 0.9 GB |
| pip 缓存 | `%LOCALAPPDATA%\pip\cache` | 0.3 GB |
| conda 安装包 | `C:\Users\wsz\miniconda3\pkgs` | 1.5 GB |
| Temp 临时文件 | `%LOCALAPPDATA%\Temp` | 1.2 GB |

**操作**：直接 `Remove-Item -Recurse -Force`。

### Tier 2 — B 类（迁移到 E 盘，用目录联接保持路径）

**特点**：软件按原路径访问即可正常工作，无需改配置。

**判定条件**：访问时间 > 7 天 且 非系统组件。

| 项目 | 路径 | 典型大小 |
|------|------|----------|
| 剪映 ASR 语音素材 | `JianyingPro\...SupplysStore` | 1.1 GB |
| PoE2 着色器缓存 | `Documents\My Games\Path of Exile 2\poe2_pipeline_cache` | 3.2 GB |
| 傲梅启动镜像 | `C:\Aomei` | 1.0 GB |

**操作流程**：

```powershell
# 1. robocopy 复制（保留权限 + 重试）
& robocopy $src $dst /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP

# 2. 校验字节数（重要！）
$srcBytes = (Get-ChildItem -LiteralPath $src -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
$dstBytes = (Get-ChildItem -LiteralPath $dst -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
if ([math]::Abs($srcBytes - $dstBytes) -gt 1MB) {
    Write-Host "校验失败，保留原目录"
    exit 1
}

# 3. 删除源目录
Remove-Item -LiteralPath $src -Recurse -Force -EA SilentlyContinue

# 4. 建立目录联接（junction，路径不变）
New-Item -ItemType Junction -Path $src -Target $dst
```

### Tier 3 — C 类（系统级，需谨慎）

**特点**：影响系统或需要管理员权限。

| 项目 | 操作 |
|------|------|
| WinSxS 组件 | `DISM /Online /Cleanup-Image /StartComponentCleanup` |
| Windows Update | `Stop-Service wuauserv; Remove-Item C:\Windows\SoftwareDistribution\Download\*` |
| 回收站 | `Clear-RecycleBin -Force` |
| 系统内存转储 | 删除 `C:\Windows\MEMORY.DMP` |
| hiberfil.sys | `powercfg /h off`（若不用休眠） |

## 关键安全检查

### 检查 1：服务端口在清理前后的状态

```powershell
# 清理前：记录活跃端口
$beforePorts = @{
    'GPT-SoVITS' = 9884  # 或 9880
    'tts-mvp'    = 8787
    'toolbox_hub' = 5050
}

# 清理后：必须全部仍 LISTENING
foreach ($name in $beforePorts.Keys) {
    $port = $beforePorts[$name]
    $listening = netstat -ano -p TCP | findstr ":$port.*LISTENING"
    if (-not $listening) {
        Write-Host "WARNING: $name (port $port) 不再监听！" -ForegroundColor Red
    } else {
        Write-Host "OK: $name (port $port) 正常"
    }
}
```

### 检查 2：访问时间

```powershell
# Tier 2 判定：访问时间 > 7 天才迁移
$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem $path -Recurse -File -Force | Where-Object {
    $_.LastAccessTime -gt $cutoff  # 7 天内用过
}
```

### 检查 3：Python/Node/Conda 等活跃工具

```powershell
# 检查是否在 conda env 中运行
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
    $_.Path  # 若指向 miniconda3\envs\...  → 该 env 不能动
}
```

## 标准实现脚本

参考 `C:\Users\wsz\Desktop\disk-cleanup.ps1`，使用以下函数：

```powershell
function Get-Size($path) {
    $s = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($s) { [math]::Round($s/1GB, 2) } else { 0 }
}

function Remove-Tier1Cache {
    param([string]$Path)
    $size = Get-Size $Path
    if ($size -gt 0.1) {
        Remove-Item -LiteralPath $Path -Recurse -Force -EA SilentlyContinue
        Write-Host "[Tier 1] 清理 $Path (${size} GB)"
    }
}

function Migrate-Tier2ToE {
    param([string]$Src, [string]$DstE)
    $srcSize = Get-Size $Src
    if ($srcSize -lt 0.3) { return }  # 太小不值得迁移
    
    # 1. robocopy
    & robocopy $Src $DstE /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    
    # 2. 校验
    $dstSize = Get-Size $DstE
    if ([math]::Abs($srcSize - $dstSize) -gt 1MB) {
        Write-Host "[Tier 2] 校验失败，保留原目录: $Src"
        return
    }
    
    # 3. 删源 + 建联接
    Remove-Item -LiteralPath $Src -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Junction -Path $Src -Target $DstE | Out-Null
    Write-Host "[Tier 2] 迁移 $Src → $DstE (${srcSize} GB)"
}
```

## 报告模板

```markdown
## C 盘清理结果

**清理前**：C 盘空闲 X GB（已用 Y GB）
**清理后**：C 盘空闲 X' GB（已用 Y' GB）
**释放空间**：Z GB

### A 类（缓存清理）
- 项目 1：N1 GB
- 项目 2：N2 GB
合计：XX GB

### B 类（迁移 E 盘）
- 项目 1：N1 GB → E:\...
- 项目 2：N2 GB → E:\...
合计：XX GB

### 服务验证
- GPT-SoVITS (9884)：OK ✓
- tts-mvp (8787)：OK ✓
- ...

### 没动的部分
- ModelScope/HuggingFace 缓存（XX GB）：GPT-SoVITS 正在用
- miniconda3 envs（XX GB）：tts-mvp 在用
- ...

### 后续建议
- 设置 `HF_HOME=E:\hf_cache`、`MODELSCOPE_CACHE=E:\ms_cache` 让新模型自动下到 E 盘
- DISM 组件清理可再释放 1-3 GB
```

## 实际案例

### 案例 1：2026-10-05 全面清理（对话 7bc0ab44）

**问题**：C 盘仅剩 9.4 GB（已用 140.7 GB），需要清理。

**步骤**：

1. **扫描阶段**（谨慎）：
   - 用 `Get-Size` 列出所有 > 0.3 GB 目录
   - 标记 Tier 1 / Tier 2 / 不可动

2. **关键发现**：`api_v2.py` 在端口 9884 运行（miniconda3\envs\qwen3-tts）
   - 决定：modelscope/huggingface 缓存、conda qwen3-tts env 都不能动
   - 服务依赖路径：`C:\Users\wsz\.cache\huggingface\`、`C:\Users\wsz\.cache\modelscope\`

3. **Tier 1 清理**（17.77 GB）：
   - NVIDIA GLCache + DXCache：4.3 GB
   - Chrome OptGuideOnDeviceModel：4.0 GB
   - 剪映 Cache：4.2 GB
   - NVIDIA Downloader：1.5 GB
   - Temp：1.2 GB
   - npm + pip + conda pkgs：2.1 GB

4. **Tier 2 迁移**（5.25 GB）：
   - 剪映 ASR → `E:\C盘瘦身搬家文件\2026-10-05\JianyingPro-ASR`
   - PoE2 着色器 → `E:\...\PoE2-shader-cache`
   - Aomei 镜像 → `E:\...\Aomei`

5. **服务验证**：
   - GPT-SoVITS 9884 端口仍 LISTENING ✓
   - 用户体验无中断

**结果**：C 盘 9.4 GB → 32.46 GB（+23 GB），GPT-SoVITS 服务正常。

### 案例 2：robocopy 校验失败保护（场景示例）

```powershell
# 假设复制时中途断电 / 源被占用
& robocopy $src $dst /E /R:1 /W:1 ...
$srcBytes = ...
$dstBytes = ...  # 只有一半

if ([math]::Abs($srcBytes - $dstBytes) -gt 1MB) {
    # 校验失败：保留源，不建联接，不删源
    Write-Host "校验失败，保留原目录"
}
```

**关键**：永不删除未校验的源，避免不可逆数据丢失。

## 注意事项

### 必须遵守

- **强制** 清理前检查活跃服务端口，清理后再次验证
- **强制** Tier 2 迁移必须 robocopy + 字节数校验
- **强制** 7 天内访问过 / 服务正在用的文件不能动
- **强制** 区分 `AAD` vs `LastWriteTime`，用 `LastAccessTime` 判断是否在用
- **禁止** 删除 `miniconda3\envs\`、`\.cache\`（除非确认服务停了）
- **禁止** 在没有 `Test-Path -LiteralPath` 的情况下清理系统路径
- **禁止** 直接 `rm -rf` 大目录

### 推荐实践

- 先扫描、再列计划、用户确认、再清理（分步走）
- Tier 1 直接清理前用 `Get-Size` 告知释放多少空间
- Tier 2 迁移前先验证 E 盘空间是否充足
- 清理后给出"还想再挤空间"的提示（DISM、HF_HOME 环境变量等）
- 报告按"做了什么 / 没做什么 / 为什么 / 后续建议"四段写

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 不检查服务直接清理 | 服务崩溃 | 检查端口 + 访问时间 |
| robocopy 后不校验 | 残缺副本 + 丢失源 | 字节数校验 |
| 直接删 `.cache\huggingface` | GPT-SoVITS 模型丢失 | 检查服务端口 9884 |
| 用 `LastWriteTime` 判断活跃度 | 安装包被误判 | 用 `LastAccessTime` |
| 把 conda env 当 cache 清 | TTS 服务 Python 没了 | 检查 python 进程路径 |
| 一次性删 30 GB 不可逆操作 | 出错无回滚 | 分 Tier + 校验 |

## 关联技能

- `port-config-audit` — 端口一致性（清理时验证服务端口）
- `process-tree-cleanup` — 进程清理（前置检查）
- `extract-skills-from-history` — 本技能来源

## 关联规则

- `C:\Users\wsz\Desktop\disk-cleanup.ps1` — 桌面上的清理脚本（参考实现）
- `tts-mvp\start-gpt-sovits.ps1` — GPT-SoVITS 启动（涉及 conda env + 端口 9884）

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-06 | 创建技能 | 7bc0ab44 对话清理 23 GB + 发现"服务端口验证"模式 |