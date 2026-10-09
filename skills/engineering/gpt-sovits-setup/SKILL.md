---
name: gpt-sovits-setup
version: 1.1.0
created: 2026-10-03
last_used: 2026-10-06
usage_count: 0
tags: [engineering, tts, gpt-sovits, model-setup, voice-cloning, multi-arm]
scope: project
overlap_with: [tts-mvp-provider-integration, port-config-audit]
---

# gpt-sovits-setup

在 Windows 上搭建 GPT-SoVITS 服务（用于 tts-mvp 或独立使用）的完整流程。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："GPT-SoVITS 配置"、"GPT-SoVITS 模型下载"、"语音克隆"
- 用户提到端口 9880（GPT-SoVITS API）或 9881（sidecar）
- 路径出现 `D:\ai\GPT-SoVITS-*` 或 `GPT_SoVITS/pretrained_models`
- 用户引用 `@tts-mvp` 并要求 GPT-SoVITS 相关操作

## 安装位置

| 路径 | 内容 |
|------|------|
| `D:\AI\GPT-SoVITS-20250606v2pro\` | 主项目（含 api_v2.py） |
| `D:\AI\GPT-SoVITS-20250606v2pro\GPT_SoVITS\pretrained_models\` | 模型目录 |
| `D:\AI\GPT-SoVITS-20250606v2pro\configs\tts_infer_v1.yaml` | v1 配置 |
| `C:\Users\wsz\miniconda3\envs\gpt-sovits\` | conda 环境 |

## 必需模型文件

启动 `api_v2.py` 之前，下列文件必须存在：

| 模型 | 文件 | 大小 |
|------|------|------|
| BERT | `GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large/` | ~2GB |
| HuBERT | `GPT_SoVITS/pretrained_models/chinese-hubert-base/fairseq/speech_chinese-hubert-base-fairseq-ckpt.pt` | ~1.1GB |
| T2S | `GPT_SoVITS/pretrained_models/s1bert25hz-2kh-longer-epoch=68e-step=50232.ckpt` | ~148MB |
| VITS | `GPT_SoVITS/pretrained_models/s2G488k.pth` | ~101MB |

### 模型下载命令

```powershell
# ModelScope（国内推荐）
modelscope download --model iic/speech_chinese-hubert-base --local_dir D:\AI\GPT-SoVITS-20250606v2pro\GPT_SoVITS\pretrained_models\chinese-hubert-base

# Hugging Face
huggingface-cli download TencentGamePlayer/chinese-hubert-base --local-dir ...
```

**关键陷阱**：API 需要 `chinese-hubert-base/` 作为**目录**（含 `fairseq/` 子目录），不是单个文件。需要将 `.pt` 移动到 `chinese-hubert-base/fairseq/speech_chinese-hubert-base-fairseq-ckpt.pt`。

## 端口架构（与 tts-mvp 集成时）

| 端口 | 进程 | 启动延迟 |
|------|------|----------|
| 9880 | GPT-SoVITS API_v2 | **90 秒**（模型加载） |
| 9881 | tts-mvp Python sidecar | 5 秒 |
| 8787 | tts-mvp Node API | 5 秒 |

**必须按顺序启动**：API(9880) → sidecar(9881) → Node(8787)

## v1 配置文件

文件路径：`D:\AI\GPT-SoVITS-20250606v2pro\configs\tts_infer_v1.yaml`

```yaml
v1:
  bert_base_path: GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large
  cnhuhbert_base_path: GPT_SoVITS/pretrained_models/chinese-hubert-base
  device: cuda
  is_half: true
  t2s_weights_path: GPT_SoVITS/pretrained_models/s1bert25hz-2kh-longer-epoch=68e-step=50232.ckpt
  version: v1
  vits_weights_path: GPT_SoVITS/pretrained_models/s2G488k.pth
