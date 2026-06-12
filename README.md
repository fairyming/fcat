# FCat - macOS 剪贴板历史管理工具

一款基于 Swift/SwiftUI 构建的 macOS 菜单栏剪贴板历史管理工具。

## 功能特性

- 菜单栏常驻应用，通过全局快捷键唤起面板（首次启动可自定义配置）
- 自动记录文本、图片、文件路径等剪贴板内容
- SQLite 持久化存储，重启后历史不丢失
- 分类过滤：全部 / 收藏 / 图片 / 文件
- 模糊搜索，支持标题、内容和文件名匹配
- 收藏功能：收藏项永久保留，不受数量限制
- 保留策略：最多 500 条非收藏记录、100 条非收藏图片、图片总存储 500MB
- 键盘驱动操作：↑↓ 选择、Enter 复制/粘贴、⌘D 收藏、Fn⌫ 删除、Esc 关闭
- 点击面板外部自动关闭
- 圆角无边框弹窗设计，无标题栏和窗口按钮

## 构建与运行

```bash
# Debug 模式（Enter = 复制到剪贴板，需手动 Cmd+V 粘贴）
swift build
swift run FCat

# Release 模式（Enter = 直接粘贴到目标应用，需辅助功能权限）
swift build -c release
swift run FCat
```

## DMG 安装包制作

```bash
./scripts/package.sh
```

脚本会自动完成 Release 构建、创建 .app bundle 并生成 `.build/FCat.dmg`。

## 安装方式

1. 双击 `FCat.dmg` 打开
2. 将 `FCat.app` 拖拽到 `Applications` 文件夹
3. 从 Applications 中启动 FCat
4. 首次打开时，macOS 可能提示"无法验证开发者"，需在 **系统设置 → 隐私与安全性** 中点击"仍要打开"

## 运行测试

```bash
swift run FCatCoreTests
```

使用自定义可执行测试框架，不依赖 XCTest，仅需 Command Line Tools 即可运行。

## 项目结构

```
Sources/
  FCat/           - 应用入口与 AppDelegate（菜单栏、窗口、生命周期）
  FCatCore/
    Models/       - ClipboardItem、ClipboardCategory、HotKey
    Hashing/      - ContentHasher（SHA-256 文本、文件、PNG 哈希）
    Search/       - FuzzyMatcher、SearchService
    Storage/      - SQLiteDatabase、ImageAssetStore、ClipboardStore
    Pasteboard/   - PasteboardClient、ClipboardMonitor
    HotKeys/      - GlobalHotKeyManager（Carbon API）
    ViewModels/   - HistoryPanelViewModel、SettingsViewModel
    Views/        - HistoryPanelView、HotKeyRecorderView（SwiftUI）
Tests/
  FCatCoreTests/  - 自定义测试框架（TestRunner.swift）
```

## 首次启动

首次启动时会弹出设置窗口，配置全局快捷键。保存后应用开始监控剪贴板，并驻留在菜单栏。

## Release 模式说明

Release 构建通过 CGEvent 模拟 Cmd+V 实现直接粘贴功能，需要 macOS 辅助功能权限：
1. 打开 **系统设置 → 隐私与安全性 → 辅助功能**
2. 添加 FCat 并启用权限
3. 应用启动时如未授权会自动提示

Debug 构建不需要此权限，Enter 仅复制到剪贴板。

## 数据存储位置

历史数据库和图片资源存储在 `~/Library/Application Support/FCat/`。