# AuthPass TOTP 功能开发 - Git 工作流手册

## 概述

本文档说明在 AuthPass 项目中修改代码后，如何提交 Git、触发 GitHub Actions 构建，以及同步各分支的完整流程。

## 分支说明

| 分支 | 用途 | 触发器 |
|------|------|--------|
| `main` | 主开发分支 | 不自动触发构建（各 workflow 仅在 `pull_request: main` 时跑测试/分析） |
| `windows-totp-list` | Windows 版本 | `windows.yaml` 监听 `windows**`，推送即触发 Windows 构建 ✅ |
| `android-totp-list` | Android 版本 | ⚠️ 当前 `main.yml`（build android）**未监听 `android**`**，推送该分支不会触发 Android 构建，见下方「差异与待澄清项」 |
| `stable` / `beta` | 稳定/测试版本 | 推送时触发所有平台构建（windows / linux / android / ios / web） |

## 差异与待澄清项（2026-06-29 核对）

按当前仓库 `.github/workflows/` 配置与远程分支核对，记录如下：

- **分支存在性**：`main`、`windows-totp-list`、`android-totp-list` 在 `origin` 远程均存在，与手册一致。
- **Windows 触发**：`windows.yaml` 触发分支为 `windows**` / `stable` / `beta`，推送 `windows-totp-list` 可自动触发 Windows 构建，与手册一致。
- **Android 触发（差异）**：`main.yml`（`build android`）触发器为 `push: stable/beta`、`tags: v*`、`pull_request: main`，**不包含 `android**` 或 `android-totp-list`**。因此推送 `android-totp-list` 分支**不会**触发 Android 构建，与手册原描述不符。
  - 待澄清：Android 构建应通过哪种方式触发？可选方案：
    1. 在 `main.yml` 的 `on.push.branches` 增加 `'android**'`（与 Windows 对齐）；
    2. 或改为通过推送 `stable`/`beta` 分支、打 `v*` tag 触发；
    3. 或对 `android-totp-list` 发起指向 `main` 的 PR（仅 `pull_request: main` 时跑）。
  - 在 CI 配置确认前，P004/P005/P006 中「推送 android-totp-list 即触发 Android 构建」的预期可能无法成立。
- **main 不自动构建**：`analyze` / `unit_test` / `integration_test` / `driver_test` 仅在 `pull_request: main` 触发，无 `push: main`；其余构建 workflow 也未监听 `main` 推送，与手册「main 分支不自动触发」一致。

## 工作流步骤

### 1. 修改代码

在 `main` 分支上进行代码修改：

```bash
# 确保在 main 分支
git checkout main

# 修改代码...
# 例如：编辑 lib/ui/screens/totp_list.dart
```

### 2. 提交代码到 main

```bash
# 添加修改的文件
git add <修改的文件>

# 提交（使用英文描述）
git commit -m "feat: xxx 功能描述"

# 推送到远程
git push origin main
```

### 3. 同步到 Windows 分支

```bash
# 切换到 windows 分支
git checkout windows-totp-list

# 合并 main 的修改
git merge main --no-edit

# 推送（会自动触发 Windows 构建）
git push origin windows-totp-list
```

### 4. 同步到 Android 分支

```bash
# 切换到 android 分支
git checkout android-totp-list

# 合并 main 的修改
git merge main --no-edit

# 推送（会自动触发 Android 构建）
git push origin android-totp-list
```

### 5. 切回 main 分支

```bash
git checkout main
```

## 触发构建的方式

### 方式一：推送代码到对应分支（自动触发）

- 推送到 `windows-totp-list` → 触发 Windows 构建 ✅
- 推送到 `android-totp-list` → ⚠️ 当前 CI 未监听 `android**`，**不会**触发 Android 构建（详见「差异与待澄清项」）

### 方式二：创建空提交触发（不修改代码）

```bash
# 切换到目标分支
git checkout windows-totp-list

# 创建空提交
git commit --allow-empty -m "ci: trigger build"

# 推送
git push origin windows-totp-list
```

## 查看构建状态

访问 GitHub Actions 页面：

```
https://github.com/fakeneko/authpass/actions
```

## 下载构建产物

1. 进入成功的构建记录
2. 页面底部找到 "Artifacts" 区域
3. 下载对应的安装包

## 注意事项

1. **优先在 main 分支修改代码**，然后同步到其他分支
2. **commit message 使用英文**，格式：`type: description`
   - `feat:` 新功能
   - `fix:` 修复
   - `ci:` CI/CD 相关
   - `chore:` 其他
3. **同步时保持 commit message 一致**，不要产生额外的 merge commit message
4. **main 分支不自动触发构建**，避免不必要的资源消耗
5. **Android 构建需要签名**：当前使用 debug 签名，正式发布需要 release keystore

## 常见问题

### Q: 推送到 main 没有触发构建？
A: 这是正常的，main 分支已禁用自动触发。需要同步到 windows/android 分支才会触发。

### Q: 如何只触发 Windows 构建？
A: 推送到 `windows-totp-list` 分支即可。

### Q: 构建失败了怎么办？
A: 查看 GitHub Actions 日志，修复代码后重新推送。

### Q: 可以合并 Windows 和 Android 的 workflow 吗？
A: 可以但不建议，因为它们使用不同的 runner 和构建工具。

## 快速命令参考

```bash
# 完整流程（修改代码后）
git checkout main
git add .
git commit -m "feat: xxx"
git push origin main

git checkout windows-totp-list
git merge main --no-edit
git push origin windows-totp-list

git checkout android-totp-list
git merge main --no-edit
git push origin android-totp-list

git checkout main
```

---

**最后更新**: 2026-06-29
**适用项目**: fakeneko/authpass
