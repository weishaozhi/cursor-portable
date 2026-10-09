---
name: tts-mvp-provider-integration
version: 1.0.0
created: 2026-10-03
last_used: 2026-10-03
usage_count: 0
tags: [engineering, tts, tts-mvp, provider, integration, sidecar]
scope: project
overlap_with: [port-config-audit, process-tree-cleanup, gpt-sovits-setup]
---

# tts-mvp-provider-integration

向 `d:\ai\projects\tts-mvp` 项目接入新的 TTS provider 时遵循的固定步骤清单。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："接入 XXX-TTS"、"添加新的 TTS 引擎"、"provider 集成"
- 用户引用 `@tts-mvp` 且要求新增/修改 TTS 后端
- 在 `d:\ai\projects\tts-mvp\server\providers\` 下创建或调整 provider 文件
- 修改 `tts-mvp\server\routes.ts` 或 `voices.ts` 中 providerVoiceId 映射

## 项目端口矩阵

tts-mvp 使用**多进程分层架构**，每个 provider 占用独立端口：

| 进程 | 端口 | 用途 |
|------|------|------|
| Node API（主服务） | 8787 | Express + 路由 + 任务调度 |
| gpt-sovits API | 9880 | GPT-SoVITS 自带的 API_v2 |
| gpt-sovits sidecar | 9881 | 轻量包装层，处理 9880 路径 |
| qwen3-tts sidecar | 9882 | Python HTTP 封装 qwen-tts |

**新增 provider 时分配下一个空闲端口**（9883、9884...），参考 `gpt-sovits-setup` skill。

## 核心架构

```
浏览器 ──> Node API (8787)
              ├─ mock         (内置, 无 sidecar)
              ├─ chattts      (内置, 无 sidecar)
              ├─ edge-tts     (内置, Python 包直接调用)
              ├─ gpt-sovits   ──> sidecar (9881) ──> gpt-sovits API (9880)
              └─ qwen3-tts    ──> sidecar (9882)
```

每个 provider 必须实现 `TtsProvider` 接口：

```typescript
// server/types.ts
export interface TtsProvider {
  id: ProviderId
  synthesize(request: SynthesisRequest): Promise<SynthesisResult>
}
```

## 标准接入清单

向 tts-mvp 接入一个新 provider（如 `provider-1`）需要改动以下 8 处：

### 1. `server/types.ts` — 注册 ProviderId

```typescript
export type ProviderId = 'mock' | 'chattts' | 'edge-tts' | 'gpt-sovits' | 'qwen3-tts' | 'provider-1'
```

### 2. `server/providers/provider-1.ts` — 实现 provider

```typescript
import type { TtsProvider, SynthesisRequest, SynthesisResult } from '../types'

export const provider1Provider: TtsProvider = {
  id: 'provider-1',
  async synthesize(req: SynthesisRequest): Promise<SynthesisResult> {
    // 调用 sidecar 或直接调用库
    const response = await fetch(`${process.env.PROVIDER1_URL}/synthesize`, { ... })
    return { audioUrl: '...', duration: 0 }
  }
}
```

### 3. `server/providers/index.ts` — 注册 provider

```typescript
import { provider1Provider } from './provider-1'

export const providers: Record<ProviderId, TtsProvider> = {
  // ... 已有 providers
  'provider-1': provider1Provider,
}
```

### 4. `server/routes.ts` — 更新两个分支

```typescript
function isProviderId(value: unknown): value is ProviderId {
  return value === 'mock' || value === 'chattts' || value === 'edge-tts'
         || value === 'gpt-sovits' || value === 'qwen3-tts' || value === 'provider-1'
}

// providerVoiceId 映射
const providerVoiceId =
  providerId === 'provider-1' ? (voice.providers.provider1 || 'default') :
  // ... 其他分支
