# JDX

JDX 是京东 iOS 去广告插件。首版 `0.1` 适配包标识 `com.360buy.jdmobile`、版本 `171204`、构建号 `16.1.83`，最低系统为 iOS 15.0。插件核对这三个包信息后才启用。

## 安装和开关

- Rootless 越狱环境使用兼容的 tweak 加载器（例如 ElleKit）和支持本地包的管理器安装 `.deb`。装过旧版 JDAdBlock 的设备先卸载旧包，再安装 JDX。
- 已有 IPA 注入工具的环境可使用 arm64 的 `JDX.dylib`。从旧版切换时先移除原有的 `JDAdBlock.dylib`，再添加 JDX。
- 在京东底部进入「我的」，在页面空白处双指长按约一秒打开「JDX 去广告」。总开关默认开启，修改会自动保存。结束京东进程并重新打开后生效。

[下载 JDX 0.1](https://github.com/SOLHK/JDX/releases/tag/v0.1)

## 覆盖范围

- 开屏广告，包括静态分析确认的冷启动完成回调和一条后台恢复路径。
- 搜索付费商品卡、顶部付费店铺、列表内店铺广告条。过滤成对的列表与网格模型，保留正常结果的顺序和原始序号。
- 首页底部推荐流、搜索尾部推荐、「我的」页推荐楼层、原生商品详情页底部推荐。首页推荐栏标题是否折叠取决于页面样式。
- 首页顶部动图推广、普通及双屏等样式的悬浮卡、带广告标记的底部横幅。底部横幅保留登录奖励、定位奖励和功能引导。

## 分析与验证

[REA 分析记录](analysis/REA.md) 包含输入身份、定位过程及关键证据。已通过 arm64 编译、静态分析、包结构与签名页哈希校验，以及使用替身 Objective-C 运行时的六个指令级模拟场景。真机注入、开关手势、页面展示和业务流程待验证。

## 本地构建

Windows 上使用 Python、LLVM 和 iPhoneOS 16.5 SDK。将命令中的路径改为本机安装目录。

```powershell
py build.py --build-dir build --output dist --llvm-dir 'C:/Program Files/LLVM/bin' --sdk 'D:/SDKs/iPhoneOS16.5.sdk'
```
