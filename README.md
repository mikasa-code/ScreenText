<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="ScreenText 图标">
</p>

# ScreenText

A small, offline screen OCR utility for macOS.

按下快捷键，框选屏幕上的文字，识别结果自动复制到剪贴板。用 Swift 和 AppKit 编写，通过 Apple Vision 在本机识别简体中文和英文，无需账号或第三方依赖。

## 构建与运行

需要 macOS 15 或更高版本，以及 Swift 6 和 macOS 15 或更新的 SDK。可以安装 Xcode 16 或更新版本，也可以只安装 Apple Command Line Tools：

```sh
xcode-select --install
```

在仓库根目录运行：

```sh
./build.sh
open build/ScreenText.app
```

脚本会构建适用于当前 Mac 架构的应用，生成图标资源并验证本地签名。输出位于 `build/ScreenText.app`，不会纳入 Git。

修改代码后重新构建前，先退出正在使用的构建版本。目前已在 Apple Silicon Mac 上验证本地构建；Intel Mac 构建仍需验证。

## 使用

1. 打开应用，菜单栏会出现取景框图标。
2. 默认按 **Control + Option + C（⌃⌥C）**，松开按键后框选文字。
3. 菜单栏显示勾号后，在目标输入框按 **⌘V** 粘贴。

首次使用需要允许 ScreenText 录制屏幕，授权后按系统提示退出并重新打开应用。系统第一次加载识别模型可能较慢，显示省略号时请稍候。

按 **Esc** 取消框选。取消、识别为空或识别失败时保留原剪贴板；识别进行中再次按快捷键不会启动第二个任务。

## 设置

点击菜单栏图标，选择 **设置…**：

- **取字快捷键**：点击组合键按钮，再按新的快捷键。至少包含 Command、Control、Option 中的一项。支持方向键和功能键；按 Esc、关闭设置窗口或切换窗口可取消录制。遇到已占用的组合键时保留原设置。
- **显示菜单栏图标**：可以隐藏图标，快捷键仍然有效。隐藏后再次打开 `ScreenText.app`，即可进入设置、恢复图标或退出应用。

设置会自动保存，应用默认不开机启动。

## 隐私与识别范围

文字识别在本机完成，应用不发送网络请求，也不保存识别历史。截图使用系统临时目录，正常处理结束后删除；识别到非空文字后才写入系统剪贴板。偏好设置由系统 UserDefaults 保存。

当前固定识别简体中文和英文，主要用于清晰的印刷文字。识别结果按行合并，不保留图片排版或表格格式。

## 录屏权限与本地签名

源码构建使用临时签名，没有 Apple Developer ID 签名或公证。构建内容变化后，系统可能仍保存着旧版本的授权，即使权限开关已开，当前版本也可能被拒绝。

遇到这种情况：

1. 退出 ScreenText。
2. 在终端运行下面的命令，仅重置 ScreenText 的录屏授权：

   ```sh
   tccutil reset ScreenCapture local.screentext.app
   ```

3. 打开 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制**，重新添加当前构建的 `ScreenText.app` 并允许录屏。不同 macOS 版本的页面名称可能略有差异。
4. 重新打开应用，再测试快捷键。

应用的 Bundle ID 是 `local.screentext.app`。如需公开分发安装包，应另行配置正式签名和公证；仓库中的构建脚本用于本地构建，不会发布安装包。

## 开发

```text
Sources/
  main.swift             应用入口、快捷键、框选识别与菜单栏状态
  Settings.swift         快捷键模型与设置窗口
Resources/
  Info.plist             应用元数据
  AppIcon.png            应用图标源图
Tests/
  ShortcutTests.swift    快捷键录制、显示与序列化检查
build.sh                 构建应用与图标资源
test.sh                 运行快捷键检查
```

运行检查：

```sh
./test.sh
```

检查使用程序构造的键盘事件，不注册全局快捷键，不读取屏幕或用户剪贴板。向 `main` 推送代码，或创建、更新目标为 `main` 的 PR 时，GitHub Actions 会运行同样的构建和检查命令。

修改识别或设置流程后，还需要在本机验收：

- 框选一段中英混排文字，确认可以粘贴；按 Esc 取消，以及框选空白区域后，确认原剪贴板未被覆盖。
- 连续取字后菜单栏图标能恢复；录制快捷键时，按键不会同时触发识别。
- 验证快捷键冲突提示、设置重启后保留，以及隐藏图标后仍能重新打开设置。

## 许可证

[MIT](LICENSE)。版权署名为 ScreenText contributors。