```

启动 API 时指定 config：

```powershell
python api_v2.py -a 127.0.0.1 -p 9880 -c configs\tts_infer_v1.yaml
```

## 启动流程

### Step 1：验证模型文件

```powershell
$modelDir = "D:\AI\GPT-SoVITS-20250606v2pro\GPT_SoVITS\pretrained_models"
Test-Path "$modelDir\chinese-roberta-wwm-ext-large"
Test-Path "$modelDir\chinese-hubert-base\fairseq\speech_chinese-hubert-base-fairseq-ckpt.pt"
Test-Path "$modelDir\s1bert25hz-2kh-longer-epoch=68e-step=50232.ckpt"
Test-Path "$modelDir\s2G488k.pth"
```

### Step 2：启动 GPT-SoVITS API（9880）

```powershell
cd /d D:\AI\GPT-SoVITS-20250606v2pro
C:\Users\wsz\miniconda3\envs\gpt-sovits\python.exe api_v2.py `
    -a 127.0.0.1 -p 9880 `
    -c configs\tts_infer_v1.yaml `
    > D:\ai\projects\tts-mvp\python\gpt-sovits-api.log 2>&1

# 等待 90 秒让模型加载完成
Start-Sleep -Seconds 90

# 验证
netstat -ano | findstr ":9880.*LISTENING"
curl http://127.0.0.1:9880/control
```

### Step 3：启动 sidecar（9881）

`d:\ai\projects\tts-mvp\python\gpt_sovits_server.py` 是 sidecar，负责：

- 将 tts-mvp 的 `SynthesisRequest` 转换为 GPT-SoVITS API 格式
- 处理参考音频路径、prompt text 等

**最常见的 bug**（2026-09-08 修复）：

```python
# ❌ 错误（丢失 /tts 路径）
response = requests.get(API_URL, ...)

# ✅ 正确（使用 f-string）
response = requests.get(f"{API_URL}/tts", ...)
```

### Step 4：启动 Node API（8787）

参见 `tts-mvp-provider-integration` 技能。

### Step 5：端到端测试

```powershell
curl -X POST http://127.0.0.1:8787/api/tts/jobs `
    -H "Content-Type: application/json" `
    -d '{"text":"你好晓辰，端到端测试。","provider":"gpt-sovits","voiceId":"xiaochen","speed":1.0,"pitch":0,"volume":100}'
```

期望返回：201 Created + `provider: gpt-sovits` + `status: completed`。

## 声音克隆流程

### 准备材料

1. **参考音频**：3-10 秒干净人声（无背景音乐）
2. **参考文本**：音频对应的精确文字

### Step 1：放置音频

```
d:\ai\projects\tts-mvp\data\reference-audio\xiaochen.wav
```

### Step 2：配置 sidecar 调用

```json
{
  "text": "要合成的新文本",
  "text_lang": "zh",
  "ref_audio_path": "d:\\ai\\projects\\tts-mvp\\data\\reference-audio\\xiaochen.wav",
  "prompt_text": "为什么你天天护肤，脸还是又黄又暗？",
  "prompt_lang": "zh",
  "top_k": 5,
  "top_p": 1,
  "temperature": 1,
  "text_split_method": "cut5",
  "batch_size": 1,
  "speed_factor": 1.0,
  "streaming_mode": false
}
```

### Step 3：调用 API

```powershell
curl -X POST http://127.0.0.1:9880/tts `
    -H "Content-Type: application/json" `
    -d @{...} | ConvertTo-Json -Compress
```

## 常见错误与解决

### 错误 1：英文合成报 NLTK 错误

```
LookupError: Resource cmudict not found
```

**解决**：

```powershell
C:\Users\wsz\miniconda3\envs\gpt-sovits\python.exe -m nltk.downloader -d D:\AI\GPT-SoVITS-20250606v2pro\GPT_SoVITS\pretrained_models\nltk_data cmudict
```

来源：对话 `41412804-aec3-499d-ab48-8866996f4c8d`

### 错误 2：sidecar 报 404

```
requests.exceptions.MissingSchema: Invalid URL 'None'
```

**根因**：sidecar 调用 GPT-SoVITS API 时路径错误（缺 `/tts`）。修复 `f"{API_URL}/tts"`。

### 错误 3：模型加载超时

```
API 启动 90 秒后仍未监听 9880
```

**检查**：

