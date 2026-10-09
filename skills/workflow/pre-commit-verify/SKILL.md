---
name: pre-commit-verify
version: 1.0.0
created: 2026-08-30
last_used: 2026-08-30
usage_count: 0
tags: [workflow, git, commit, verify, quality-gate]
scope: project
overlap_with: [git-workflow.md]
---

# pre-commit-verify

Git 提交前的完整验证流程，确保代码质量和文档一致性。

## 触发条件

满足以下任一条件时自动加载：

- 用户说："提交验证"、"测试后再提交"、"准备 commit"
- 用户说："完整测试"、"严格匹配 vs 普通匹配"
- AI 准备执行 git commit 之前
- 修改了核心文件（services/、models/、API 等）

## 核心原则

**质量门禁原则**：

```
代码变更
    ↓
├─ 测试通过？→ 否 → 修复后重试
├─ docs 同步？→ 否 → 更新 docs
├─ ISS 登记？→ 否 → 登记 ISS
    ↓
是
    ↓
提交
```

**违反案例**（来自历史对话）：

| 对话 | 问题 | 后果 |
|------|------|------|
| `c4d801eb` (7/29) | "测试验证后再改动" | 用户明确要求先验证 |
| `ef1f8b74` (8/7) | 完整测试 vs 普通测试 | 必须用完整测试覆盖 |
| `ce90cd7d` (8/8) | "解决超时后再测试" | 修复后必须重新测试 |
| `40c7192a` (7/29) | 测试报告不符合预期 | 修复后未充分测试 |

## 标准验证流程

```
1. 识别变更范围
   ↓
2. 运行测试套件
   ├─ 单元测试
   ├─ 集成测试
   └─ 启动器测试（如适用）
   ↓
3. 验证测试结果
   ├─ 退出码 0 = 通过
   ├─ 退出码 1 = 断言失败
   └─ 退出码 2 = 脚本异常
   ↓
4. docs 合规检查
   ├─ arch.md（架构变更）
   ├─ prd.md（功能变更）
   ├─ test.md（测试变更）
   └─ project_state.md（ISS 状态）
   ↓
5. ISS 跟踪检查
   ├─ bug 修复 → 登记 ISS-XXX
   ├─ 关闭的 ISS → 更新为 🟩
   └─ 已知问题 → 标记状态
   ↓
6. 提交信息检查
   ├─ 格式符合 git-workflow.md
   ├─ 描述清楚改动
   └─ 关联 ISS 编号
   ↓
7. 最终确认
```

## 详细验证项

### 1. 测试验证

#### 1.1 运行测试

```bash
# 运行项目测试
python -m pytest tests/ -v

# 或 toolbox_hub 专项测试
cd toolbox_hub && python -m pytest tests/ -v

# 检查退出码
if [ $? -eq 0 ]; then
    echo "Tests passed"
fi
```

#### 1.2 退出码约定

| 退出码 | 含义 | 处理 |
|--------|------|------|
| 0 | 全部通过 | 继续下一步 |
| 1 | 至少 1 个断言失败 | 必须修复 |
| 2 | 脚本异常 | 检查导入、语法 |
| 其他 | 异常退出 | 查看日志 |

#### 1.3 测试覆盖率

- 修改的代码必须有测试覆盖
- 新增功能必须有对应测试
- bug 修复必须有回归测试

#### 1.4 严格 vs 普通测试

用户曾区分两种测试：

| 类型 | 用途 | 何时使用 |
|------|------|----------|
| 严格匹配测试 | 验证特定输入 | 边界场景、回归测试 |
| 普通匹配测试 | 验证一般情况 | 冒烟测试 |

**原则**：

- 修复 bug → 优先加严格匹配测试
- 优化功能 → 用普通测试 + 严格测试覆盖

### 2. Docs 合规验证

参考 `docs-compliance-check` 技能的检查清单。

**强制检查项**：

- [ ] `docs/project/test.md` 通过率表格已更新
- [ ] 架构变更已更新 `docs/project/arch.md`
- [ ] 新功能已更新 `docs/project/prd.md`
- [ ] ISS 状态已更新（修复完成 → 🟩）

### 3. ISS 跟踪验证

