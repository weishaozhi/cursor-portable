# RULE: API 设计与文档规范

## 触发条件
- 创建新的 API 端点
- 修改现有 API
- 编写 API 文档
- 设计数据模型

## 强制约束

### 1. API 文档必需（API.md）

对于包含 API 的项目，必须在 `docs/API.md` 中维护完整文档：

#### 必需章节
```markdown
# <Project> API 文档

Base URL: `http://localhost:<port>/api`

认证方式：[JWT / API Key / 无]

## <资源名> `/resource`

### 操作名
- **METHOD** `/path`
- **Headers:** `Authorization: Bearer <token>`
- **Query:** `param` (说明)
- **Body:**
```json
{ "field": "type" }
```
- **Response (2xx):**
```json
{ "data": {} }
```
```

#### 参考示例
查看 `md_editor/docs/API.md` 作为完整示例。

### 2. RESTful 设计原则

| HTTP 方法 | 用途 | 幂等性 | 示例 |
|----------|------|--------|------|
| **GET** | 查询资源 | ✅ | `GET /api/files` 获取文件列表 |
| **POST** | 创建资源 | ❌ | `POST /api/files` 创建新文件 |
| **PUT** | 完整更新 | ✅ | `PUT /api/files/1` 替换文件内容 |
| **PATCH** | 部分更新 | ✅ | `PATCH /api/files/1` 修改文件名 |
| **DELETE** | 删除资源 | ✅ | `DELETE /api/files/1` 删除文件 |

### 3. 路由命名约定

#### 资源路由
```
GET    /api/<resources>          # 列表（支持分页/过滤）
POST   /api/<resources>          # 创建
GET    /api/<resources>/<id>     # 详情
PUT    /api/<resources>/<id>     # 完整更新
PATCH  /api/<resources>/<id>     # 部分更新
DELETE /api/<resources>/<id>     # 删除
```

#### 嵌套资源
```
GET    /api/<resources>/<id>/<sub-resources>
POST   /api/<resources>/<id>/<sub-resources>
```

#### 操作端点（非资源）
```
POST   /api/<resources>/<id>/<action>
```
示例：
- `POST /api/files/1/restore` - 恢复文件
- `POST /api/versions/1/restore` - 恢复版本

### 4. 请求/响应格式

#### 成功响应（2xx）

**单个资源**：
```json
{
  "id": 1,
  "name": "资源名",
  "created_at": "2026-08-30T14:00:00"
}
```

**列表资源**：
```json
[
  { "id": 1, "name": "项目1" },
  { "id": 2, "name": "项目2" }
]
```

**操作结果**：
```json
{
  "message": "操作成功",
  "affected": 5
}
```

#### 错误响应（4xx/5xx）

**统一格式**：
```json
{
  "detail": "错误信息"
}
```

**常见状态码**：
| 状态码 | 含义 | 使用场景 |
|--------|------|----------|
| 200 | OK | 成功（GET/PUT/PATCH） |
| 201 | Created | 创建成功（POST） |
| 204 | No Content | 删除成功（DELETE） |
| 400 | Bad Request | 请求参数错误 |
| 401 | Unauthorized | 未认证或认证失败 |
| 403 | Forbidden | 无权限访问 |
| 404 | Not Found | 资源不存在 |
| 409 | Conflict | 资源冲突（如重复创建） |
| 500 | Internal Server Error | 服务器内部错误 |

### 5. 数据模型设计（Pydantic）

#### 请求模型
```python
from pydantic import BaseModel, Field
from typing import Optional

class FileCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    content: str = ""
    parent_id: Optional[int] = None
    is_folder: bool = False

class FileUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1)
    content: Optional[str] = None
    parent_id: Optional[int | str] = None  # 支持 "__none__" 哨兵
```

#### 响应模型
```python
from datetime import datetime

class FileResponse(BaseModel):
    id: int
    name: str
    path: str
    content: str
    parent_id: Optional[int]
    is_folder: bool
    owner_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True  # Pydantic v2