```

### 5. `server/voices.ts` — 添加 voice 映射

```typescript
{
  id: 'xiaochen',
  name: '晓辰',
  providers: {
    // ... 已有映射
    provider1: 'SpeakerName',   // 新增
  }
}
```

### 6. `.env.example` 和 `.env` — 添加配置

```bash
PROVIDER1_URL=http://127.0.0.1:9883
PROVIDER1_TIMEOUT_MS=120000
PROVIDER1_DEFAULT_VOICE=default
```

### 7. `python/provider_1_server.py` — Python sidecar（仅当 provider 是重型 ML 模型时）

参考 `python/gpt_sovits_server.py` 或 `python/qwen3_tts_server.py` 实现。需要的端点：

- `GET /health` — 健康检查 + 模型加载状态
- `GET /voices` — 可用音色列表
- `POST /synthesize` — 合成接口

### 8. 启动 / 测试脚本

- `scripts/start-provider-1.ps1` — 启动 sidecar（含依赖检查）
- `scripts/test-provider-1.ps1` — 健康检查 + 中文/英文合成测试

## Provider 类型判断

**直接调用型**（无需 sidecar）：edge-tts、mock、chattts

**Sidecar 包装型**（需 Python HTTP 服务）：gpt-sovits、qwen3-tts、cosyvoice、fish-speech 等。

## 实际案例

### 案例 1：Qwen3-TTS 接入（2026-09-07）

来源：对话 `1463272c-b000-44dc-960b-f0f35e1178d2`

**完成的所有改动**（11 个文件）：

| 文件 | 操作 |
|------|------|
| `server/types.ts` | 添加 `qwen3-tts` 到 `ProviderId` |
| `server/providers/qwen3-tts.ts` | 新建（调用 sidecar 9882） |
| `server/providers/index.ts` | 注册 provider |
| `server/routes.ts` | `isProviderId` + `providerVoiceId` 双分支更新 |
| `server/voices.ts` | 9 个 voice 添加 `qwen3Tts` 映射 |
| `.env.example` + `.env` | `QWEN3_TTS_URL/PORT/MODEL/TIMEOUT_MS` |
| `python/qwen3_tts_server.py` | Python sidecar（含 model loading） |
| `python/requirements-qwen3-tts.txt` | pip 依赖 |
| `scripts/start-qwen3-tts.ps1` | 启动脚本（含依赖检查 + 模型下载提示） |
| `scripts/test-qwen3-tts.ps1` | 4 项测试（health/voices/中文/英文） |
| `docs/QWEN3_TTS_SETUP.md` | 配置文档（含故障排查） |

**结果**：Qwen3-TTS 完整集成，所有 provider 共享同一前端 UI。

### 案例 2：GPT-SoVITS 端到端联调（2026-09-08）

来源：对话 `6a9c7ada` + `94d8d572` + `41412804`

**涉及端口启动顺序**：

```powershell
# 1. GPT-SoVITS API（9880）—— 模型加载需 90 秒
cd D:\ai\GPT-SoVITS-20250606v2pro
C:\Users\wsz\miniconda3\envs\gpt-sovits\python.exe api_v2.py -a 127.0.0.1 -p 9880 -c configs\tts_infer_v1.yaml

# 2. sidecar（9881）—— 修复 f"{API_URL}/tts" 路径后启动
cd D:\ai\projects\tts-mvp
C:\Users\wsz\miniconda3\envs\gpt-sovits\python.exe python\gpt_sovits_server.py

# 3. Node API（8787）—— 重启读取新 .env
npm run dev:server

# 4. 端到端测试
curl -X POST http://127.0.0.1:8787/api/tts/jobs -d '{"provider":"gpt-sovits",...}'
```

**典型错误**：

- `f{API_URL}/tts` 缺失花括号（Python f-string）→ sidecar 调用 404
- NLTK 缺少 `cmudict` → 英文合成失败 → `python -m nltk.downloader -d /path/to/nltk_data cmudict`
- Node API 重启后端口仍被占 → 用 `process-tree-cleanup` 技能清理 tsx 残留

### 案例 3：edge-tts 音色对应（2026-09-07）

来源：对话 `eba53f6b-e495-42d4-a78f-bee0cd07a705`

**任务**：将 tts-mvp 中所有音色映射到 edge-tts 可用音色，删除未对应的。

**操作**：

1. 调用 edge-tts 的 `list_voices()` 获取全部可用音色
2. 遍历 `voices.ts`，把 `providers.edgeTts` 字段更新为对应的 edge-tts voice short name
3. 删除无对应 edge-tts 的 voice，或保留但标记为 edge-tts 不可用

## 注意事项

### 必须遵守

- **强制** ProviderId 修改后同步更新 `types.ts` 和 `routes.ts` 两处
- **强制** 端口分配避开现有端口（8787/9880/9881/9882）
- **强制** sidecar 必须实现 `/health` 端点（被 toolbox_hub 健康检查使用）
- **强制** 启动前用 `netstat -ano | findstr :PORT` 检查端口占用
- **禁止** 在 Node API 内直接 import 重型 ML 库（PyTorch / TensorFlow）
- **禁止** 修改端口号而不更新 `port-config-audit` 记录的端口矩阵

### 推荐实践

- 每个 provider 单独一个文件，方便禁用和调试
- `.env` 添加新配置后必须更新 `.env.example`
- 重型 provider 使用 Python sidecar 而非 Node 调用
- sidecar 启动脚本加入"依赖检查 + 模型下载提示"
- 文档放置在 `docs/{PROVIDER_NAME}_SETUP.md`，包含故障排查章节

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 只改 `types.ts` 不改 `routes.ts` | TS 编译通过但运行时 400 | 两个分支同时更新 |
| Node API 内 import PyTorch | 启动慢、内存爆炸 | 用 Python sidecar |
| 端口与其他 provider 冲突 | 启动失败 | 查端口矩阵分配新端口 |
| 忘了同步 `.env.example` | 其他开发者不知道配置项 | 每次配置变更同步 |
| 忘记添加 health 端点 | toolbox_hub 健康检查失败 | 必须实现 `/health` |

## 关联技能

- `gpt-sovits-setup` — GPT-SoVITS 专用配置
- `port-config-audit` — 多端口一致性审计（含 TTS 矩阵）
- `process-tree-cleanup` — sidecar 进程清理
- `extract-skills-from-history` — 本技能的来源

## 关联规则

- `tts-mvp\server\types.ts` — `TtsProvider` 接口定义
- `tts-mvp\server\providers\index.ts` — provider 注册表
- `tts-mvp\.env.example` — 配置项模板

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-10-03 | 创建技能 | 11+ 次 TTS provider 集成对话（Qwen3-TTS、GPT-SoVITS、edge-tts） |