**新增 bug 必须登记**：

```markdown
| 编号 | 问题 | 优先级 | 状态 |
|------|------|--------|------|
| ISS-006 | Vite 子进程脱链 | P1 | 🟨 待处理 |
```

**修复完成必须更新**：

```markdown
| ISS-006 | Vite 子进程脱链 | P1 | 🟩 已完成 |
```

**登记位置**：`docs/project/project_state.md`

### 4. 提交信息验证

参考 `git-workflow.md` 规则中的提交格式：

```
<type><YYYY_MM_DD_HH_MM>_<short-snake-name>

<详细说明…>
- 新增了功能 123
- 调整 xxx
```

**提交类型**：

| type | 含义 | 是否发版 |
|------|------|----------|
| `feature` | 新功能 | 视情况 |
| `bugfix` | 缺陷修复 | 累计 10 次或必修 |
| `refactor` | 重构 | 不直接发版 |
| `docs` | 文档 | 不直接发版 |
| `test` | 测试 | 不直接发版 |
| `chore` | 杂项 | 不直接发版 |

**示例**：

```
bugfix2026_08_07_19_45_force_kill_children

ISS-006: Vite/esbuild 子进程脱链导致强制关闭不彻底

- 修改 service_manager.py 实现 _force_kill_tree
- 添加端口验证机制
- 5 轮启停测试通过
- 更新 toolbox-integration.md 增加深度清理章节
```

### 5. 代码质量验证

#### 5.1 静态检查

```bash
# Python (如使用)
python -m flake8 backend/ --max-line-length=100
python -m mypy backend/

# TypeScript/Vue (如使用)
npm run lint
```

#### 5.2 安全检查

- 不提交敏感信息（密钥、密码、token）
- 不提交调试代码（pdb、console.log）
- 不引入未审计的依赖

### 6. 依赖检查

```bash
# 检查 requirements.txt 是否更新
git diff requirements.txt

# 检查 package.json 是否更新
git diff frontend/package.json
```

## 标准验证脚本

`scripts/pre_commit_verify.py`：

