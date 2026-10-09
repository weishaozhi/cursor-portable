# RULE: 架构与模块设计规范

## 触发条件
- 设计新模块或服务
- 修改现有架构
- 添加新的技术栈组件
- 重构代码结构

## 强制约束

### 1. 技术栈一致性

#### 后端标准栈
- **Python 3.9+**
- **FastAPI** - Web 框架（单进程服务）
- **Pydantic** - 数据验证
- **pytest** - 测试框架
- **logging** - 日志（使用 `basicConfig`）

#### 前端标准栈
- **Vue 3** + **TypeScript**
- **Pinia** - 状态管理
- **Vite** - 构建工具
- **Axios** - HTTP 客户端

#### 数据存储
- **JSON 文件** - 配置和小型数据集
- **SQLite** - 需要查询的结构化数据（如 md_editor）
- 禁止引入重型数据库（PostgreSQL/MySQL）除非有明确需求

### 2. 模块划分原则

每个项目必须遵循清晰的分层结构：

#### 后端结构（标准）
```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI 应用入口
│   ├── core/
│   │   └── config.py        # 配置、常量
│   ├── models/              # 数据模型（Pydantic/ORM）
│   ├── services/            # 业务逻辑层
│   ├── api/
│   │   └── routes.py        # API 路由
│   └── utils/               # 工具函数
├── requirements.txt
└── tests/
```

#### 前端结构（标准）
```
frontend/
├── src/
│   ├── main.ts
│   ├── App.vue
│   ├── api/                 # API 调用封装
│   ├── components/          # Vue 组件
│   ├── stores/              # Pinia stores
│   ├── types/               # TypeScript 类型定义
│   └── utils/               # 工具函数
├── package.json
└── vite.config.ts
```

### 3. 架构文档要求（arch.md）

每个项目的 `docs/project/arch.md` 必须包含：

#### 必需章节
1. **系统概览**：架构图（ASCII 或 Mermaid）
2. **模块划分**：表格列出模块、路径、职责
3. **数据流**：关键路径的数据流图
4. **技术栈速览**：表格列出层级和选型
5. **部署/启动链路**：本地开发和生产部署命令
6. **目录结构**：完整的文件树
7. **可观测性**：日志、健康检查、监控
8. **已知架构债**：引用 `project_state.md` 的 ISS 编号

#### 示例模块划分表格
```markdown
| 模块 | 路径 | 职责 |
|------|------|------|
| 配置 | `core/config.py` | 常量定义、路径配置 |
| 装备模型 | `models/equipment.py` | 装备数据结构、装备库 |
| 求解服务 | `services/solver.py` | DFS 搜索、Memo 缓存 |
```

### 4. 数据流文档化

关键业务流程必须在 `arch.md` 中绘制数据流：

```
1. 用户输入: 热血=4, 专注=2
        ↓
2. API 解析目标 → ["热血", "热血", "热血", "热血", "专注", "专注"]
        ↓
3. Service 加载数据（data/*.json）
        ↓
4. Solver 执行搜索算法
        ↓
5. 返回排序后的方案列表
```

### 5. API 设计规范

#### RESTful 约定
- **GET** - 查询资源（幂等）
- **POST** - 创建资源或非幂等操作
- **PUT** - 完整更新资源
- **PATCH** - 部分更新资源
- **DELETE** - 删除资源

#### 路由组织
```python
/api/auth/          # 认证相关
/api/files/         # 文件管理
/api/tools/         # 工具管理
/api/<resource>/    # 资源端点
```

#### 响应格式
成功：
```json
{
  "data": { ... },
  "count": 10
}
```

错误：
```json
{
  "detail": "错误信息"
}
```

### 6. 配置管理

#### 配置文件优先级
1. **环境变量** - 敏感信息（不提交）
2. **config.yaml** - 端口、超时等可配置项
3. **core/config.py** - 硬编码常量（如词缀列表）

#### 单一来源原则
- 端口号**仅在 config.yaml 定义**
- 路径使用 `Path(__file__).parent` 计算，不硬编码
- 敏感信息（密钥、密码）通过环境变量或 `.env` 文件

### 7. 进程管理（仅 toolbox_hub）

#### 单进程工具
- 直接通过 `subprocess.Popen` 启动
- 使用 `CREATE_NEW_PROCESS_GROUP` 隔离
- 健康检查：HTTP GET + 2xx 响应

#### 多进程工具
- **必须**通过 launcher 包装
- Launcher 负责子进程生命周期管理
- 任一子进程退出 → 强制终止所有子进程

## 架构调整工作流

### 修改前
1. 在 `arch.md` 中描述现状
2. 识别需要变更的模块
3. 评估影响范围（修改边界）

### 修改中
1. **先更新** `arch.md` 的对应章节
2. 在 `project_state.md` 新建 ISS 跟踪变更
3. 执行代码修改
4. 更新测试

### 修改后
1. 验证架构图与代码一致
2. 更新 ISS 状态为 🟩
3. 在 `arch.md` 变更记录中登记

## 可观测性要求

### 日志规范
```python
import logging

LOGGER = logging.getLogger(__name__)

# 关键路径必须打日志
LOGGER.info("启动服务: %s", service_name)
LOGGER.warning("配置缺失: %s", config_key)
LOGGER.error("操作失败: %s", error_msg, exc_info=True)
```

### 健康检查端点
每个 Web 服务必须提供：
```python
@app.get("/health")
def health_check():
    return {"status": "ok"}
```

### 进程监控（toolbox_hub）
- 子进程日志写入 `logs/<id>.log`
- 健康检查超时 12 秒
- 进程退出时记录退出码

## 禁止行为

### 架构反模式
- ❌ 架构调整不更新 `arch.md`
- ❌ 在多个地方硬编码同一个配置值
- ❌ 直接在路由层写业务逻辑（应在 services/ 层）
- ❌ 前端直接操作 localStorage 存储业务数据（应通过 API）

### 技术债务
- ❌ 引入新技术栈不在 `arch.md` 中说明理由
- ❌ 临时方案不在 `project_state.md` 登记为 ISS
- ❌ 跨项目复制代码（应抽取共享库或通过 API 调用）

### 依赖管理
- ❌ 使用未固定版本的依赖（requirements.txt 必须锁版本）
- ❌ 引入重型依赖解决简单问题（如为了一个 HTTP 请求引入 requests）
- ❌ 不更新 `requirements.txt` 或 `package.json`

## 参考模板

查看以下项目作为架构参考：
- **ciallo** - 标准的 FastAPI + Vue 3 架构
- **toolbox_hub** - 多进程管理架构
- **md_editor** - SQLite + 协作功能架构
