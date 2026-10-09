# 项目级技能

本目录包含 d:\ai\projects 项目下使用的所有项目级技能。

## 目录结构

```
.cursor/skills/
├── INDEX.md                        # 技能索引
├── README.md                       # 本文件
├── workflow/                       # 工作流类技能
│   ├── plan-executor/             # 计划执行
│   ├── docs-compliance-check/     # 文档合规
│   └── pre-commit-verify/         # 提交前验证
└── engineering/                    # 工程类技能
    ├── process-tree-cleanup/      # 进程树清理
    └── port-config-audit/         # 端口配置审计
```

## 技能设计原则

按用户的核心分类标准：

- **规则**：核心指令（代码风格、语言、禁止语法）→ `.cursor/rules/`
- **技能**：具体方法（解决问题的工作流）→ `.cursor/skills/`

## 技能触发方式

每个技能在 frontmatter 中定义了清晰的触发条件。当用户消息匹配触发短语时，AI 自动加载相应技能。

## 技能沉淀流程

1. **识别问题模式**：从历史对话中找出 ≥3 次重复的问题
2. **判断沉淀价值**：问题可复用且包含 3+ 个步骤
3. **创建技能**：按统一模板（元数据 + 触发条件 + 工作流 + 案例 + 反模式）
4. **更新索引**：在 INDEX.md 中登记
5. **跟踪使用**：根据使用情况调整或合并

## 关联文档

- [.cursor/rules/README.md](../rules/README.md) - 规则系统说明
- [.cursor/rules/knowledge-evolution.md](../rules/knowledge-evolution.md) - 知识沉淀与持续改进规则

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-08-30 | 初始化技能集 | 从历史对话中沉淀 5 个高频问题模式 |