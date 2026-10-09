# Cursor Portable（可移植版）

> 🌐 语言：[English](https://github.com/weishaozhi/cursor-portable/blob/main/README.md) | **中文**

一个仓库搞定——在任何机器上重新生成你的 Cursor skills、rules 和 MCP 服务器配置。

## 目录结构

```
cursor-portable/
├── bin/mcp-bridge/      # MCP 服务器源码（node + ws + @modelcontextprotocol/sdk）
├── user/
│   └── mcp.json         # 可移植的 MCP 配置（用 ${userHome}，不写死路径）
├── skills/              # 镜像自 d:\ai\projects\.cursor\skills\
├── rules/               # 镜像自 d:\ai\projects\.cursor\rules\
├── extensions.txt       # 扩展安装清单
├── manifest.json        # 同步契约声明（什么放哪里、为什么不放）
├── setup.ps1 / setup.sh # 幂等安装脚本（支持 -DryRun、-SkipUser、-SkipProject、-SkipNpm）
├── pull.ps1  / pull.sh  # 本机 → 仓库镜像（把改动抓回来）
├── tests/smoke.sh       # 适合 CI 的冒烟测试
├── .github/workflows/   # GitHub Actions：每次 push 跑冒烟测试
├── LICENSE              # MIT
├── .editorconfig        # 编辑器一致性
└── .gitattributes       # 锁定换行（shell 用 LF，.ps1 用 CRLF）
```

**本仓库是唯一真实来源。** 到新机器 clone 一次、跑一次 `setup`，完事。

## 当前机器首次配置

已经搞定——见 `user/mcp.json` 和 `~/.cursor/bin/mcp-bridge/`。直接看「日常使用」。

如果将来重装系统想从本仓库重新引导当前机器：

```powershell
cd d:\ai\projects\cursor-portable
.\setup.ps1
```

## 新机器引导

**新机器上的前置依赖：** Git、Node.js ≥ 18、Cursor。

```bash
git clone <本仓库地址> cursor-portable
cd cursor-portable
# Windows：
./setup.ps1
# macOS / Linux：
chmod +x setup.sh && ./setup.sh
```

这一条命令会做：

1. 把 `bin/mcp-bridge/` 复制到 `~/.cursor/bin/mcp-bridge/`，然后 `npm install`。
2. 写 `~/.cursor/mcp.json`（用 `${userHome}`，无需改路径）。
3. 把 `skills/` 镜像到 `~/.cursor/skills/`。
4. 把 `rules/` 和 `skills/` 镜像到 `<项目>/.cursor/`（默认是当前目录）。

两套脚本通用参数：
```
./setup.ps1 -ProjectDir D:\other\workspace   # 指定不同的项目目录
./setup.ps1 -SkipUser                       # 只装项目，不动 user 级
./setup.ps1 -SkipProject                    # 只装 user 级，不动项目
./setup.ps1 -SkipNpm                        # 跳过 npm install（快速重跑）
./setup.ps1 -DryRun                         # 只打印计划，不动文件
```

装完**重启 Cursor**，让 MCP 服务器列表重新加载。

## 日常使用——把改动抓回仓库

当你直接在原生位置（`~/.cursor/skills/`、项目里 `.cursor/`）编辑了 rule 或 skill，把它们抓回来：

```powershell
.\pull.ps1                       # 抓 ~/.cursor/skills + 项目/.cursor/rules
git add -A
git commit -m "update: <改了什么>"
git push
```

在另一台机器上：`git pull && ./setup.ps1`。

## 为什么 `mcp.json` 用 `${userHome}`

原本的写法（跨机器就坏）：
```json
"args": ["d:\\ai\\projects\\browser-mcp-bridge\\mcp-bridge.js"]
```

可移植的写法（任何机器都跑得起来）：
```json
"args": ["${userHome}/.cursor/bin/mcp-bridge/mcp-bridge.js"]
```

`${userHome}` 由 VS Code / Cursor 的 MCP 层在启动服务器时解析。Windows 上变成 `C:\Users\<你>\.cursor\bin\mcp-bridge\mcp-bridge.js`，macOS 上变成 `/Users/<你>/.cursor/bin/mcp-bridge/mcp-bridge.js`。正斜杠在两个平台的 Node 都能接受。

其它支持的变量：`${workspaceFolder}`、`${env:VAR}`。

## 本仓库明确**不**同步什么

这些写在 `manifest.json` 的 `explicitly_excluded` 字段。同步它们要么泄露机器特定状态、要么会因为系统特定二进制直接失败：

| 内容 | 排除原因 |
|---|---|
| `~/.cursor/argv.json` | 含有机器特定的 `crash-reporter-id` UUID。把同一个 ID 写到所有机器会让崩溃报告在多台设备间互相关联。让 Cursor 在首次启动时自己生成。 |
| `%APPDATA%\Cursor\User\settings.json` | 可能含 `http.proxy`、账号 ID、机器路径。如需部分同步，手动挑字段同步到跟踪文件里。 |
| Cursor 扩展（二进制） | 系统特定的二进制。用 `extensions.txt` 当清单，让 Cursor Settings Sync 去拉，或者手动 `cursor --install-extension <id>`。 |
| 工作区存储 + 对话历史 | 按路径索引；首次打开时自动重建。 |

`settings.json` 的部分同步套路：
```powershell
$keys = 'editor.fontSize','editor.tabSize','workbench.colorTheme'
# 从 %APPDATA%\Cursor\User\settings.json 里挑出这些键，合并到仓库里跟踪的部分文件
```

## 新增 MCP 服务器

1. 把服务器源码扔进 `bin/<名字>/`（或者 symlink 到外部路径）。
2. 在 `user/mcp.json` 加条目，路径用 `${userHome}` 或 `~/.cursor/bin/` 下的相对路径。
3. 改 `setup.ps1` 把新目录复制到 `~/.cursor/bin/`。
4. 更新 `manifest.json`，保持契约明确。
5. `git push`，然后在另一台机器上 `git pull && ./setup.ps1`。

## 验证仓库（冒烟测试）

```bash
bash tests/smoke.sh
```

每次 push 时 CI 自动跑（`.github/workflows/smoke.yml`）。检查项：文件布局、bridge JS 语法、manifest JSON 合法性、mcp.json 可移植性（`${userHome}` 存在、无 Windows 路径）、shell 语法、`.gitignore` / `.gitattributes` 正确性、声明的依赖、以及 `argv.json` 保持未跟踪。

## 故障排查

- **装完后 MCP 服务器启动失败** — 打开 Cursor → Settings → MCP，错误信息一般会指出缺哪个文件。最常见：`node_modules` 没装（去掉 `-SkipNpm` 重跑）、或者 `${userHome}` 不支持（Cursor ≥ 0.40 都支持）。
- **`pull.ps1` 覆盖了本地改动** — 它是故意先清空 `skills/` 和 `rules/` 再复制的。pull 之前先 commit 或 stash。
- **项目目录不对** — 给 `setup.ps1` 传 `-ProjectDir <路径>`，给 `setup.sh` 传 `--project-dir <路径>`。
- **想看预览** — `./setup.ps1 -DryRun` 或 `bash setup.sh --dry-run`。
- **沙盒环境里 `gh auth login --web` 超时** — 去 https://github.com/settings/tokens/new 生成一个 PAT（勾 `repo` scope），然后**在你自己的终端**里跑 `gh auth login --with-token -h github.com`；token 别发到聊天里。
