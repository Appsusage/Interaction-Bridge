# Shell Bridge 按会话话题分文件夹执行规范

生效时间：2026-10-24（Asia/Kuching）
适用范围：本会话起，所有经 GitHub Interaction-Bridge、Backup-Interaction-Bridge 或 Dropbox AI Shell Bridge 提交的 Shell Bridge 任务。

## 1. 一个聊天话题，一个任务文件夹
- 每个新聊天话题第一次提交 Shell Bridge 命令之前，先创建一个以该聊天窗话题命名的专属文件夹。
- 同一话题的后续任务，一律沿用同名文件夹，不得每条命令另建主题文件夹，也不得混入其他话题。
- 文件夹名称保留可识别的话题文字；剔除路径分隔符及不支持的字符。发生重名时使用明确后缀，避免跨会话混用。
- 当前会话话题文件夹：`Shell Bridge 多任务与浮窗测试`。

## 2. Shell Bridge 指令文件必须放在话题文件夹内
在 GitHub 中的入口：
```text
Appsusage/Interaction-Bridge/<话题文件夹>/shell_bridge.txt
Appsusage/Backup-Interaction-Bridge/<话题文件夹>/shell_bridge.txt
```
在真正的 Dropbox App 文件夹中的入口：
```text
/Apps/AI Shell Bridge/inbox/<话题文件夹>/shell_bridge.txt
```
- 只向本次选定的一个执行入口提交任务，避免主/备仓库双重执行。
- 同名 `shell_bridge.txt` 尚未被接收时不得覆盖；必须等上一条命令安全进入处理阶段再提交下一条。
- 不再以仓库根目录的 `shell_bridge.txt` 作为本规范的任务入口。

## 3. 按话题收集、顺序编号与执行
任务接收后，`shell_command.js` 将来源文件内容复制到真正的 Dropbox App 文件夹：

```text
/Apps/AI Shell Bridge/processing/<话题文件夹>/Sxxx.txt
```

- **S 序号从 Outbox 最后序号继续**；旧序号基点为 `S1492`，接下来使用 `S1493`、`S1494`……，禁止把时间戳拼进 S 编号。
- 扫描 Outbox 的根目录和各话题子目录，兼顾尚未完成的 Processing 文件；为避免话题文件夹归档后序号倒退，可在 Outbox 根目录保存 `.shell_command_sequence.txt` 高水位标记。
- 每个任务独立执行，并保留完整 Shell stdout、stderr、退出码和任务状态；等待 10 秒、AI 的 yes/no 回答及延后状态按既定流程记录。
- Dropbox API 使用 App Folder 权限时，API 的 `/` 对应网页中的 `/Apps/AI Shell Bridge/`，所以 API 路径必须写成 `/inbox/...`、`/processing/...`、`/outbox/...`；绝不可写成 `/ai-agent/bridge/shell`。
- Replit 本地模块路径 `ai-agent/bridge/shell/` 与 Dropbox 文件路径不同，不得混淆。

## 4. 任务结束：来源原始日志 + Outbox，同话题暂不归档
一个 `Sxxx.txt` 任务结束后，按顺序执行：

1. 在**来源话题文件夹**写入 `Sxxx.txt_raw_log.txt`，保留该文件以及既有的 AI yes/no 临时日志。
2. 在**该来源文件夹**仅删除已经处理的 `shell_bridge.txt`；不删除来源话题文件夹，也不删除 `Sxxx.txt_raw_log.txt`。
3. 在真正的 Dropbox App 目录建立或复用 `/Apps/AI Shell Bridge/outbox/<话题文件夹>/`，写入 `Sxxx.txt`，内容为完整原始 Shell 日志和退出状态。
4. Outbox 写入成功后，才清理对应的 `processing/<话题文件夹>/Sxxx.txt` 临时副本。
5. **不得在每次任务结束时把 Outbox 日志直接写入 Archive**，也不得删除话题文件夹或其原始日志。

### 何时将 Outbox 迁往 Archive
- `shell_command.js` 周期性对比 GitHub 主仓库、备用仓库以及 Dropbox `inbox/` 的**现存话题文件夹**。
- 当某个 `outbox/<话题文件夹>` **在所有来源中均已不存在**，且没有正在运行或排队的该话题任务时，才清理对应 Outbox 文件夹。
- 清理前，必须先把该话题 Outbox 中的 `Sxxx.txt` **移动到** `/Apps/AI Shell Bridge/archive/`；归档重名时改存 `archive/<话题文件夹>/`，绝不覆盖既有日志。其他文件也须安全迁移或保留，不得直接丢失。
- 仅在所有文件移动成功、确认 Outbox 话题子文件夹已空后，才删除该 Outbox 子文件夹。
- **任一来源目录读取失败时，不得误判为来源已消失，更不得执行归档清理。**

## 5. 实施约束
- 本文为强制执行规范；实际监听程序必须支持扫描各入口的话题子文件夹，不能仅扫描根目录。
- 在监听器、`shell_command.js` 和必要的调度入口验证支持话题子文件夹之前，禁止声称新结构已成功运行。
- 不修改无关逻辑，不更改 `dropbox_token.js` 或泄露 Token。
