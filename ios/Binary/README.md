# iOS 二进制 CocoaPods 分发

## 当前状态

迁移配置已建立，尚未执行归档、pod lint 或发布。本目录不是已经发布的二进制。
Maaku 适配器和专属测试已移除；SPM 与 XCFramework 都编译同一份
`Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift`，使用 swift-markdown。

## 打包范围

仅编译 `ios/Sources/THKMDView`，静态链接 swift-markdown / swift-cmark 到动态
THKMDView.framework。解析器通过 implementation-only import 隔离，调用方不需要安装
Markdown 或 Maaku 模块。框架内包含 Mermaid HTML/JS 资源。

不包含 Example、Fixtures、mock、主题设置界面、本地偏好保存或 Tests。
源码使用方仍走 SPM；不要在同一个 App 中同时安装 THKMDView 的 SPM 和 pod 版本。

## 本地构建（维护者执行）

需要 Xcode 26+ / Swift 6.2+、XcodeGen、CocoaPods。选择合适的 Xcode 工具链后，在仓库根目录执行：

```sh
bash ios/scripts/build-xcframework.sh
```

脚本将：

1. 检查二进制项目的解析器 revision 与 `ios/Package.resolved` 一致。
2. 生成临时 Xcode 工程，分别归档真机 arm64 与模拟器 arm64/x86_64。
3. 检查框架没有外部 Markdown/cmark 动态依赖、公开接口没有泄露解析器模块、Mermaid 资源齐全。
4. 创建 XCFramework，携带 SDK 和第三方许可证。
5. 在本地产物目录执行 CocoaPods 集成 lint（不启动示例 App）。
6. 生成 `ios/Binary/build-*/THKMDView-<版本>.zip`、SHA256SUMS 和 podspec。

产物保留在独立目录，不覆盖旧包。请保留构建日志及实际 Xcode 版本。
Swift 模块稳定性不保证新工具链产物可被任意旧 Xcode 导入，发布前需验证消费端最低工具链。

## 本地 pod 验证

脚本成功后可在宿主 Podfile 中指向产物目录：

```ruby
pod 'THKMDView', :path => '/绝对路径/ios/Binary/build-XXXXXX/release'
```

该目录必须同时存在 podspec 与 XCFramework。原先指向 Git 源码的 pod 接入方式不再构建 SDK。
共享 P0/P1/P2 数据仍供源码示例和测试使用；二进制宿主需要另外接入验收界面，不能将源码测试通过
等同于二进制集成或 UI 验收通过。

## 发布（需维护者明确执行）

当前工作流只上传 Actions 构建附件，不创建 Release、不 push tag、不推送 CocoaPods trunk。
首个二进制版本发布前，维护者应选择未占用的版本号并更新根目录 podspec，完成构建和消费端验证。
将生成的 ZIP 上传到对应 GitHub Release，地址必须与 podspec 的 `s.source` 一致。
确认远端 ZIP 可下载后，才分发该版本 podspec 或提交到自己的 Specs 仓库。

```ruby
# 发布相应资产后才可使用；这里不是已可用版本的承诺。
pod 'THKMDView', :podspec => 'https://raw.githubusercontent.com/vizoss/THK-Markdown/v<版本>/THKMDView.podspec'
```

共享数据里的 `ios-binary` 表示待验收的二进制接入目标，不表示已经验收。
历史文档中 Maaku、旧 pod lint 的记录仅描述旧版本，不能用于证明当前二进制可用。
