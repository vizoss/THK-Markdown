# THKMDView

*English: [`README.md`](README.md)*

`THKMDView` 是一个跨平台（Android / iOS）SDK，用于在聊天类 UI 中渲染**流式 Markdown**——
也就是可以放进 `RecyclerView` 列表项或 `UITableView` cell 里的视图组件，用来把 LLM 通过
SSE 逐步返回的回复实时渲染出来，标题、强调、链接、列表、代码块、引用、表格等 Markdown
格式会随着新增的 token/分片持续增量应用。

仓库里并排维护着两套独立、各自符合平台习惯的实现，二者共享同一套公开 API 形态和同一套
架构设计（完整设计理由见 [`docs/RESEARCH.md`](docs/RESEARCH.md) / 中文版
[`docs/RESEARCH.zh-CN.md`](docs/RESEARCH.zh-CN.md)）：

| 平台     | 路径                              | 语言   | 分发方式                          |
|----------|-----------------------------------|--------|-----------------------------------|
| Android  | [`android/`](android/README.md)   | Kotlin | Gradle module（AAR），已接入 GitHub Packages 远端依赖 |
| iOS      | [`ios/`](ios/README.md)           | Swift  | Swift Package（源码）或 CocoaPods（XCFramework 二进制） |

iOS 两种接入方式统一使用 `swift-markdown` 和同一套渲染代码，不再使用 Maaku。
SPM 提供源码，CocoaPods 提供预编译 XCFramework；远端 pod 安装需先构建并发布二进制资产。
详见 [二进制打包与发布](ios/Binary/README.md)。

## 核心能力（两个平台一致）

- **`setMarkdown(_:)`** —— 渲染一段完整的 Markdown 文本。
- **`appendMarkdownChunk(_:)`** —— 追加一个 SSE 风格的增量分片；重新渲染会做防抖合并，
  避免每来一个小分片就触发一次重新排版。
- **`reset()`** —— 清空缓冲区/流式渲染状态；需要在 `onViewRecycled` /
  `prepareForReuse` 里调用，确保被复用的 cell 不会残留上一条消息的渲染尾巴。
- 可插拔的渲染器与主题、链接/图片点击回调、GFM 扩展语法（表格、删除线、任务列表）。
- P3：原生提示块、基础编号脚注、离线行内/块级数学公式；语法、限制及验收见 [P3 说明](docs/P3.zh-CN.md)。代码语法高亮仍暂不支持。

## 主题配置

双端 Markdown SDK 的颜色与字号由 `THKMDTheme` 统一配置；给 `markdownView.theme` 赋值后会重新渲染当前内容，无需再次调用 `setMarkdown`。iOS 的 SPM 和 CocoaPods 共用这些配置。

### 配置项

| 配置项（Android / iOS 同名，除特别说明外） | 用途 |
| --- | --- |
| `bodyTextColor` | 正文、列表和表格正文颜色 |
| `headingTextColor` | 标题和表格表头文字颜色 |
| `linkColor` | 链接颜色 |
| `alertNoteColor` / `alertTipColor` / `alertImportantColor` / `alertWarningColor` / `alertCautionColor` | 对应提示块的标题和竖条颜色；正文和背景复用引用配置 |
| `footnoteScale` | 脚注上标序号相对正文字号倍率，默认 0.75；颜色复用 `linkColor`，不打开外部链接 |
| `mathScale` | 公式相对正文字号倍率，默认 1；颜色复用 `bodyTextColor`，背景透明 |
| `codeTextColor` | 行内代码、代码块和复制图标颜色 |
| `codeBackgroundColor` | 行内代码与代码块背景色 |
| `codeBlockCornerRadiusDp` / `codeBlockCornerRadius` | 代码和引用背景圆角；Android 为 dp，iOS 为 pt |
| `blockQuoteBarColor` | 引用竖条及水平分隔线颜色 |
| `blockQuoteTextColor` | 引用正文颜色，不覆盖链接和代码自身颜色 |
| `blockQuoteBackgroundColor` | 最外层引用背景色，内层引用共享背景 |
| `tableBorderColor` | 表格网格边框颜色 |
| `tableHeaderBackgroundColor` | 表格表头背景色 |
| `backgroundColor` | 整个 Markdown 视图背景色，默认透明 |
| `bodyFontSizeSp` / `bodyFontSize` | 正文基准字号；Android 为 sp，iOS 为 pt；默认 15 |
| `codeFontSizeSp` / `codeFontSize` | 代码字号；Android 为 sp，iOS 为 pt；默认 13 |
| `heading1Scale`～`heading6Scale` | 标题相对正文字号倍率，默认依次为 1.6、1.4、1.25、1.15、1.05、1.0 |
| `imagePlaceholderColor` | 图片加载中或失败时的占位色 |
| `copyFeedbackTextColor`（仅 iOS） | 自绘复制成功提示的文字颜色 |
| `copyFeedbackBackgroundColor`（仅 iOS） | 复制成功提示背景色，包含透明度 |
| `copyFeedbackFontSize`（仅 iOS） | 复制成功提示字号，单位 pt，默认 12；提示尺寸随字号自适应 |

