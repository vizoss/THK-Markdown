# 科技周刊阅读示例

两端例子首页的「科技周刊 · 50 篇」进入文章列表，点击后用 THKMDView 展示完整正文。

- 来源：[阮一峰的科技爱好者周刊](https://github.com/ruanyf/weekly)。
- `weekly.json` 固定收录第 364～413 期，按期号降序；标题及路径来自该仓库目录。
- Android assets 和 iOS Example Resources 共用此目录文件。仅例子应用打包目录，
  不放入 Android 库、Swift Package 库资源或 XCFramework。
- 正文按需从 `raw.githubusercontent.com` 在线读取，图片由现有图片加载器处理；
  未内置或离线缓存文章/图片。无网络时显示重试入口。
- 详情页保留作者署名和 GitHub 原文入口，点击正文网页链接交给系统打开。
  从主题页返回会应用已保存主题，退出详情取消正文请求。

验证：50 条目录编号唯一，50 篇正文均成功读取，所选文章的 Markdown 图片地址均为绝对 URL。
Android 示例编译、iOS 示例源码类型检查通过；未启动应用或执行视觉验收。
