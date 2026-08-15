# 知乎 15

一个参考 `kangyun1994/zhihu-plus-plus-swift` 产品结构、以 iOS 15 SDK 为基线重写的知乎客户端。

## 当前版本

- 当前版本：0.1.11（下一次标签构建为 0.1.12）
- 最低系统：iOS 15.0
- UI：SwiftUI 主导，UIKit 承载复杂内容页面，不依赖第三方 UI 库

## 已有功能

- 首页信息流：推荐、关注、热榜、知乎日报，支持下拉刷新和本地演示数据降级
- 内容浏览：搜索、问题/回答/文章详情、评论列表、发表评论、收藏、浏览历史、消息通知；详情采用 push 子页面
- 问题回答：问题详情可进入全部回答列表，支持下拉刷新、分页加载和点击回答进入独立详情页
- 知乎接口：真实 Feed、搜索、正文、评论、通知、收藏/历史、关注、赞同和创作请求；包含 `x-zse-96` 请求签名
- 登录体系：知乎网页登录、二维码扫码登录、Cookie 持久化、Keychain 安全存储、风控验证页面
- 多账号：账号列表、切换、添加和删除账号，账号会独立保存在 Keychain Vault
- 图片能力：URLSession 图片下载，内存 `NSCache` + 磁盘缓存，列表复用时避免旧图片串位
- 视觉资源：沿用参考项目 AppIcon 的 iPhone/iPad 全尺寸资源；用户头像和作者头像使用知乎接口返回的真实头像并走同一套图片缓存
- 创作能力：富文本回答/想法编辑器、粗体/斜体/下划线、图片插入、草稿保存、发布回答和想法
- 视频能力：获取知乎视频播放地址并使用 AVKit 播放
- 隐私保护：Face ID、Touch ID 或设备密码 App 锁
- iPad 适配：支持 iPad 横竖屏、系统 Split View/Slide Over 窗口缩放，窄分屏自动关闭大标题，列表和编辑页面使用自适应约束；详情操作栏固定在安全区底部
- UI 架构：SwiftUI 主导航与信息流，UIKit 承载登录二维码、风控验证、正文 Web/Markdown、视频、富文本编辑器和 App 锁等复杂场景
- 兼容性：SwiftUI/UIKit 混合、Swift 5、iOS 15 部署目标，兼容 iPhone/iPad 全尺寸、横竖屏和 Split View，不使用 iOS 26 专属 API

## 运行

在 macOS + Xcode 中打开 `Zhihu15.xcodeproj`，选择 iOS 15 或更高版本模拟器运行。当前包标识为 `com.pixia.zhihu15.client`，工程文件保持 Xcode 13 格式，真机运行前在 Signing & Capabilities 中设置自己的 Team 和签名配置。

如果安装了 XcodeGen，也可以先执行 `xcodegen generate`，工程会从 `project.yml` 重新生成；默认打包脚本使用仓库中已提交的工程文件，以便兼容 Xcode 13.4.1。需要重新生成时设置 `REGENERATE_XCODE_PROJECT=1`。

## GitHub Actions

`.github/workflows/ios-unsigned-ipa.yml` 使用 GitHub 托管的 `macos-14` 编译未签名 IPA，构建完成后会上传为 Actions Artifact。可以在 Actions 页面手动运行，也可以推送版本标签：

```bash
git tag v1.0.0
git push origin v1.0.0
```

当前 GitHub 托管镜像不再提供 `macos-13` 和 Xcode 13.4.1，因此 CI 使用现行镜像中的 Xcode 15.4；应用仍固定 `IPHONEOS_DEPLOYMENT_TARGET=15.0`，可运行在 iOS 15 及以上设备。若必须让编译器使用精确的 iOS 15.x SDK，需要自托管 macOS 安装 Xcode 13.4.1，或在 Actions 中使用 Apple Developer 凭据先安装该 Xcode，再将 `DEVELOPER_DIR` 指向它。

## 性能取舍

列表使用原生 cell 复用和自动高度估算，网络请求不放在主线程，图片经过内存/磁盘缓存后再回主线程更新；登录页和正文使用系统 WebKit/网络能力，不在信息流滚动路径中加载 Web 内容或执行复杂动画。

## 未签名 IPA

打包方式参考 `pixia-bills`：

```bash
./scripts/build_unsigned_ipa.sh 1.0.0
```

产物为 `build/zhihu15-1.0.0.ipa`。如果必须使用 iPhoneOS 15.x SDK，先切换到包含该 SDK 的 Xcode：

```bash
DEVELOPER_DIR=/Applications/Xcode_13.4.1.app REQUIRE_IOS15_SDK=1 \
  ./scripts/build_unsigned_ipa.sh 1.0.0
```

注意：SDK 是 Xcode 的构建工具版本，最低运行系统由 `IPHONEOS_DEPLOYMENT_TARGET=15.0` 决定。当前 Linux 环境没有 Xcode，不能直接生成 IPA；脚本需在 macOS 执行。未签名 IPA 不能直接安装到普通 iPhone，真机发布仍需要自己的签名证书和 provisioning profile。
