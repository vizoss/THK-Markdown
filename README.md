# THKMDView

面向 AI 聊天、流式回复和文章阅读的 Android / iOS Markdown 视图组件。

正文使用原生文本视图排版；表格独立横向滚动。Mermaid 与数学公式使用随库打包的离线 WebView / WebKit 资源，不把整篇文章放进网页。支持整篇设置、增量追加、主题切换、图片加载器注入，以及可选的 SSE 状态 UI。

> **接入边界**：THKMDView 是渲染组件，不是聊天 SDK 或 SSE 网络客户端。连接、事件解析、消息存储、重试策略、鉴权和业务路由由宿主应用管理。

## 目录

- [能力与限制](#能力与限制)
- [环境要求](#环境要求)
- [安装依赖](#安装依赖)
- [基础使用与布局](#基础使用与布局)
- [SSE 与状态展示](#sse-与状态展示)
- [主题配置](#主题配置)
- [链接图片点击与复制](#链接图片点击与复制)
- [图片加载与缓存](#图片加载与缓存)
- [公式缓存](#公式缓存)
- [列表复用与生命周期](#列表复用与生命周期)
- [自定义解析器与异常处理](#自定义解析器与异常处理)
- [业务接入检查清单](#业务接入检查清单)
- [示例工程与开发](#示例工程与开发)
- [贡献与许可证](#贡献与许可证)

## 能力与限制

| 能力 | 当前行为 |
| --- | --- |
| 基础 Markdown | 标题、粗体、斜体、删除线、链接、引用、分隔线、有序/无序列表、代码 |
| GFM 表格 | 顶层表格、列对齐、单元格行内格式，宽表格独立横向滚动 |
| 任务列表 | 显示勾选状态；不是可编辑表单，不提供勾选写回 |
| 图片 | 行内异步加载、占位、点击回调；加载完成可能改变布局高度 |
| 复制 | 代码块和最外层引用的复制按钮、可配置成功提示；不是整条消息操作栏 |
| Mermaid | 顶层 `mermaid` 代码围栏渲染为图表；嵌套围栏按代码显示 |
| 提示块 | NOTE、TIP、IMPORTANT、WARNING、CAUTION |
| 脚注 | 基础编号与文末定义；不提供跳转/回跳、递归脚注或跨消息引用 |
| 数学公式 | 行内/块级 TeX，MathJax base/AMS 子集；不是完整 LaTeX 文档引擎 |
| 流式渲染 | 分片合并刷新、通用块级增量解析，必要时全文回退 |
| SSE 状态 | 等待、输出、完成、停止、失败；默认三个点，可替换为外部视图 |
| 代码高亮 | **暂不支持**；当前为等宽字体和主题背景 |
| 原始 HTML | 按文本安全降级，不当作可执行网页 |
| 嵌套表格 | 引用/列表中的表格按文本降级，不保证与顶层表格相同的交互 |

两端分别使用 **commonmark-java** 和 **swift-markdown**。iOS 的 SPM 与 CocoaPods 共用 swift-markdown，不再使用 Maaku。

平台字体、字形和换行系统不同，不承诺逐像素完全一致，也不默认做左右两端对齐。扩展语法、公式限制与示例见 [P3 文档](docs/P3.zh-CN.md)。

增量解析复用稳定的顶层块，重新解析可能变化的尾部；链接定义、脚注、历史内容修改等场景会回退全文解析。全文预处理与富文本生成仍有成本，单个长容器也可能整体重解析，不能将“增量”理解为任意长度文本都只处理新增字符。详见 [性能说明](docs/performance-review.md)。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| Android 运行环境 | API 21+ |
| Android 仓库构建 | JDK 17；仓库使用 AGP 8.5.2、Kotlin 1.9.24、compileSdk 34，使用随仓库提供的 Gradle Wrapper |
| iOS 库运行环境 | iOS 13+，UIKit |
| iOS 源码/二进制构建 | Xcode 26+ / Swift 6.2+；当前固定的 swift-markdown 依赖要求该工具链 |
| iOS 示例 | iOS 15+；重新生成工程需要 XcodeGen |
| 网络 | 纯文本、Mermaid 和公式无需运行时联网；远程图片、真实 SSE 和周刊正文需要网络 |

这里是当前仓库的要求，不代表任意旧工具链都能消费新构建的 XCFramework。

## 安装依赖

### Android：本地模块

将本仓库作为源码依赖放到项目旁边，在宿主 `settings.gradle.kts` 中接入：

```kotlin
include(":thkmdview")
project(":thkmdview").projectDir = file("../thk-markdown/android/thkmdview")
```

在应用模块中：

```kotlin
dependencies {
    implementation(project(":thkmdview"))
}
```

宿主需要配置 `google()` 和 `mavenCentral()`，并提供兼容的 Android/Kotlin 插件配置。上述相对路径按你的目录调整。

### Android：Maven / AAR

仓库配置的发布坐标是：

```kotlin
implementation("com.thk.mdview:thkmdview:<已发布版本>")
```

发布仓库为 GitHub Packages，不是 Maven Central：

```kotlin
// 宿主 settings.gradle.kts 的 dependencyResolutionManagement.repositories
maven {
    url = uri("https://maven.pkg.github.com/vizoss/THK-Markdown")
    credentials {
        username = providers.gradleProperty("gpr.user").orNull
            ?: System.getenv("GITHUB_ACTOR")
        password = providers.gradleProperty("gpr.token").orNull
            ?: System.getenv("GITHUB_TOKEN")
    }
}
```

使用有包读取权限的凭据，存放在用户级 `~/.gradle/gradle.properties` 或 CI secrets，**不要提交令牌**。是否还需组织授权取决于你的 GitHub 账号与组织设置。

CI 按 `<VERSION_NAME>-build<run_number>` 生成版本；请从实际发布记录选择版本。仓库中的 `VERSION_NAME=0.1.0` 不等于已经发布了名为 `0.1.0` 的可下载包，本 README 不承诺某个远端版本当前可用。

推荐通过带 POM 的 Maven 包或源码模块集成。单独复制 AAR 不会自动带入 Maven 传递依赖，需要自行补齐：AndroidX Core/AppCompat、协程 Android、commonmark-java 及 GFM 表格、删除线、任务列表扩展。精确版本以 [库构建配置](android/thkmdview/build.gradle.kts) 为准；不要遗漏 AAR 内的 HTML/JS assets。

### iOS：SPM 源码

**当前 Package.swift 位于 `ios/`，不在仓库根目录。** 克隆仓库后，在 Xcode 中添加本地 package，选择该 `ios/` 目录，并将 **THKMDView** product 链接到业务 target。

从另一个本地 Swift package 引用：

```swift
// Package.swift 相关片段；路径按宿主位置调整
dependencies: [
    .package(path: "../thk-markdown/ios")
]
// 宿主 target 的 dependencies：
.product(name: "THKMDView", package: "ios")
```

不要直接将仓库根 URL 当作远程 SPM 包地址；当前目录布局不支持这种安装方式。只有当分发仓库/版本在根目录提供 Package.swift 时，才能按标准远程 SPM 方式安装。

业务只需依赖 `THKMDView`，不要依赖例子使用的 `MarkdownFixtures`。源码接入时解析器依赖和资源由 SPM 管理。

### iOS：CocoaPods 二进制

CocoaPods 路线使用 **预编译 XCFramework**，不是通过 pod 编译 Git 仓库里的 Swift 源码。

已有本地二进制产物时：

```ruby
platform :ios, '13.0'

target 'YourApp' do
  pod 'THKMDView', :path => '/path/to/THKMDView-release'
end
```

产物目录需要同时包含 podspec 与 `THKMDView.xcframework`。维护者发布了匹配版本的 ZIP 和 podspec 后，才可使用远端 podspec：

```ruby
# <版本> 为实际存在、已验证的发布版本，不能原样复制。
pod 'THKMDView',
    :podspec => 'https://raw.githubusercontent.com/vizoss/THK-Markdown/v<版本>/THKMDView.podspec'
```

根目录 podspec 中的版本号不是“已上传 Release / 已发布到 CocoaPods trunk”的证明。现有二进制工作流生成候选附件，不自动发布 Release 或 trunk。

- 同一个业务 target 不要同时安装 THKMDView 的 SPM 和 pod 版本。
- 二进制内包含解析器与渲染资源，不包含 Example、Fixtures、30 组模拟回复、周刊目录或主题设置页面。
- 二进制构建、资源检查、许可证和发布步骤见 [iOS Binary](ios/Binary/README.md)。

## 基础使用与布局

### Android

```kotlin
import com.thk.mdview.THKMDView

val markdownView = THKMDView(context).apply {
    layoutParams = android.widget.LinearLayout.LayoutParams(
        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
        android.view.ViewGroup.LayoutParams.WRAP_CONTENT
    )
    setMarkdown("# 你好\n\n这是一段 **Markdown**。")
}
container.addView(markdownView) // container 为宿主的 LinearLayout
```

也可以使用 XML：

```xml
<com.thk.mdview.THKMDView
    android:id="@+id/markdownView"
    android:layout_width="match_parent"
    android:layout_height="wrap_content" />
```

THKMDView 是 **LinearLayout，不是 TextView**。不要用 `android:textSize`、`android:textColor`、`android:maxWidth` 等 TextView 专属属性配置它。样式使用 `theme`；宽度上限使用 `maxContentWidthPx`（px，非正数表示不限制）。

### iOS

```swift
import UIKit
import THKMDView

let markdownView = THKMDView()
markdownView.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(markdownView)

NSLayoutConstraint.activate([
    markdownView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
    markdownView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
    markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
])
markdownView.setMarkdown("# 你好\n\n这是一段 **Markdown**。")
```

以上仅演示短内容的尺寸约束。长文章请把它放进 UIScrollView，并约束到 contentLayoutGuide，同时将内容宽度固定到 frameLayoutGuide；不要将长文章固定在一个不足以容纳正文的高度里。

### 通用约定

| API | 作用 |
| --- | --- |
| `setMarkdown` | 完整替换正文，立即渲染 |
| `appendMarkdownChunk` | 追加增量文本，防抖后刷新；传的是新增内容，不是每次累计全文 |
| `reset` | 清空正文、待渲染任务、附件任务和旧分段，SSE 状态回到 idle |
| `theme` | 重新渲染现有内容；赋相同主题不重复渲染 |
| `imageLoader` | 注入业务图片加载/缓存服务，建议在设置正文之前完成 |

视图不提供整篇正文的独立垂直滚动，交给 UIScrollView、UITableView、RecyclerView 等宿主。不要手动添加业务子视图到组件内部，其子视图由渲染器管理。

**所有视图 API 在主线程调用。** 网络线程收到消息后先切回主线程；不要每到一个 token 就 reset 或 setMarkdown。

图片、图表、公式异步完成，以及主题变化，都可能改变高度。iOS 自适应列表可通过 `onContentSizeChange` 合并刷新行高，避免在回调中递归 setMarkdown；Android 正常使用 wrap_content 和布局更新。滚动跟随、保持阅读位置由业务负责。

## SSE 与状态展示

### 最小接入

```swift
markdownView.sseEnabled = true
markdownView.setSSEState(.waiting)
// 业务从 SSE 事件中提取出的正文增量：
markdownView.appendMarkdownChunk("首先，我们可以")
markdownView.appendMarkdownChunk("把问题拆成三步。")
// 收到业务协议的完成事件：
markdownView.setSSEState(.completed)
```

```kotlin
import com.thk.mdview.THKSSEState

markdownView.sseEnabled = true
markdownView.setSSEState(THKSSEState.WAITING)
markdownView.appendMarkdownChunk("首先，我们可以")
markdownView.appendMarkdownChunk("把问题拆成三步。")
markdownView.setSSEState(THKSSEState.COMPLETED)
```

| 状态（iOS / Android） | 默认 UI |
| --- | --- |
| idle / IDLE | 不展示状态 |
| waiting / WAITING | 三个点；正文为空时单独显示，有正文时在正文下方显示 |
| streaming / STREAMING | 正文下方左对齐三个点，持续闪烁 |
| completed / COMPLETED | 刷新尾部缓冲、隐藏圆点、保留正文 |
| stopped / STOPPED | 刷新尾部缓冲、隐藏圆点、保留正文 |
| failed / FAILED | 刷新尾部缓冲、保留正文，显示错误文字及可选重试按钮 |

等待状态收到非空分片会自动变为输出中；完成、停止、失败由业务通知，不能从“暂时没有分片”猜测结束。`setSSEState` 不会替业务取消网络请求。

`onRetry` 只通知业务，不自动重连或清空文本：

```swift
markdownView.onRetry = { [weak self] in self?.retryCurrentMessage() }
markdownView.setSSEState(.failed, errorMessage: "连接中断，已保留收到的内容")
```

```kotlin
markdownView.onRetry = { retryCurrentMessage() }
markdownView.setSSEState(THKSSEState.FAILED, "连接中断，已保留收到的内容")
```

这里的 `retryCurrentMessage` 是宿主方法。业务决定续传还是重新生成，并用消息 ID / 尝试 ID 拦截晚到的旧回调。

### 自定义三个点或替换 UI

- `sseEnabled` 默认 false，不影响普通 Markdown。
- `sseStatusUIEnabled = false` 关闭整个内建状态层，包括失败提示。
- `sseIndicatorView` 接收业务 UIView / View，替换等待和输出中的圆点；nil / null 恢复默认。
- `onSSEIndicatorActivityChanged` 通知自定义动画启停；`onSSEStateChanged` 通知消息状态变化。
- 自定义视图不能同时属于另一个父容器；iOS 需提供固有高度或高度约束，Android 使用自身测量高度。
- 先设置动画回调，再开启状态。移出窗口、替换、reset 会停止动画；仍挂在窗口内但被宿主裁剪的离屏视图，由宿主控制显示。
- `sseIndicatorStyle` 可设颜色、直径、间距和周期；默认 6pt/dp、间距 5、周期 0.9 秒，颜色跟随正文主题。

```swift
markdownView.sseIndicatorStyle = THKSSEIndicatorStyle(
    color: .systemBlue, diameter: 6, gap: 5, cycleDuration: 0.9
)
markdownView.sseIndicatorView = customIndicator
markdownView.onSSEIndicatorActivityChanged = { [weak customIndicator] _, active in
    customIndicator?.setAnimating(active) // 业务自定义方法
}
```

```kotlin
import com.thk.mdview.THKSSEIndicatorStyle

markdownView.sseIndicatorStyle = THKSSEIndicatorStyle(
    color = android.graphics.Color.BLUE, diameterDp = 6f, gapDp = 5f, cycleMs = 900
)
markdownView.sseIndicatorView = customIndicator
markdownView.onSSEIndicatorActivityChanged = { _, active ->
    customIndicator.setAnimating(active) // 业务自定义方法
}
```

默认刷新防抖为 **32ms**：iOS `streamingDebounceInterval` 单位秒（0.032），Android `streamingDebounceMs` 单位毫秒（32）。连续到来的分片会合并刷新，业务必须发送终态以立即提交最后一段。**流式追加不等于匀速逐字打字机**；要逐字展示一个大分片，应由业务另行调度。

完整契约与错误边界见 [SSE 接入说明](docs/sse.md)。

## 主题配置

从默认主题复制后修改，不必从零填写全部字段：

```swift
var theme = THKMDTheme.default
theme.bodyFontSize = 17
theme.headingTextColor = .systemBlue
theme.backgroundColor = .clear
theme.copyFeedbackBackgroundColor = UIColor.black.withAlphaComponent(0.8)
markdownView.theme = theme
```

```kotlin
import com.thk.mdview.THKMDTheme

markdownView.theme = THKMDTheme.Default.copy(
    bodyFontSizeSp = 17f,
    headingTextColor = 0xFF2563EB.toInt(),
    backgroundColor = android.graphics.Color.TRANSPARENT,
    copyFeedbackBackgroundColor = 0xCC000000.toInt()
)
```

### 字段速查

字段双端同名，除非表中分别列出。Android 颜色是 ARGB Int，iOS 为 UIColor。

| 字段 | 用途 / 默认值 |
| --- | --- |
| `bodyTextColor` | 正文、列表、表格正文 |
| `headingTextColor` | 标题、表头 |
| `linkColor` | 链接、脚注序号、默认 SSE 重试按钮 |
| `backgroundColor` | 整个组件背景，默认透明 |
| `bodyFontSizeSp` / `bodyFontSize` | Android sp / iOS pt，默认 15 |
| `codeFontSizeSp` / `codeFontSize` | Android sp / iOS pt，默认 13 |
| `heading1Scale`～`heading6Scale` | 正文字号倍率：1.6、1.4、1.25、1.15、1.05、1.0 |
| `codeTextColor` / `codeBackgroundColor` | 行内代码、代码块文字与背景；复制图标复用代码文字色 |
| `codeBlockCornerRadiusDp` / `codeBlockCornerRadius` | 代码和引用背景圆角，dp / pt，默认 8 |
| `blockQuoteBarColor` | 引用竖线与分隔线 |
| `blockQuoteTextColor` | 引用正文，保留独立的链接和代码颜色 |
| `blockQuoteBackgroundColor` | 最外层引用背景 |
| `tableBorderColor` / `tableHeaderBackgroundColor` | 表格边框与表头背景 |
| `imagePlaceholderColor` | 图片加载中和失败的占位背景 |
| `alertNoteColor` / `alertTipColor` / `alertImportantColor` / `alertWarningColor` / `alertCautionColor` | 提示块标题和竖线；正文与背景使用引用主题 |
| `footnoteScale` | 脚注序号倍率，默认 0.75 |
| `mathScale` | 公式字号倍率，默认 1；文字色使用 bodyTextColor |
| `listBulletScale` | **仅 Android**，圆点直径与正文字号之比，默认 0.20；iOS 使用字体圆点字形 |
| `copyFeedbackTextColor` / `copyFeedbackBackgroundColor` | 复制成功提示的文字/背景，默认白字、黑色 75% 不透明度 |
| `copyFeedbackFontSizeSp` / `copyFeedbackFontSize` | 复制成功提示字号，sp / pt，默认 12 |

Mermaid 复用正文、代码、表格、引用的主题颜色。SSE 圆点的独立配置使用 `sseIndicatorStyle`，不在 THKMDTheme 中。

默认主题不是自动深色模式。宿主应在外观变化时赋予匹配的主题；iOS 的主题字号是显式 pt 值，需要宿主根据 Dynamic Type 策略调整，不能假定所有正文会自动缩放。SDK 不持久化主题，示例的 UserDefaults / SharedPreferences 保存逻辑只是业务参考。

主题只控制 Markdown 与其状态展示，不控制导航栏、输入框、消息气泡或系统剪贴板提示。完整定义：[Android](android/thkmdview/src/main/java/com/thk/mdview/THKMDTheme.kt) / [iOS](ios/Sources/THKMDView/THKMDTheme.swift)。

## 链接图片点击与复制

### 点击回调：返回值不要写反

| 平台 | 业务已处理点击时 | 不处理时 |
| --- | --- | --- |
| iOS `onLinkTap` / `onImageTap` | 返回 **false**，拦截默认交互 | true / 未设置允许系统默认交互，行为依内容位置而异 |
| Android `onLinkClick` / `onImageClick` | 返回 **true** 表示业务处理 | 当前组件不负责默认打开浏览器；不要指望 false 自动跳转 |

建议两个平台都显式设置链接和图片回调，由业务统一路由：

```swift
markdownView.onLinkTap = { [weak self] url in
    self?.routeAllowedURL(url) // 校验 scheme / 域名后再处理
    return false
}
markdownView.onImageTap = { [weak self] url in
    self?.presentImage(url)
    return false
}
```

```kotlin
markdownView.onLinkClick = { url ->
    routeAllowedURL(url)
    true
}
markdownView.onImageClick = { url ->
    presentImage(url)
    true
}
```

`routeAllowedURL` / `presentImage` 是业务函数，不是库 API。Android 图片未设回调时回退到链接回调；iOS 正文图片与表格图片的默认回退不完全一致，因此**不要依赖默认行为实现跨端路由**。库不提供统一的文章 baseURL 参数，相对链接/图片需要业务在输入或加载器中解析。

复制按钮会复制对应块的可见文本；其中的公式按 TeX 源码还原。成功提示显示在按钮附近，可通过主题设置颜色与字号；Android 系统可能另外显示系统剪贴板提示。库没有公开“复制成功事件”回调，也不自动提供整篇复制按钮。

## 图片加载与缓存

### 默认实现

| 项目 | Android | iOS |
| --- | --- | --- |
| 默认加载器 | `DefaultTHKImageLoader` | `DefaultTHKImageLoader` |
| 网络 | HttpURLConnection | URLSession |
| 内存缓存 | 按 Bitmap 字节数计费的 LruCache；默认约 JVM 最大堆的 1/8 | NSCache；未设置公开的固定容量上限 |
| 磁盘缓存 | `cacheDir/thkmdview_image_cache` | caches 目录下 `THKMDView/ImageCache` |
| 缓存键 | URL 字符串 SHA-256 | URL 字符串 SHA-256 |
| 默认构造配置 | memoryCacheBytes、diskCacheDir、fetcher | URLSession |
| 图片缓存公共管理 API | 没有统一的 THKMDView 图片容量/清理 API | 同左 |

默认磁盘缓存**没有库级 TTL 或容量淘汰策略**，也没有账号隔离协议。URL 相同而内容变化时可能返回旧图；带鉴权的私有图片不应未经设计就写入共享持久缓存。

**生产业务推荐注入已有图片服务**，统一管理容量、缓存键、认证、账号隔离、清理和请求取消。可以共享一个加载器实例，避免每个消息视图各持有一套独立内存缓存。

### Android：配置默认加载器

```kotlin
import com.thk.mdview.DefaultTHKImageLoader

val sharedLoader = DefaultTHKImageLoader(
    context = applicationContext,
    memoryCacheBytes = 16 * 1024 * 1024,
    diskCacheDir = java.io.File(applicationContext.cacheDir, "chat_images")
)
markdownView.imageLoader = sharedLoader
```

`memoryCacheBytes` 必须为正数；不要用 0 表示禁用图片缓存。如果要完全无缓存，提供自己的加载器。

### 双端：注入业务图片服务

以下为可复用的适配器定义，`fetch` 闭包由业务连接自己的图片框架：

```kotlin
import android.graphics.Bitmap
import com.thk.mdview.THKImageLoader
import kotlinx.coroutines.CancellationException

class AppImageLoader(
    private val fetch: suspend (String) -> Bitmap?
) : THKImageLoader {
    override suspend fun load(url: String): Bitmap? = try {
        fetch(url)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}
```

```swift
import UIKit
import THKMDView

struct AppImageLoader: THKImageLoading {
    let fetch: (URL) async -> UIImage?
    func load(url: URL) async -> UIImage? {
        await fetch(url)
    }
}
```

将适配器实例赋给 `markdownView.imageLoader`，再设置正文。无需为此修改库或新增图片缓存容量 API。

业务加载器需要注意：

- 失败返回 nil / null；响应任务取消，并取消底层网络或解码工作，避免只丢弃结果却继续下载。
- 异步接口不等于无限并发许可：耗时磁盘、网络、解码不要阻塞 UI，限制并发与响应大小。
- 凭据、请求头、签名 URL 更新由加载器负责；缓存键不能忽略账号与授权上下文。
- 使用 HTTPS、验证 MIME / 尺寸，对不可信 URL 做协议和域名限制。默认加载器不是完整的安全下载沙箱。
- 图片真实尺寸到达后可能重新排版，不要在聊天宿主中假定气泡高度固定。
- 修改 iOS URLSession 的 URLCache 不会关闭默认加载器自身的磁盘图片缓存；需要完全控制缓存时替换加载器。
- 切换加载器不会自动清空原加载器缓存；建议绑定正文前注入。若需让当前内容重新请求，可用 setMarkdown 重新设置业务保存的正文。
- 内部公式图片不走业务图片加载器。GIF/动画、SVG、复杂格式的支持不要按专用图片浏览器推断，应由业务适配并验证。

## 公式缓存

公式缓存与图片缓存是两回事，属于**进程级共享**缓存。默认预算 8 MiB，主线程配置：

```swift
THKMDView.configureMathCache(maxBytes: 16 * 1024 * 1024)
THKMDView.clearMathCache()
```

```kotlin
THKMDView.configureMathCache(maxBytes = 16 * 1024 * 1024)
THKMDView.clearMathCache()
```

设为 0 禁用公式结果缓存；负数非法。改变预算会清空已有缓存，清理缓存不会销毁引擎或停止在途任务。iOS NSCache 容量是建议性限制，**不是整个渲染器的内存硬上限**。相同公式请求可合并，取消一个订阅不取消其他订阅。

## 列表复用与生命周期

消息正文、状态和尝试 ID 必须保存在业务模型中，而不是只存进一个 cell。滚动复用时从模型恢复。

**Android：**

```kotlin
// 绑定另一条消息前
holder.markdown.reset()
holder.markdown.theme = appTheme
holder.markdown.sseEnabled = true
holder.markdown.setMarkdown(message.content)
holder.markdown.setSSEState(message.state)

// onViewRecycled 中
holder.markdown.reset()
holder.markdown.onRetry = null
```

其中 holder、appTheme、message 为宿主对象，message.state 类型为 THKSSEState。reset 会清理 Mermaid WebView、待渲染任务和附件；临时 detach 不清空正文，必要时重新挂载后恢复。

**iOS：**

```swift
override func prepareForReuse() {
    super.prepareForReuse()
    markdownView.reset()
    markdownView.onRetry = nil
}
```

控制器被回调捕获时使用 `[weak self]`，并在页面退出时取消业务 SSE 任务。reset **不会**关闭宿主网络连接，也不会清空业务历史或共享缓存；主题、加载器、自定义状态视图与回调配置仍由业务负责重新绑定。

异步高度变化可参考 [iOS 列表宿主](ios/Example/Sources/DemoMessageListViewController.swift)；Android 参考 [ChatAdapter](android/sample/src/main/java/com/thk/mdview/sample/ChatAdapter.kt)。宿主自行控制是否跟随最新消息，避免用户阅读历史时被强制拉回底部。

## 自定义解析器与异常处理

- Android：实现 `MarkdownRenderer`，通过 `setMarkdownRenderer` 注入。
- iOS：实现 `MarkdownRendering`，赋给 `renderer`；通过可抛错的 `renderSafely` / `renderFull` 报告可恢复错误，旧的源码实现有默认适配。
- 输出支持文本、表格、Mermaid 分段；渲染器需要正确维护主题、格式范围与复制范围。通常只需配置主题，不需要替换解析器。

发生可恢复解析异常时，先全量重试，仍失败则显示原始纯文本，并通过 `onRenderFailure` 报告阶段和错误。下一次正文更新仍尝试正常解析。**解析异常不自动变成 SSE 请求失败**。

Android 不吞掉 OOM 等 JVM Error；Swift trap、Objective-C 异常和底层原生崩溃不能通过 Swift throws 捕获。这也不是对任意 UI 布局错误的兜底。错误回调不要无条件重新 setMarkdown，以免形成递归重试。

## 业务接入检查清单

- [ ] 所有视图更新在主线程，输入为正确解码的 Unicode 文本，不直接追加 SSE 原始 `data:` 行或 JSON。
- [ ] 分片是 delta 而非累计全文；结束、失败和停止均显式通知。
- [ ] 每次请求有消息 ID / 尝试 ID，取消后丢弃晚到的旧回调。
- [ ] 复用时 reset，再恢复正文、状态、主题和事件回调。
- [ ] 状态视图启停与宿主可见性一致；后台不持续播放业务动画。
- [ ] iOS 列表处理异步高度变化，双端在窄屏、大字体、长文下验收。
- [ ] 显式拦截链接和图片点击，限制 URL 协议/域名，按业务确认外部跳转。
- [ ] 远程图片配置网络权限与 HTTPS 策略；Android 宿主声明 INTERNET，iOS 遵循 ATS，不为方便而全局放开明文 HTTP。
- [ ] 图片缓存有容量、过期、账号隔离和退出登录清理策略。
- [ ] 保留 Mermaid / MathJax 资源及第三方许可证，不把示例数据打进业务库。
- [ ] 不把测试用例数量、源码编译通过或模拟 SSE 通过当作线上协议、性能与视觉验收完成。

不可信 Markdown 仍可能触发图片请求、消耗大量布局资源或提供恶意链接。建议宿主限制单消息长度、图片大小、并发数量与可访问地址；禁用 HTML 执行不等于内容完全无风险。

## 示例工程与开发

首页提供四个入口：

1. **ShowCase 格式显示**：P0～P3 共 139 个共享用例，全文、播放、暂停、单步与验收说明。
2. **SSE Chat**：30 组共享复杂回复。本地模拟等待和流式输出；输入 1～30 选题，10/20/30 演示失败与重试，输入 `/停止` 中止。
3. **科技周刊**：阮一峰周刊第 364～413 期，共 50 篇，在线读取 Markdown 正文。
4. **主题设置**：即时修改并本地保存；保存逻辑属于例子，不属于库。

两个例子共享用例与回复 JSON；业务库不依赖示例应用。周刊来源：[ruanyf/weekly](https://github.com/ruanyf/weekly)。

### 仓库结构

```text
android/thkmdview/     Android 库
android/sample/        Android 示例
ios/Sources/THKMDView/ iOS 库
ios/Example/           iOS 示例
ios/Fixtures/          双端共享 Markdown 用例
ios/Binary/            XCFramework 构建配置
examples/sse/          30 组模拟回复
examples/weekly/       50 篇周刊目录
docs/                  专题与验收文档
```

### 构建与测试

```sh
# Android：仓库根目录执行
cd android
./gradlew :thkmdview:testDebugUnitTest :sample:assembleDebug
```

```sh
# iOS：仓库根目录执行
cd ios/Example
xcodegen generate
xcodebuild build -project Example.xcodeproj -scheme Example \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

iOS XCTest 需要选择可用模拟器目标；UIKit 项目不能用普通 macOS `swift test` 代替。详细开发说明：[Android](android/README.md) / [iOS](ios/README.md)。二进制构建见 [Binary 指南](ios/Binary/README.md)。

仓库测试覆盖解析对照、分片、复用、主题、图片、SSE 状态和降级等行为。WebView 实际绘制、长列表性能和双端视觉效果仍需运行时验收，不宣称完全符合全部 CommonMark/GFM 边界或“零泄漏”。

## 贡献与许可证

欢迎通过 [Issues](https://github.com/vizoss/THK-Markdown/issues) 提交问题。请尽量提供：

- 平台、系统版本、接入方式和库版本/提交；
- 最小 Markdown 输入、分片顺序、主题配置；
- 预期与实际结果、截图或脱敏日志；
- 是否仅在流式、复用、字体变化或特定宽度下发生。

修改解析、布局或公开 API 时，请补充相应测试；涉及双端能力时同步评估两端并更新文档。不要提交访问令牌、私人会话内容或未经授权的数据。

本项目采用 [MIT License](LICENSE)。内置 Mermaid、MathJax、图标及解析器依赖保留各自的许可证；请保留分发产物中的第三方许可文件。周刊文章与外部图片不是本项目原创内容，不因本项目的 MIT 许可而改变其原有权利归属。
