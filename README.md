# 知乎 15

一个参考 `kangyun1994/zhihu-plus-plus-swift` 产品结构、使用 iOS 15 原生 UIKit 重写的知乎客户端。

## 当前版本

- 最低系统：iOS 15.0
- UI：UIKit + `UITableView`，不依赖 SwiftUI、第三方库
- 页面：首页（推荐 / 关注 / 热榜 / 日报）、收藏、搜索、详情、消息、账号
- 数据：知乎真实接口，接口失败时保留本地演示数据作为降级内容
- 登录：`WKWebView` 知乎网页登录，Cookie 使用 Keychain 保存
- 图片：内存 `NSCache` + 磁盘 Cache + URLSession，列表 cell 复用时取消旧图片绑定

## 运行

在 macOS + Xcode 中打开 `Zhihu15.xcodeproj`，选择 iOS 15 或更高版本模拟器运行。工程文件保持 Xcode 13 格式，真机运行前在 Signing & Capabilities 中设置自己的 Team 和 Bundle Identifier。

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
