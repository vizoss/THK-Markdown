# THKMDView · iOS

UIKit Markdown 库，最低 iOS 13；示例最低 iOS 15。

业务安装、公开 API、主题、点击事件、图片缓存和生命周期以 [主 README](../README.md) 为准。本页只维护 iOS 构建与开发说明。

## 两种分发，一套解析器

- **SPM**：编译源码，解析器为 swift-markdown。
- **CocoaPods**：集成预编译 XCFramework，内部静态链接同一套解析器依赖。
- 不再提供 Maaku 线路；不要在同一个 target 同时依赖 SPM 和 pod 版本。

[Package.swift](Package.swift) 位于本目录，不在仓库根目录。当前使用方式是克隆仓库后添加本地 `ios/` package，不能直接把仓库根 URL 当作远程 SPM 包。

业务 target 只链接 THKMDView product；MarkdownFixtures 仅供示例与测试使用。

当前固定的 swift-markdown revision 要求 **Xcode 26+ / Swift 6.2+**。库的 iOS 部署下限与构建工具链要求不是同一件事。

## 构建示例

示例工程由 [XcodeGen 配置](Example/project.yml) 生成。以下从仓库根目录执行：

```sh
cd ios/Example
xcodegen generate
xcodebuild build -project Example.xcodeproj -scheme Example \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

也可直接在 Xcode 打开已有的 `ios/Example/Example.xcodeproj`。修改 project.yml 后需重新生成。首次构建需要下载 Swift 包依赖；真机运行需配置自己的签名团队。

## 测试

Example scheme 包含库测试和共享用例。先查询可用设备，再用实际 UDID 替换占位符：

```sh
xcrun simctl list devices available
# 以下在 ios/Example 下执行
xcodebuild test -project Example.xcodeproj -scheme Example \
  -destination 'platform=iOS Simulator,id=<UDID>'
```

本项目依赖 UIKit，普通 macOS `swift test` 不能替代 iOS Simulator 测试。测试目录见 [Tests](Tests/)；测试通过不等于 WebKit 绘制、长列表性能或双端视觉效果已经验收。

## 示例入口

首页提供 ShowCase 格式显示、SSE Chat、科技周刊、主题设置四个入口。

- ShowCase：P0～P3 共享用例与分片播放。
- SSE Chat：30 组本地模拟回复；输入 1～30 选题，10/20/30 演示失败与重试，输入 `/停止` 中止。
- 科技周刊：50 篇周刊目录，联网读取 Markdown 正文。
- 主题设置：完整页面编辑并本地保存，返回内容页面后应用。

示例业务代码位于 [Example/Sources](Example/Sources/)，不进入 XCFramework。库本身不保存主题、不连接 AI 服务、不持有业务聊天记录。

## 集成注意

- 给 THKMDView 确定宽度，用固有高度或宿主自适应布局；整篇纵向滚动由宿主负责。
- 视图更新在主线程；`onContentSizeChange` 用于异步内容完成后的行高刷新，应合并更新，避免递归布局。
- 控制器回调使用弱引用；复用时 reset，并取消业务网络任务、重新绑定消息状态。
- `onLinkTap` / `onImageTap` 返回 **false** 表示拦截默认行为，与 Android 回调约定不同。
- 图片真实尺寸到达后可能改变行高；建议注入业务图片服务统一管理缓存、认证和取消。
- 默认主题不会自动适配深色模式或业务 Dynamic Type 策略；宿主调整主题并自行保存。
- SPM 通过 Bundle.module 加载离线资源；二进制从框架 bundle 加载，不能遗漏 Mermaid / MathJax 文件。

更多示例见 [基础使用](../README.zh-CN.md#基础使用与布局)、[主题配置](../README.zh-CN.md#主题配置)、[图片缓存](../README.zh-CN.md#图片加载与缓存)、[生命周期](../README.zh-CN.md#列表复用与生命周期)。

## 二进制与 CocoaPods

构建、检查资源、消费端 lint、本地 pod 与发布步骤见 [Binary 指南](Binary/README.md)。

源码仓库里的 podspec 不是已发布二进制的证明。必须有匹配版本的 XCFramework ZIP 和 podspec，远端安装才成立。示例、Fixtures、模拟回复、周刊目录和测试不随库打包。

## 专题

- [SSE 接入](../docs/sse.md)
- [P0](../docs/P0.zh-CN.md) / [P1](../docs/P1.zh-CN.md) / [P2](../docs/P2.zh-CN.md) / [P3](../docs/P3.zh-CN.md)
- [性能与增量解析](../docs/performance-review.md)

历史 Maaku、源码 pod 或旧验收记录仅描述旧版本，不作为当前二进制可用性的依据。
