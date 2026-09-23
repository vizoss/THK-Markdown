# Markdown 主题配置

双端 Markdown SDK 的颜色与字号统一由 `THKMDTheme` 提供。主题文件中每个配置项均说明用途；Android 字号为 sp、圆角为 dp，iOS 为 pt。具体色值和字号只作为主题默认值存在，不应散落在渲染逻辑里。

## 本次补齐

- `heading1Scale`～`heading6Scale`：六级标题相对正文字号的倍率。
- `imagePlaceholderColor`：图片加载中和加载失败时的占位底色。
- iOS `copyFeedbackTextColor`、`copyFeedbackBackgroundColor`、`copyFeedbackFontSize`：自绘复制提示；提示尺寸随字号自适应。Android 使用系统 Toast，其样式由系统负责。
- Mermaid：正文主题控制文字颜色/字号，代码背景控制节点底色，表格边框控制节点边框和连线，引用/表头背景控制次级区域。即使源码未改变，切换主题也会更新图形。
- iOS SPM 与 CocoaPods 两套 renderer 同步接入标题倍率和图片占位色。

## 使用

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

## 扫描范围与保留项

- 范围是 Markdown SDK 自有渲染及 Mermaid 模板。示例 App 导航栏、输入框、选择器属于宿主 UI，不由 Markdown 主题接管；示例主题预设本身的常量是配置值，mock 蓝色图片是测试数据。
- 透明的子视图/WebView 用于背景合成，不是额外视觉配色。iOS 复制图标的黑色笔画只是 template image 的 alpha 遮罩，显示颜色来自主题。第三方 vendored Mermaid 源码不直接修改，通过主题变量覆盖其基础配色。
- 新字段可通过上述 API 配置；示例主题面板尚未为每个新增字段添加控件。

## 验证记录

- 双端 IDE 构建并运行成功，P0-14 现场确认使用主题颜色渲染图形，并验证不改源码从 Default 切到 Vibrant 后图形更新。
- Android 新增 `ThemeConfigurationTest` 单独运行通过。
- Android 全量测试本次运行 64 项，1 项失败：`P0FixtureTest` 的 P0-05 copy range 断言；尚未在基线独立复现，不能宣称与此次改造无关或全量通过。
- iOS 新增标题倍率/Mermaid 字号断言，但未执行 iOS 单元测试或 CocoaPods 构建。