```powershell
# 查看日志
type D:\ai\projects\tts-mvp\python\gpt-sovits-api.log

# 找 GPU 占用
nvidia-smi
```

### 错误 4：CUDA OOM

```
torch.cuda.OutOfMemoryError
```

**解决**：

1. 关闭其他 GPU 进程
2. 修改 `is_half: false` 降低精度
3. 使用更短的参考音频

## 实际案例

### 案例 1：完整搭建流程（2026-09-08）

来源：对话 `91a53769` + `94d8d572` + `6a9c7ada`

**步骤**：

1. 创建 `chinese-hubert-base/fairseq/` 目录并复制 `.pt` 文件
2. 创建 `configs/tts_infer_v1.yaml`
3. 启动 API（90 秒等待）
4. 修复 sidecar 的 `f"{API_URL}/tts"` bug
5. 重启 Node API
6. 端到端测试生成 `frontend_e2e.wav`

**结果**：5+ 轮迭代后，端到端中文合成成功。

### 案例 2：从 MP3 克隆新音色（2026-10-01）

来源：对话 `1c1a0c7b-40a7-42f3-a5a8-2ce0774ef474`

**任务**：用 GPT-SoVITS 克隆 `C:\Users\wsz\Videos\202610010012.mp3` 的音色

**步骤**：

1. 提取 3-10 秒参考音频片段
2. 转写参考文本
3. 放入 `data/reference-audio/` 目录
4. 配置 sidecar 调用（参考上方的 step 2）
5. 调用 `/tts` 端点

## 注意事项

### 必须遵守

- **强制** 按顺序启动：9880 → 9881 → 8787
- **强制** API 启动后等待 90 秒（模型加载时间）
- **强制** 模型文件路径与 v1 config 完全一致
- **强制** 英文合成前安装 NLTK cmudict
- **禁止** 修改 `api_v2.py` 中的默认路径
- **禁止** 多个 GPT-SoVITS 实例共用同一 v1 config

### 推荐实践

- 所有日志重定向到 `D:\ai\projects\tts-mvp\python\*.log`，便于排查
- sidecar 启动脚本加入"等待 API 就绪"的轮询逻辑
- 使用 `gpt-sovits-api.log` 监控加载进度
- 参考音频建议采样率 22050Hz 单声道 WAV

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 不等 90 秒就启动 sidecar | sidecar 调用失败 | 启动后等待 + 轮询 `/control` |
| 复用旧 config | 模型加载失败 | 创建专用 `tts_infer_v1.yaml` |
| 改默认模型路径 | 多人开发时配置漂移 | 用 config 显式指定 |
| NLTK 数据放错位置 | 英文失败 | 指定 `-d` 到项目目录 |

## 关联技能

- `tts-mvp-provider-integration` — tts-mvp 中 provider 集成
- `port-config-audit` — 端口一致性审计
- `process-tree-cleanup` — 清理 GPT-SoVITS 残留进程

## 关联规则

- `GPT-SoVITS-20250606v2pro\configs\tts_infer_v1.yaml` — v1 配置
- `tts-mvp\python\gpt_sovits_server.py` — sidecar 实现

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-03 | 创建技能 | 5+ 次 GPT-SoVITS 配置/调试对话 |
| 2026-10-06 | 追加多臂配置 + 脚本转发器模式 + setup 脚本 | 2851e7c8 对话 |

## 多臂配置（Multi-Arm，2026-10-06 追加）

需要同时运行多个 GPT-SoVITS 权重组合时（例如 V2 / V3 各一臂），使用**配置驱动**而非硬编码。

### 文件结构

```
tts-mvp/
├── config/
│   └── arms.json           # 臂表（核心配置）
├── scripts/
│   ├── start-gpt-sovits.ps1          # 新：配置驱动启动器
│   └── start-gpt-sovits-ab.ps1       # 旧：作为转发器保留
└── ...
```

### config/arms.json 示例