Android 复制成功提示使用系统 Toast，样式由系统管理。

### 使用示例

```swift
var theme = THKMDTheme.default
theme.bodyFontSize = 18
theme.heading1Scale = 1.8
theme.imagePlaceholderColor = .lightGray
theme.copyFeedbackFontSize = 14
markdownView.theme = theme
```

```kotlin
markdownView.theme = THKMDTheme.Default.copy(
    bodyFontSizeSp = 18f,
    heading1Scale = 1.8f,
    imagePlaceholderColor = android.graphics.Color.LTGRAY
)
```

### Mermaid 与配置边界

Mermaid 复用同一主题：正文颜色/字号控制图中文字，代码背景控制节点底色，表格边框控制节点边框与连线，引用/表头背景控制次级区域。源码不变时切换主题，图形也会更新。

主题控制 Markdown SDK 自有渲染及 Mermaid 模板，不接管示例 App 导航栏、输入框、选择器等宿主 UI。默认主题是固定配色，不自动切换深色模式；需要时由宿主提供主题。透明子视图用于背景合成；iOS 复制图标的黑色笔画只是模板遮罩，实际显示颜色来自主题。Mock 图片颜色属于测试数据。

所有字段都可通过 API 配置；示例主题面板尚未为每个新增字段提供控件。配置项源码注释见 [Android 主题](android/thkmdview/src/main/java/com/thk/mdview/THKMDTheme.kt)和 [iOS 主题](ios/Sources/THKMDView/THKMDTheme.swift)。改造验证记录见 [主题验证记录](docs/theme-configuration.md)。

## 现状

### 示例界面样式

双端示例使用同一套扁平样式，独立于 Markdown 渲染主题。配色与字号集中在 Android 的
`sample/src/main/res/values/demo_ui.xml` 和 iOS 的
`Example/Sources/MockAssistantReply.swift` 中的 `DemoUI`，修改时应同步两端。
白底、深灰文字、蓝色强调色；正文控件 14sp/pt、状态文字 12sp/pt、标题 18sp/pt；
左右边距 16、标题栏高 56、控件高 44、输入栏高 68（单位 dp/pt）。
用例选择与验收要求使用无阴影、可滚动的自定义弹窗：宽度为可用宽度减 32，最大 560，
高度为可用高度的 70%。示例外壳固定浅色，Markdown 仍由 `THKMDTheme` 配置。
系统状态栏、键盘和字体栅格化保留平台差异。

示例 App 修改 Markdown 主题后会自动保存到本地（Android SharedPreferences / iOS UserDefaults），下次启动恢复，包括颜色透明度、字号、圆角和标题倍率。选择 Default 预设也会保存；卸载或清除 App 数据后恢复默认。此行为仅属于示例工程，SDK 不会自行持久化宿主主题。

当前示例提供双端共享的 18 个 P0、60 个 P1、25 个 P2、36 个 P3 用例，共 139 个，支持分组选择、全文、播放、暂停和单步。上一条/下一条按 P0 → P1 → P2 → P3 连续切换，仅全目录首尾禁用。覆盖和验收步骤见 [P0](docs/P0.zh-CN.md)、[P1](docs/P1.zh-CN.md)、[P2](docs/P2.zh-CN.md)、[P3](docs/P3.zh-CN.md)。P1/P2/P3 已接入测试入口，尚待执行双端渲染测试和视觉验收，不代表全部通过。新增 P3 主题字段在两端示例面板均可修改并本地保存。

初始脚手架：工程结构、构建工具链、核心渲染管线、单元测试，以及每个平台各自的示例 App
（一个可交互的"和 LLM 聊天"演示：用户输入文本消息，mock 的助手回复覆盖全部 Markdown
语法并以流式分片方式渲染）。具体的构建/测试/运行方式见各平台目录下的 README。

## License

[MIT](LICENSE) —— 详见 license 文件；这是一个默认占位选择，如果你所在组织有其他要求，
可以自行替换。
