# 技能索引

按分类组织的项目级技能列表。所有技能源自历史对话中高频出现的问题模式（≥3 次）。

## 分类目录

### workflow/（工作流类）

- [plan-executor](./workflow/plan-executor/SKILL.md) - 自动按 .plan.md 执行 todos (v1.0, 频率 8+)
- [docs-compliance-check](./workflow/docs-compliance-check/SKILL.md) - docs 规范合规检查 (v1.0, 频率 5+)
- [pre-commit-verify](./workflow/pre-commit-verify/SKILL.md) - Git 提交前验证 (v1.0, 频率 3+)

### engineering/（工程类）

- [process-tree-cleanup](./engineering/process-tree-cleanup/SKILL.md) - 进程树深度清理 (v1.0, 频率 5+)
- [port-config-audit](./engineering/port-config-audit/SKILL.md) - 端口配置审计 (v1.0, 频率 4+)

### productivity/（生产率类，含元技能）

- [extract-skills-from-history](./productivity/extract-skills-from-history/SKILL.md) - 从历史对话中沉淀技能（元技能）(v1.0)

## 按使用频率排序

| 排名 | 技能 | 频率 | 类别 |
|------|------|------|------|
| 1 | plan-executor | 8+ | workflow |
| 2 | process-tree-cleanup | 5+ | engineering |
| 2 | docs-compliance-check | 5+ | workflow |
| 4 | port-config-audit | 4+ | engineering |
| 5 | pre-commit-verify | 3+ | workflow |
| - | extract-skills-from-history | 元技能 | productivity |

## 元技能说明

`extract-skills-from-history` 是一个**元技能**（meta-skill）：

- **特殊定位**：用于从历史对话中沉淀其他技能，而非直接解决业务问题
- **触发场景**：每 30 天或阶段性工作完成后调用
- **关联工具**：与 `grilling` 技能配合使用（用于决策讨论）

## 元数据说明

每个技能包含：

- **version**: 技能版本号
- **created/last_used**: 创建/最后使用日期
- **usage_count**: 使用次数
- **tags**: 标签列表
- **scope**: 适用范围（project/global）
- **overlap_with**: 重叠技能列表

## 待整理

暂无待整理项（v1.0 创建）。

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 初始化技能索引 | 5 个技能沉淀 |
| 2026-08-30 | 添加 extract-skills-from-history | 元技能，反思沉淀过程本身的价值 |