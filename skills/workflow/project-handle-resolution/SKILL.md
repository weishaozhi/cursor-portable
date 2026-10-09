---
name: project-handle-resolution
version: 1.0.0
created: 2026-10-03
last_used: 2026-10-03
usage_count: 0
tags: [workflow, project-resolution, d-of-ai-projects, handle, routing]
scope: project
overlap_with: []
---

# project-handle-resolution

解析用户消息中的 `@project-name` 引用，定位到 `d:\ai\projects\project-name` 目录。

## 触发条件

满足以下任一条件时自动加载：

- 用户消息包含 `@<name>` 形式的引用（如 `@tts-mvp`、`@toolbox_hub`）
- 用户说："在 XXX 项目中"、"XXX 项目里"、并且项目在 `d:\ai\projects\` 下
- 工作目录为 `d:\ai\projects` 时，所有项目引用都需要解析

## 解析规则

### 基础规则

```
@project-name
   ↓
去除前缀 @
   ↓
在 d:\ai\projects\<project-name> 中查找
   ↓
找到 → 进入该目录操作
未找到 → 询问用户或列出相似项目
```

### 已知项目映射

| 引用 | 路径 | 说明 |
|------|------|------|
| `@tts-mvp` | `d:\ai\projects\tts-mvp` | 多 provider TTS 服务 |
| `@toolbox_hub` | `d:\ai\projects\toolbox_hub` | 服务编排中心 |
| `@toolboxhub` | `d:\ai\projects\toolbox_hub` | 同上（无下划线） |
| `@video-subtitle-remover` | `d:\ai\projects\video-subtitle-remover` | 视频字幕移除 |
| `@video_summarizer` | `d:\ai\projects\video_summarizer` | 视频摘要 |
| `@ciallo` | `d:\ai\projects\ciallo` | 历史项目 |
| `@md_editor` | `d:\ai\projects\md_editor` | Markdown 编辑器 |

**注意**：`@toolbox_hub` 和 `@toolboxhub` 是同一项目。用户口语中常省略下划线。

## 解析步骤

### Step 1：识别引用

扫描用户消息中的 `@<name>` 模式：

```powershell
# 示例消息
"@tts-mvp 帮我添加一个音色"

# 提取
$refs = @('tts-mvp')
```

### Step 2：验证目录存在

```powershell
$path = "d:\ai\projects\$ref"
if (Test-Path $path) {
    # 找到
} else {
    # 未找到
}
```

### Step 3：处理多种形态

如果用户用 `@project_name`（下划线）或 `@project-name`（连字符），**两种都尝试**：

```powershell
$candidates = @(
    "d:\ai\projects\$ref",                  # 原样
    "d:\ai\projects\$($ref -replace '_', '-')",  # 下划线→连字符
    "d:\ai\projects\$($ref -replace '-', '_')"   # 连字符→下划线
)

foreach ($c in $candidates) {
    if (Test-Path $c) {
        $resolved = $c
        break
    }
}
```

### Step 4：未找到时的处理

```powershell
if (-not $resolved) {
    # 列出所有相似项目
    Get-ChildItem d:\ai\projects | Where-Object { $_.Name -like "*$ref*" }
    
    # 询问用户
}
```

## 完整解析模板

```powershell
function Resolve-ProjectHandle {
    param([string]$Handle)
    
    # 去除 @
    $name = $Handle -replace '^@', ''
    
    # 候选路径
    $candidates = @(
        "d:\ai\projects\$name",
        "d:\ai\projects\$($name -replace '_', '-')",
        "d:\ai\projects\$($name -replace '-', '_')"
    )
    
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return (Resolve-Path $c).Path
        }
    }
    
    # 未找到，列出相似项
    Write-Host "未找到项目 '$name'，相似项目：" -ForegroundColor Yellow
    Get-ChildItem d:\ai\projects | Where-Object { 
        $_.Name -like "*$name*" 
    } | Select-Object -ExpandProperty Name
    
    return $null
}

# 使用
$path = Resolve-ProjectHandle '@tts-mvp'
# 返回: d:\ai\projects\tts-mvp
```

## 在工具调用中使用

```powershell
# 例：用户说 "@tts-mvp 调用 Qwen 接口报错"
# 解析后
$projectPath = "d:\ai\projects\tts-mvp"

# 然后定位代码
Get-ChildItem "$projectPath\server" -Recurse | Where-Object { $_.Name -like "*.ts" }
```

## 实际案例

### 案例 1：@tts-mvp 解析

**用户消息**：`@tts-mvp 调用 Qwen 接口报错 fetch failed`

**解析过程**：

1. 提取 handle：`tts-mvp`
2. 验证 `d:\ai\projects\tts-mvp` 存在 ✓
3. 进入 `server\providers\` 查找 Qwen 相关代码
4. 定位 `server\providers\qwen3-tts.ts` 或相关 sidecar

**对应对话**：`4a88a259-73bb-4690-a92f-11cb5b9a9176`

### 案例 2：@toolbox_hub 启动失败

**用户消息**：`toolboxhub @toolbox_hub 无法正常启动了`

**特殊情况**：

- 同时出现 `toolboxhub`（裸）和 `@toolbox_hub`（带 @）
- 两者指向同一项目
- 解析时优先匹配带 `@` 的版本

**对应对话**：`5b8b8579-3b13-4427-909f-a98ffdd4f798`

### 案例 3：@video-subtitle-remover 进度查询

**用户消息**：`@video-subtitle-remover 帮我看看这个项目进行到哪一步了`

**解析**：直接进入 `d:\ai\projects\video-subtitle-remover`，读取 README 和 git log

**对应对话**：`4dad69a7-dc08-436a-a215-51f1f6f0b6a7`

### 案例 4：@video_summarizer 集成 TTS

**用户消息**：`@video_summarizer 接入 chat tts`

**解析**：下划线 handle，路径 `d:\ai\projects\video_summarizer`

**对应对话**：`1fbe8cfd-ab55-4fa2-b6b0-0a572be65228`

## 注意事项

### 必须遵守

- **强制** 所有 `@<name>` 必须解析到 `d:\ai\projects\<name>` 或变体
- **强制** 找不到时不要假设，必须列出候选项询问用户
- **强制** 处理下划线/连字符的等价变体
- **禁止** 把 `@` 视为邮箱或社交媒体提及
- **禁止** 把 `@project-name` 误解析为 `@project` 或 `@name`

### 推荐实践

- 解析后立即 `cd` 进入项目目录
- 对长 handle 使用模糊匹配辅助（如 `@tts` → `tts-mvp`）
- 项目改名时同步更新已知项目映射表
- 跨多个 `@` 引用时一次性全部解析

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 把 `@xxx` 当作邮箱忽略 | 错失项目上下文 | 优先解析 handle |
| 不验证目录直接操作 | 路径错误 | 先 `Test-Path` |
| 硬编码某个 handle | 不可维护 | 用映射表 |
| 把裸名和 `@` 视为不同项目 | 重复条目 | 等价化处理 |

## 关联技能

- `tts-mvp-provider-integration` — `@tts-mvp` 操作时使用
- `gpt-sovits-setup` — `@tts-mvp` 的 GPT-SoVITS 配置
- `port-config-audit` — `@toolbox_hub` 中端口审计

## 关联规则

- 工作目录为 `d:\ai\projects\` 时自动启用此技能
- `.cursor\projects\d-ai-projects\` 是本技能所在项目

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-03 | 创建技能 | 6+ 次 `@xxx` 项目引用对话 |