```json
{
  "arms": [
    {
      "id": "v2",
      "label": "晓辰 V2",
      "host": "127.0.0.1",
      "port": 9880,
      "t2s_weights": "models/xiaochen_v2-e25.ckpt",
      "vits_weights": "models/xiaochen_v2_e15_s315.pth",
      "config_template": "tts_infer_arm_v2.yaml"
    },
    {
      "id": "v3",
      "label": "晓辰 V3",
      "host": "127.0.0.1",
      "port": 9882,
      "t2s_weights": "models/xiaochen_v3-e30.ckpt",
      "vits_weights": "models/xiaochen_v3_e20_s315.pth",
      "config_template": "tts_infer_arm_v3.yaml"
    }
  ]
}
```

### start-gpt-sovits.ps1（配置驱动）

```powershell
[CmdletBinding()]
param(
    [string[]]$Arms,           # 指定 arm id，如 v2,v3；空 = 全部
    [switch]$Stop,             # 停止指定 arm
    [switch]$SyncEnv           # 同步 conda env
)

# 1. 读配置
$config = Get-Content "config\arms.json" -Raw | ConvertFrom-Json
$allArms = $config.arms

# 2. 筛选
if ($Arms) {
    $targets = $allArms | Where-Object { $_.id -in $Arms }
} else {
    $targets = $allArms
}

# 3. 生成 yaml（运行时）
foreach ($arm in $targets) {
    $yamlPath = "$PSScriptRoot\..\GPT-SoVITS-20250606v2pro\configs\$($arm.config_template)"
    @"
v1:
  bert_base_path: GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large
  cnhuhbert_base_path: GPT_SoVITS/pretrained_models/chinese-hubert-base
  device: cuda
  is_half: true
  t2s_weights_path: $arm.t2s_weights
  version: v1
  vits_weights_path: $arm.vits_weights
"@ | Set-Content $yamlPath
}

# 4. 启动 / 停止
foreach ($arm in $targets) {
    if ($Stop) {
        # 按 arm.id + config_template 匹配进程（不再按旧的 xiaochen_ab_v*.yaml）
        Get-Process python -EA SilentlyContinue | Where-Object {
            $_.CommandLine -like "*$($arm.config_template)*"
        } | Stop-Process -Force
    } else {
        # 启动
        Start-Process -FilePath $python `
            -ArgumentList "api_v2.py","-a",$arm.host,"-p",$arm.port,"-c","configs\$($arm.config_template)" `
            -RedirectStandardOutput "logs\gpt-sovits-$($arm.id).log"
    }
}
```

### 关键改进

| 维度 | 旧（硬编码） | 新（配置驱动） |
|------|-------------|---------------|
| 臂表 | 在脚本默认参数里 | `config/arms.json` |
| yaml 文件名 | `tts_infer_xiaochen_ab_v2.yaml` | `tts_infer_arm_v2.yaml`（运行时生成） |
| 端口 | 硬编码 9880/9881 | 配置指定 |
| 权重路径 | 硬编码 | 配置指定 |
| 启动器 | 一个文件管所有 | 同一个文件读 config |
| Stop 匹配 | 模糊（易失效） | 精确（按 config_template） |

## 脚本转发器模式（2026-10-06 追加）

重构脚本名/参数时，**旧脚本必须保留并改为转发器**，否则会产生"静默失效"——比没有脚本更糟糕。

### 反例：直接删除或重命名旧脚本

```powershell
# 用户在终端历史里还有这条命令
.\scripts\start-gpt-sovits-ab.ps1 -Stop

# 旧脚本按 tts_infer_xiaochen_ab_v2.yaml 匹配进程
# 现在跑着的进程用的是 tts_infer_arm_v2.yaml
# → 匹配不到 → 打印「无进程」→ exit 0
# → 两臂其实还在占着 4GB+4GB=8GB 显存
# → 用户以为停了，实际没停
```

### 正解：旧脚本作为转发器