```

### 6. 特殊字段约定

#### 哨兵值（Sentinel Values）
用于区分 "不更新" 和 "设为 null"：

```python
# API 接受三种值：
# - null / 省略：不更新该字段
# - 整数（如 5）：设置为该值
# - "__none__"：显式设为 null

class FileUpdate(BaseModel):
    parent_id: Optional[int | str] = None

# 路由处理
if update_data.parent_id == "__none__":
    file.parent_id = None
elif update_data.parent_id is not None:
    file.parent_id = update_data.parent_id
# else: 保持原值
```

#### 时间戳格式
- 使用 ISO 8601：`2026-08-30T14:30:00`
- UTC 时区或明确标注时区
- Pydantic 自动序列化 `datetime` 对象

### 7. 查询参数规范

#### 分页
```
GET /api/files?page=1&page_size=20
```

#### 过滤
```
GET /api/files?parent_id=5&is_folder=false
```

#### 排序
```
GET /api/files?sort=-created_at,name
```
（`-` 表示降序）

#### 搜索
```
GET /api/files/search?q=关键字
```

### 8. 认证设计

#### JWT 认证（推荐）
```python
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    # 验证 token
    return user
```

**登录流程**：
```
POST /api/auth/login
Content-Type: application/x-www-form-urlencoded

username=user&password=pass

→ 200 OK
{
  "access_token": "eyJ...",
  "token_type": "bearer"
}
```

**使用 Token**：
```
GET /api/files
Authorization: Bearer eyJ...
```

### 9. WebSocket 规范（实时协作）

#### 连接
```
ws://localhost:8000/ws/<resource>/<id>?token=<jwt>
```

#### 消息格式
```json
{
  "type": "event_name",
  "user_id": 1,
  "username": "用户名",
  "data": { ... }
}
```

#### 消息类型约定
- `user_joined` / `user_left` - 用户进出
- `<resource>_update` - 资源更新
- `cursor_update` - 光标位置（协作编辑）

## API 文档维护工作流

### 新增端点
1. 在代码中实现路由 + Pydantic 模型
2. 在 `docs/API.md` 中添加完整文档
3. 包含请求示例和响应示例
4. 标注必填字段和可选字段

### 修改端点
1. 更新代码实现
2. **同时更新** `docs/API.md`
3. 如果是破坏性变更，在 `project_state.md` 登记

### 废弃端点
1. 在 `docs/API.md` 中标注 `[DEPRECATED]`
2. 在 `project_state.md` 登记移除计划
3. 保留至少一个版本周期后再删除

## 推荐实践

### FastAPI 自动文档
利用 FastAPI 自动生成的文档：
```python
@app.post("/api/files", response_model=FileResponse, status_code=201,
          summary="创建文件", description="创建新文件或文件夹")
async def create_file(file: FileCreate, user: User = Depends(get_current_user)):
    """
    创建新文件或文件夹：
    
    - **name**: 文件名（必填）
    - **content**: 文件内容（可选）
    - **parent_id**: 父文件夹 ID（可选，null 表示根目录）
    - **is_folder**: 是否为文件夹（默认 false）
    """
    ...
```

访问 `http://localhost:8000/docs` 查看自动生成的文档。

### 测试 API
编写 API 集成测试：
```python
def test_create_file(client, auth_token):
    response = client.post(
        "/api/files",
        json={"name": "test.md", "content": "# Test"},
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    assert response.status_code == 201
    assert response.json()["name"] == "test.md"
```

## 禁止行为

- ❌ API 变更不更新文档
- ❌ 错误响应返回 HTML 或纯文本（必须是 JSON）
- ❌ 在 URL 中暴露敏感信息（如密码、token）
- ❌ GET 请求修改服务器状态
- ❌ 返回数据库内部字段（如 `password_hash`）
- ❌ 不验证用户输入（必须使用 Pydantic 验证）
- ❌ 硬编码端口或域名在代码中

## 参考示例

完整 API 文档参考：
- `md_editor/docs/API.md` - 完整的 REST API + WebSocket 示例