```python
#!/usr/bin/env python3
"""提交前验证脚本"""
import subprocess
import sys
from pathlib import Path


def run_tests():
    """运行测试"""
    print("=" * 60)
    print("Step 1: 运行测试套件")
    print("=" * 60)

    result = subprocess.run(
        ["python", "-m", "pytest", "tests/", "-v"],
        capture_output=True, text=True
    )

    print(result.stdout)

    if result.returncode == 0:
        print("✓ Tests passed")
        return True
    else:
        print(f"✗ Tests failed with exit code {result.returncode}")
        return False


def check_docs():
    """检查 docs 合规"""
    print("=" * 60)
    print("Step 2: Docs 合规检查")
    print("=" * 60)

    # 读取 project_state.md 检查 ISS 状态
    state_file = Path("docs/project/project_state.md")
    if state_file.exists():
        content = state_file.read_text(encoding="utf-8")
        if "🟨" in content:
            print("⚠ Project_state.md 中有待处理 ISS")
            print("  请确认是否需要更新")

    # 读取 test.md 检查通过率
    test_file = Path("docs/project/test.md")
    if test_file.exists():
        content = test_file.read_text(encoding="utf-8")
        # 检查是否含真实日期（不是写死 PASS）
        if "全部通过" in content or "100%" in content:
            print("✗ test.md 含写死的通过率")
            return False

    print("✓ Docs 检查通过")
    return True


def check_git_status():
    """检查 git 状态"""
    print("=" * 60)
    print("Step 3: Git 状态检查")
    print("=" * 60)

    result = subprocess.run(
        ["git", "status", "--porcelain"],
        capture_output=True, text=True
    )

    if not result.stdout.strip():
        print("✗ 没有需要提交的变更")
        return False

    print(f"待提交变更：\n{result.stdout}")
    return True


def main():
    checks = [
        ("Tests", run_tests),
        ("Docs", check_docs),
        ("Git", check_git_status),
    ]

    all_passed = True
    for name, check_fn in checks:
        if not check_fn():
            all_passed = False
            print(f"\n✗ {name} check failed")
            break

    print()
    if all_passed:
        print("✓✓✓ 所有检查通过，可以提交")
        return 0
    else:
        print("✗✗✗ 验证失败，请修复后再试")
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

## 实际案例

### 案例 1：toolbox_hub 强制清理修复后的验证

来源：对话 `85d14443-a718-4a71-996d-23b1f82f0518`

**修复内容**：实现 `_force_kill_tree` 解决 Vite 子进程脱链

**验证流程**：

1. **测试验证**：5 轮启停测试
   ```
   Round 1: start → force_stop → 端口释放 ✓
   Round 2: start → force_stop → 端口释放 ✓
   Round 3: start → force_stop → 端口释放 ✓
   Round 4: start → force_stop → 端口释放 ✓
   Round 5: start → force_stop → 端口释放 ✓
   ```

2. **Docs 检查**：
   - project_state.md：ISS-006 状态从 🟨 → 🟩
   - toolbox-integration.md：添加 `_force_kill_tree` 章节
   - arch.md：更新进程管理章节

3. **ISS 更新**：ISS-006 完成

4. **提交信息**：
   ```
   bugfix2026_08_07_19_45_force_kill_children
   ```

**结果**：提交通过，无回归问题

### 案例 2：ciallo 装备筛选功能提交前验证

来源：对话 `319351e1-b7fc-481e-b2dc-95aa27b76e72`

**变更**：扩展到 8 个装备槽位

**验证流程**：

1. **运行测试**：
   ```
   tests/test_solver.py -v
   ✓ 8 项全部通过
   ```

2. **Docs 检查**：
   - arch.md：更新槽位章节
   - prd.md：更新功能列表
   - test.md：更新通过率表格

3. **提交**：
   ```
   feature2026_08_08_00_45_extend_8_slots
   ```

### 案例 3：完整测试 vs 普通测试

来源：对话 `ef1f8b74-84cf-4224-a393-a5ae3271be64`

**问题**：用户要求"完整测试通过后再确认是否提交"

**实施**：

1. 运行完整测试套件（不只是相关测试）
2. 验证全部退出码 0
3. 报告测试结果给用户
4. 用户确认后提交

## 验证清单（速查表）

### 提交前必做

- [ ] 测试通过（退出码 0）
- [ ] 退出码符合约定（0=通过，1=断言失败，2=脚本异常）
- [ ] 新功能有测试覆盖
- [ ] bug 修复有回归测试
- [ ] test.md 通过率表格已更新（不写死 PASS）
- [ ] 架构变更更新 arch.md
- [ ] ISS 状态已更新
- [ ] 提交信息符合格式
- [ ] 单次提交只包含相关改动
- [ ] 不含敏感信息

### 提交时推荐

- [ ] 详细提交信息（不只写 "update"）
- [ ] 关联 ISS 编号
- [ ] 说明测试覆盖情况
- [ ] 说明 docs 更新情况

## 注意事项

### 必须遵守

- **强制**运行测试后才能提交
- **强制**退出码 0 才能提交
- **强制**更新 docs 才能提交
- **禁止** 跳过测试就提交
- **禁止** 注释掉失败的测试
- **禁止** 写死测试通过率

### 推荐实践

- 修改后立即验证
- 关键修复做完整测试
- 提交前让用户确认
- 提交信息描述改动原因

### 反模式

| 反模式 | 后果 | 正确做法 |
|--------|------|----------|
| 跳过测试就提交 | 引入回归 bug | 必须测试通过 |
| 写死通过率 | 失去测试可信度 | 实际运行后记录 |
| 注释失败测试 | 测试覆盖下降 | 修复测试或代码 |
| 提交信息只写 "update" | 无法追溯 | 详细描述改动 |
| 大杂烩提交 | 难回滚、难 review | 单次提交相关改动 |

## 关联技能

- `docs-compliance-check` - 文档合规检查
- `plan-executor` - plan 执行后验证
- `process-tree-cleanup` - 进程相关提交验证

## 关联规则

- `git-workflow.md` - Git 提交规范
- `testing.md` - 测试规范
- `project-structure.md` - 文档结构

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 创建技能 | 3+ 次提交前验证对话 |