```powershell
# scripts\start-gpt-sovits-ab.ps1（新内容）
<#
.SYNOPSIS
    已废弃：请改用 scripts\start-gpt-sovits.ps1。
#>
[CmdletBinding()]
param(
    [string]$Repo = '',
    [int]$V2Port = 0,
    [int]$V3Port = 0,
    [string]$Python = '',
    [string]$LogDir = '',
    [switch]$V2Only,
    [switch]$V3Only,
    [switch]$Stop
)

$target = Join-Path $PSScriptRoot 'start-gpt-sovits.ps1'

# 旧参数在新脚本里没有对应物 → 显式警告
$ignored = @()
if ($Repo)    { $ignored += "-Repo $Repo" }
if ($V2Port)  { $ignored += "-V2Port $V2Port" }
if ($V3Port)  { $ignored += "-V3Port $V3Port" }
if ($Python)  { $ignored += "-Python $Python" }
if ($LogDir)  { $ignored += "-LogDir $LogDir" }
if ($ignored.Count) {
    Write-Host "已废弃的 start-gpt-sovits-ab.ps1：忽略参数 $($ignored -join ', ')" -ForegroundColor Yellow
    Write-Host "  端口与权重现在只来自 config\arms.json（python 解释器认 .env / PATH）" -ForegroundColor Yellow
}

# 旧参数映射到新参数
$forward = @{}
if ($Stop) { $forward['Stop'] = $true }
if ($V2Only -and $V3Only)      { $forward['Arms'] = @() }
elseif ($V2Only)               { $forward['Arms'] = @('v2') }
elseif ($V3Only)               { $forward['Arms'] = @('v3') }

Write-Host "（转发到 scripts\start-gpt-sovits.ps1）" -ForegroundColor DarkGray
& $target @forward
exit $LASTEXITCODE
```

### 转发器设计要点

| 要求 | 原因 |
|------|------|
| 保留旧脚本，不要直接删除 | 用户的终端历史、文档引用还在 |
| 显式警告被忽略的参数 | 不能静默 drop（-Stop 静默 drop 会留进程） |
| 转发 exit code | 错误传播给调用者 |
| 转发关键参数 | `-Stop`、`-V2Only`、`-V3Only` 必须仍生效 |
| 在脚本顶部写 SYNOPSIS | 用户能立刻看到"已废弃" |

## 完整 setup 脚本（2026-10-06 追加）

`tts-mvp` 项目的 setup 脚本结构（位于 `scripts/setup/`）：

```
scripts/
├── setup/
│   ├── check-env.ps1                  # 只读体检
│   ├── install-deps.ps1               # 安装依赖（conda env、Python 包）
│   ├── fetch-pretrained-models.ps1     # 下载预训练模型
│   ├── fetch-trained-weights.ps1      # 导入训练好的权重
│   ├── train-voice.ps1                # 训练新音色
│   └── register-voice.ps1             # 注册音色到 tts-mvp
├── start-gpt-sovits.ps1               # 启动 GPT-SoVITS（配置驱动）
├── start-gpt-sovits-ab.ps1            # 已废弃，转发器
├── start-qwen3-tts.ps1
└── test-qwen3-tts.ps1
```

### 标准 setup 脚本模式

| 脚本 | 必须支持 flag |
|------|-------------|
| `check-env.ps1` | `-Help`、`-Json` |
| `install-deps.ps1` | `-SkipConda`、`-SkipGptSovits`、`-SkipModels`、`-CondaEnv`、`-GptSovitsUrl`、`-GptSovitsRoot` |
| `fetch-pretrained-models.ps1` | `-GptSovitsRoot`、`-HfEndpoint`、`-Retries` |
| `fetch-trained-weights.ps1` | `-Source`、`-Interactive`、`-Force`、`-NoVerify` |
| `train-voice.ps1` | `-VoiceId`、`-RefAudio`、`-RefText`、`-SovitsEpochs`、`-GptEpochs`、`-SovitsBs`、`-SovitsSeg`、`-SovitsGradCkpt`、`-GptBs`、`-EvalEpochs`、`-QuickTest`、`-SkipStage1`、`-DryRun` |
| `register-voice.ps1` | `-VoiceId`、`-RefAudio`、`-RefText`、`-Name`、`-Description`、`-SovitsWeights`、`-Sample`、`-Forget` |

所有脚本必须有 `[CmdletBinding()]` + `Get-Help` 友好帮助。