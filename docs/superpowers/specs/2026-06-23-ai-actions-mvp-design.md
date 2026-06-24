# FCat AI Actions MVP 设计

## 目标

在现有剪贴板历史面板中加入轻量 AI Actions，让用户可以对选中的文本历史项执行翻译、总结、改写、解释代码、格式化 JSON 等动作，并快速复制或粘贴结果。

这个版本的核心闭环是：打开历史面板 → 选中文本项 → 打开 AI 动作菜单 → 执行动作 → 在右侧预览结果 → 复制或粘贴结果。

## 非目标

- 不做图片或文件内容的 AI 处理。
- 不做多轮对话。
- 不做流式输出。
- 不做 Prompt 模板编辑器。
- 不做 Workflow 或脚本动作系统。
- 不自动上传剪贴板历史；只有用户主动触发动作时才发送当前文本。

## 用户交互

在 `HistoryPanelView` 中增加 AI Actions 模式：

- 用户通过现有全局快捷键打开 FCat 历史面板。
- 选中一个文本历史项。
- 按 `Tab` 或 `⌘K` 打开 AI Actions 菜单。
- 菜单列出第一版内置动作：
  - 翻译成中文
  - 总结
  - 改写
  - 解释代码
  - 格式化 JSON
- 动作菜单打开时：
  - `↑↓` 选择动作
  - `Enter` 执行动作
  - `Esc` 关闭动作菜单
- AI 执行中，右侧预览区显示 loading 状态，并禁止重复触发同一动作。
- AI 结果返回后，右侧预览区显示结果。
- 结果支持：
  - `Enter` 复制或粘贴 AI 结果，行为与当前 Debug/Release 模式一致
  - `⌘C` 复制 AI 结果
  - `Esc` 回到普通历史预览

非文本项打开动作菜单时显示不可用提示：`AI actions only support text in this version`。

## 配置与隐私边界

设置页新增 AI 配置：

- API Base URL
- API Key
- Model
- 默认目标语言：中文
- 请求超时

第一版使用 OpenAI-compatible Chat Completions 接口，方便接入 OpenAI、DeepSeek、SiliconFlow、Ollama 兼容网关等服务。

隐私边界：

- 只有用户主动选择 AI 动作时，才发送当前选中文本。
- 不自动处理剪贴板历史。
- AI 结果默认不写入数据库。
- 如果用户复制或粘贴 AI 结果，现有剪贴板监控可以自然记录该结果。
- API Key 不保存到 SQLite；使用 macOS Keychain 保存。
- Base URL、Model、默认语言、超时等普通配置可保存到 UserDefaults。

## 模块设计

新增三个核心模块。

### AIAction

职责：定义内置 AI 动作。

字段：

- `id`
- `title`
- `supportedTypes`
- `promptTemplate`

第一版动作固定内置，不开放编辑。

### AIService

职责：执行 AI 请求。

输入：

- `AIAction`
- `ClipboardItem`
- `AISettings`

输出：

- 成功：纯文本结果
- 失败：结构化错误，用于 UI 展示

行为：

- 只接受文本项。
- 组装 OpenAI-compatible Chat Completions JSON。
- 对网络错误、鉴权失败、超时、响应解析失败返回可展示错误。
- 对超过字符上限的文本直接返回本地错误，不发送请求。

### AISettingsStore

职责：保存和读取 AI 配置。

- UserDefaults 保存 Base URL、Model、默认语言、请求超时。
- Keychain 保存 API Key。
- 提供设置完整性检查，缺少必要配置时让 UI 显示配置提示。

## 数据流

```text
HistoryPanelView
  -> HistoryPanelViewModel
    -> selected ClipboardItem
    -> selected AIAction
    -> AIService.run(...)
    -> aiResult / aiLoading / aiError
  -> right preview renders result
```

现有 `ClipboardStore` 不需要改动数据结构。搜索、分类、收藏、删除逻辑保持不变。

## 错误处理

- 未配置 Base URL、API Key 或 Model：右侧预览区显示配置提示。
- 选中项不是文本：动作菜单显示不可用提示。
- 文本超过上限：提示文本过长，不发送请求。第一版上限为 20k 字符。
- 请求超时：右侧预览区显示超时错误。
- 鉴权失败：提示检查 API Key。
- 网络失败：显示网络错误。
- 响应解析失败：显示模型响应无法解析。
- AI 请求失败不影响历史项，也不写数据库。

## JSON 格式化动作

`格式化 JSON` 优先尝试本地格式化：

- 如果选中文本是合法 JSON，本地格式化后直接展示结果，不发起 AI 请求。
- 如果不是合法 JSON，提示用户当前内容不是合法 JSON。

第一版不把非法 JSON 发送给 AI 自动修复，避免动作语义不清。

## 测试范围

需要覆盖：

- AI 动作只对文本项可用。
- 内置动作列表包含翻译、总结、改写、解释代码、格式化 JSON。
- Prompt 生成符合动作语义。
- OpenAI-compatible 请求 JSON 结构正确。
- 缺少配置时不发请求并返回配置错误。
- 文本超过 20k 字符时不发请求。
- 请求成功时 ViewModel 更新 `aiResult`。
- 请求失败时 ViewModel 更新 `aiError`。
- 切换历史项会清空上一条 AI 结果。
- AI 结果复制走现有 pasteboard 写入能力。
- 合法 JSON 使用本地格式化，不调用 AIService。

## 验收标准

- 用户可以在历史面板中对文本项打开 AI Actions 菜单。
- 用户可以执行翻译、总结、改写、解释代码、格式化 JSON 五个动作。
- AI 结果显示在右侧预览区。
- 用户可以复制或粘贴 AI 结果。
- 未配置 AI 服务时有清晰提示。
- 网络、鉴权、超时失败不会导致 App 崩溃。
- 非文本项不会被发送给 AI 服务。
- AI 请求只在用户主动触发动作时发生。
