# THKMDView —— 实现调研与架构设计

*English: [`RESEARCH.md`](RESEARCH.md)*

当前状态：v0（脚手架阶段）。本文档记录了仓库中 Android / iOS 脚手架背后的设计理由，
以及还需要人来拍板的若干决策点。

## 1. 需求回顾

- 这是一个**视图组件**，不是一个完整页面：Android 上叫 `THKMDView`，iOS 上同样叫
  `THKMDView`。
- 渲染 **Markdown**（至少要支持 CommonMark + GFM：表格、删除线、任务列表）。
- 主要使用场景是 **LLM 聊天消息气泡**，因此必须：
  - 能放进 `RecyclerView` 的 item / `UITableView`（或 `UICollectionView`）的 cell
    里，并且正确应对**视图复用（recycling）**。
  - 支持 **SSE 流式传输**：文本以一连串小增量的形式到达，渲染出来的 Markdown 必须
    实时、正确、低成本地随每个增量更新——包括某个语法结构（代码围栏、链接、表格）
    还**处于"半截"状态**、因此语法上不完整的时候。
- 每个平台都要配一套**单元测试**和一个**可运行的示例 App**。

## 2. 调研过的已有方案

| 项目 | 平台 | 参考的思路 |
|---|---|---|
| [Markwon](https://github.com/noties/Markwon) | Android | 用 commonmark-java 把 Markdown 解析成一个 `Spanned`/`SpannableStringBuilder`，交给单个 `TextView` 渲染。块级结构（引用、代码块、列表）不是子 View，而是自定义 `Span`（`LeadingMarginSpan`、`LineBackgroundSpan` 等）。这是 Android 上"列表里渲染 Markdown"这个场景久经考验的主流方案。 |
| ChatGPT / Claude / Gemini 网页版，`streamdown`、`react-markdown` 的流式方案 | Web | 把原始文本缓冲起来，**每来一个分片就重新解析整个缓冲区**，但对重新渲染做**防抖/节流**（通常是一帧动画或约 30–50ms），而不是每个 token 都渲染一次。没闭合的语法结构（没关闭的代码围栏、没闭合的 `**`）就原样当作字面文本，等下一个分片把它补完——这正好是 CommonMark 解析器处理"被截断的文档"时天然的行为，不需要专门再写一套"半成品 Markdown"的语法解析。 |
| `swift-markdown`（Apple / `swiftlang`） | iOS | 基于 `cmark`/`cmark-gfm` 的正统 CommonMark+GFM 语法树（`Document`、`MarkupVisitor`），和 `commonmark-java` 是同类工具。它本身不自带把语法树转成富文本的渲染器——这部分需要我们自己写，做法上参照 Markwon 的 span 思路。 |
| 基于 WebView 的渲染方案（把 Markdown 转 HTML 再丢进 `WKWebView`/`WebView`） | 两端都考虑过 | 不作为主方案：每条聊天气泡都起一个 `WebView` 太重（自带进程/GPU layer、创建与复用都慢、和 `RecyclerView`/`UITableView` 的高度测量配合别扭、会破坏原生文本选中/无障碍/深色模式主题）。保留作为一个有文档记录的**逃生舱**，未来给"直接渲染一段原始 HTML"这种节点类型用，而不是默认渲染器。 |

## 3. 架构决策：单一富文本视图 + 自定义 span，而不是一堆子 View 叠起来

两个平台都权衡过两种形态：

- **方案 A：单一文本视图，语法树 → 带自定义 span/attachment 的富文本**
  （Markwon 的做法）。每条消息只用一个 `TextView`/`UITextView`；块级元素（代码块、
  引用块、表格兜底、分割线）用自定义 span（Android：`Span` 的具体实现）或自定义绘制
  （iOS：自定义 `NSLayoutManager`，为打了标记的区间画背景色块/竖线）来表示，而不是
  用独立的子 View。
- **方案 B：复合视图，每个块一个子 View**（用 `LinearLayout`/`UIStackView` 装一堆
  段落 label、一个表格 view、一个代码块 view……）。

**最终决策：采用方案 A，并为特定节点类型留一个通往方案 B 的逃生舱。** 理由：

1. **列表 cell 的开销。** 每条消息一个视图，意味着只有一次测量/排版，只有一个对象
   需要复用；相比之下 N 个子 View（数量和类型随消息内容变化）在 `RecyclerView`/
   `UITableView` 快速滚动时才是真正的性能大头，文本排版本身反而不是瓶颈。
2. **流式重新渲染的开销。** 重新渲染意味着重建一份富文本/`Spanned` 再调用一次
   `setText`，而不是去 diff 一整棵 View 树。
3. **已经被大规模验证过。** 这正是 Markwon 的做法，也是"高频聊天消息渲染 Markdown"
   这个场景目前最接近的现成范例。
4. **是逃生舱，不是教条。** 有些节点确实需要一个真正的 View——比如需要异步加载、
   支持点击放大的图片，或者需要独立于气泡横向滚动的宽表格。`THKMDView` 为每种节点
   类型预留了一个可插拔的 `BlockRenderer`/`ExternalBlockRenderer` 钩子，未来可以让
   *某个特定节点*渲染成内嵌子 View（Android：借鉴 `ImageSpan` 搭配回调、用一个离屏
   测量好的真实 `View` 填充；iOS：用 `NSTextAttachment` 承载一个渲染好的 `UIView`
   快照，或自定义 attachment view）。v0 阶段**尚未**实现这个钩子的"非文本"路径——
   表格目前渲染成纯等宽字体的兜底样式，图片也还没有加载——这些都标记为下面的 v2
   工作项。

## 4. 流式 / 增量渲染策略

最终采用的方案（两个脚手架里都已实现）：

1. `appendMarkdownChunk(chunk)` 把内容追加进内部的原始文本缓冲区——**v0 阶段不做
   增量式的语法树 diff**。
2. 每次追加都会安排一次**防抖后的整体重新解析 + 重新渲染**（默认约 32ms，可配置）。
   在防抖窗口内到达的多个分片会合并成一次渲染，这正是即便在"每几毫秒一个 token"的
   速率下依然能保持低成本的关键。
3. 因为解析器（commonmark-java / swift-markdown，二者都是符合规范的 CommonMark
   实现）每次拿到的都是*完整*缓冲区，"半截语法结构"的处理方式就是任何 CommonMark
   解析器处理"被截断文档"的天然方式——一个没闭合的 `` ``` `` 围栏会被当作未终止的
   代码块渲染，直到闭合围栏到达；没闭合的 `**` 在第二个 `**` 到达之前就是字面文本；
   打了一半的 `[link](url` 在 `)` 出现之前也是字面文本。不需要额外写一套"半成品
   Markdown"专用语法——这和上面提到的几个 Web 聊天界面的行为是一致的。
4. `reset()` 会取消任何尚未执行的防抖渲染并清空缓冲区。**必须在
   `onViewRecycled`/cell 的 `prepareForReuse` 里调用一次，并且在 `onBindViewHolder`
   绑定新 item 时再调用一次**——脚手架里的单元测试（`*ReuseTest`）专门断言了：一个
   已经被划走的消息留下的"待执行渲染"，绝不能落到接替它的视图上。
5. 刻意推迟到 v2 的工作：只重新渲染"末尾未闭合块"的增量式块级重新解析，而不是每次
   都重新解析整个缓冲区。对于典型的聊天消息长度（几百到大约几千字符）目前用不上；
   只有在真实消息长度下做过性能画像、确实证明有必要时才值得重新考虑。

## 5. 公开 API（两平台对齐）

| 概念 | Android（`com.thk.mdview.THKMDView`） | iOS（`THKMDView`） |
|---|---|---|
| 全量渲染 | `fun setMarkdown(markdown: String)` | `func setMarkdown(_ markdown: String)` |
| 流式追加 | `fun appendMarkdownChunk(chunk: String)` | `func appendMarkdownChunk(_ chunk: String)` |
| 清空/复用 | `fun reset()` | `func reset()` |
| 防抖间隔 | `var streamingDebounceMs: Long` | `var streamingDebounceInterval: TimeInterval` |
| 链接点击 | `var onLinkClick: ((String) -> Boolean)?` | `var onLinkTap: ((URL) -> Bool)?` |
| 自定义渲染 | `fun setMarkdownRenderer(renderer: MarkdownRenderer)` | `var renderer: MarkdownRendering` |

## 6. 测试策略（脚手架中已实现）

- **渲染测试**：用已知的 Markdown 样例喂进去，断言纯文本提取结果，以及在正确的位置
  出现了预期的 span/属性类型（粗体、斜体、行内代码、标题字号、链接、引用块、代码块
  背景、列表缩进）。
- **流式/分片模糊测试（chunk-fuzz）**：拿一份样例文档，按多种不同（包括随机）的边界
  切成分片，逐个喂给 `appendMarkdownChunk`，然后断言*最终*渲染结果和一次性调用
  `setMarkdown` 渲染整份文档的结果完全一致——这正是真正保护上面"半截语法结构"行为
  正确性的测试。
- **防抖合并测试**：断言在一个防抖窗口内连续到达的 N 个分片只会触发一次渲染
  （Android 用 Robolectric 的 shadow looper 控制时间，iOS 用可控的时钟/expectation）。
- **复用安全性测试**：在流式渲染进行到一半时绑定视图，调用 `reset()`/换绑到另一条
  消息，断言旧的"待执行渲染"绝不会落地。
- 目前还没做（v2 候选项）：golden/快照像素级测试、真实网络 SSE 集成测试、大文档
  性能基准测试。

## 7. 待你拍板的开放问题

1. **最低系统版本。** 脚手架默认值：Android `minSdk 21`，iOS `13`。如果你不需要覆盖
   这么老的版本，可以适当提高——这能简化一些代码路径（比如 iOS 15+ 的
   `AttributedString`/`NSTextAttachment` API 比 iOS 13 的 `NSMutableAttributedString`
   好用不少）。
2. **License。** 默认用了 MIT（见 `LICENSE`）——如果你所在组织有别的标准，可以换。
3. **包名/命名空间。** 默认用的是 `com.thk.mdview`（Android）和模块名 `THKMDView`
   （iOS/SPM）。真要往外发布之前，确认一下这些是否符合你实际的命名空间规划。
4. **表格渲染的完整度。** v0 阶段 GFM 表格在单一文本视图里渲染成纯等宽字体的兜底
   样式。要做"真正的"表格（列对齐、横向滚动、单元格内独立的行内样式）需要用到第 3
   节里提到的复合视图逃生舱——如果你的 LLM 输出里表格很常见，这个值得在 v1 优先做。
5. **代码块语法高亮。** v0 还没实现（目前只有等宽字体 + 背景色）。候选方案：
   Android 用 Prism4j 或者自己按语言写一个正则词法分析器；iOS 用 Splash（纯 Swift）
   或类似方案。两边都已经预留了可插拔的渲染器接口，随时能接进去。
6. **图片加载。** v0 还没实现（`![]()` 能解析出来，但不会真正渲染）。需要引入一个
   图片加载依赖（Android 上是 Coil/Glide，iOS 上需要一个轻量加载器或类似
   `AsyncImage` 的方案），并且要用到复合视图/attachment 那个逃生舱。
7. **Compose / SwiftUI 封装。** 按需求核心必须是 UIKit/Android View 体系（要能塞进
   `RecyclerView`/`UITableView`）。如果之后确实需要在列表之外使用，后续加一层薄薄的
   `@Composable`/SwiftUI `UIViewRepresentable` 封装并不难。
8. **分发渠道。** Android 现在每次 push 到 `main` 都会通过
   `.github/workflows/android-publish.yml` 自动发布到 GitHub Packages（Maven）；
   iOS 通过 SPM 分发，另外也配了一份 CocoaPods podspec（通过 git tag 接入，见
   `ios/README.md`）。两边都还没有上 Maven Central 或 CocoaPods 官方 trunk 仓库——
   如果需要的话这块还是开放的。

## 8. 路线图

- **v0（当前脚手架）** —— 工程结构、构建工具链、核心的 Markdown → span/富文本渲染
  管线（粗体/斜体/删除线/行内代码/标题/列表/引用/代码块/链接/任务列表）、流式缓冲区
  + 防抖、可安全复用的 API、单元测试、示例 App。
- **v1** —— 真正的表格渲染、图片加载 + 点击放大、主题化 API（把颜色/字体/间距整合
  成一个 `Theme`/样式对象）、链接预览钩子。
- **v2** —— 语法高亮、块级增量重新解析（只有在性能画像证明"整体重新解析"在你的
  消息长度下确实是瓶颈时才做）、Compose/SwiftUI 封装。
- **v3** —— 发布流水线（Maven Central + SPM 官方索引/CocoaPods trunk）、golden/
  快照可视化回归测试、无障碍能力审查（对每种节点类型过一遍 VoiceOver/TalkBack）。
