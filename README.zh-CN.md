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
| iOS      | [`ios/`](ios/README.md)           | Swift  | Swift Package（SPM）或 CocoaPods（见 [`THKMDView.podspec`](THKMDView.podspec)） |

iOS 这一份包从同一份源码同时提供两种分发方式：SPM（用 swift-markdown 解析）和
CocoaPods（用 Maaku 解析，因为 swift-markdown 没有发布 CocoaPods trunk 版本）。两者
共享同一套公开 API 和流式渲染架构，渲染效果预期一致——具体安装方式和细节见
[`ios/README.md`](ios/README.md#cocoapods)。

## 核心能力（两个平台一致）

- **`setMarkdown(_:)`** —— 渲染一段完整的 Markdown 文本。
- **`appendMarkdownChunk(_:)`** —— 追加一个 SSE 风格的增量分片；重新渲染会做防抖合并，
  避免每来一个小分片就触发一次重新排版。
- **`reset()`** —— 清空缓冲区/流式渲染状态；需要在 `onViewRecycled` /
  `prepareForReuse` 里调用，确保被复用的 cell 不会残留上一条消息的渲染尾巴。
- 可插拔的渲染器与主题、链接/图片点击回调、GFM 扩展语法（表格、删除线、任务列表）。

## 现状

当前示例已改为双端共享的 18 个 P0 用例，支持选择、全文、播放、暂停和单步。数据源、覆盖范围及手动验收步骤见 [P0 验收说明](docs/P0.zh-CN.md)。

初始脚手架：工程结构、构建工具链、核心渲染管线、单元测试，以及每个平台各自的示例 App
（一个可交互的"和 LLM 聊天"演示：用户输入文本消息，mock 的助手回复覆盖全部 Markdown
语法并以流式分片方式渲染）。具体的构建/测试/运行方式见各平台目录下的 README。

## License

[MIT](LICENSE) —— 详见 license 文件；这是一个默认占位选择，如果你所在组织有其他要求，
可以自行替换。
