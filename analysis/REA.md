# JDX 0.1 的 REA 分析记录

| 项目 | 已核对的值 |
| --- | --- |
| 应用包标识 | `com.360buy.jdmobile` |
| 应用版本 / 构建号 | `171204` / `16.1.83` |
| IPA SHA-256 | `761c01a4944b440d22a8c3567ab6e39aecbe9c116147749763c1c711e4a6ec1a` |
| 主程序 | `Payload/JD4iPhone.app/JD4iPhone` |
| 主程序 SHA-256 | `21804273ff5e6be667705a840aca63d781c8ab2d1c1a8567612bd76caee6fd3c` |
| 主程序架构 / 最低系统 | iOS arm64 / 15.0 |

分析使用 REA 6.9.0（npm 包 `rea-agents`，MIT 许可证）、Rizin 0.9.1 和 LLVM。REA 清点 IPA 并生成 Apple 应用包图，随后通过 Rizin 提供程序获取指定地址的指令。LLVM 用于核对 Mach-O 元数据、Objective-C 方法签名及消息分发。公开开屏和首页去广告规则用于对照广告位用途。 [REA](https://github.com/morluto/rea) · [REA 许可证](https://github.com/morluto/rea/blob/main/LICENSE) · [开屏规则](https://github.com/blackmatrix7/ios_rule_script/blob/master/script/startup/startup.js) · [首页规则](https://github.com/zbsdsb/loon-adblock-plugins/blob/main/JD_remove_ads_v2.js)

## 广告和推荐入口

下表地址为此构建的 Mach-O 未滑动虚拟地址。插件在运行时按类名、选择器和类型编码定位方法。

| 范围 | 宿主方法 | 处理依据 |
| --- | --- | --- |
| 开屏 | `-[LaunchAnimationManager canShowLaunchADView]` (`0x100402d4c`) | 冷启动 `0x1004025c8` 调用该判断，返回否后由 `0x100402618` 继续到 `startMain`。另一个展示回调在 `0x103e7f934` 调用该判断，返回否后在创建广告视图前结束。 |
| 首页顶部推广 | `-[JDMainPageFloatPhotoCeilingModel canShowCeilingPhoto]` (`0x104116f9c`) | `setFloatTopViewData:` 先移除旧素材，再在 `0x104185ca0` 判断是否展示 `photoCeiling`。 |
| 首页悬浮卡 | `-[JDMainPageViewController shouldDisplayFloat:]` (`0x104185650`)、`shouldDisplayFloat916:` (`0x1041869b0`)、`shouldShowTwoScreenFloatViewForModel:` (`0x104196494`) | 三种布局各自具有广告不展示时的清理分支。 |
| 首页底部横幅 | `-[JDMainPageBottomXViewBoxModel mp_canUse]` (`0x1040f63ec`) | 广告曝光路径检查 `extension_id`。候选列表会跳过被过滤的横幅并继续遍历。插件保留登录奖励、定位奖励和功能引导。 |
| 搜索付费商品 | `-[FinalSearchListViewController p_createVMWithProductModelArray:]` (`0x10640240c`) | 宿主在 `0x1064498bc` 读取 `adStatus` 并将字符串 `1` 视为广告。插件在原生建模后按对象身份移除列表及网格中的成对项，保留普通商品顺序和源序号。 |
| 搜索店铺广告 | `-[FSSearchModel topInfoType]` (`0x106599708`)、`beltAdShop` (`0x106599940`)、`beltAdShopTn` (`0x106599954`) | 顶部仅处理 `adShop` 和 `adSlideShop`，列表店铺广告条使用独立模型。 |
| 搜索尾部推荐 | `-[FSSearchModel recommendShow]` (`0x106599848`) | 宿主将字符串 `0` 判为关闭推荐分页。 |
| 首页推荐 | `-[JDURMulTabBridgeManager getRecommendViewHeight:]` (`0x100342c2c`)、`initBottomCollectionView` (`0x1003437e0`) | 折叠推荐行并隐藏推荐容器，保留宿主分区索引。推荐标签头能否折叠取决于页面样式。 |
| 「我的」页推荐 | `-[MyJdRecommendFloor15250 myjd_numberOfItems]` (`0x10498d058`) | 使用宿主的空推荐楼层路径。 |
| 原生商品详情页推荐 | `-[PDRecommendListFloor render]` (`0x105bf8ed8`) | 运行原始渲染再隐藏本楼层。已追踪的商品详情主布局路径会折叠隐藏项。 |

订单页主动点开的推荐、搜索卡内混合优惠券的推荐、底栏 DyLand 以及 WebView 页面未纳入本版覆盖。上述结论来自静态分析。实际加载、设置手势、广告下发时的展示和搜索分页仍待 iPhone 实测。

## 复核步骤

准备同一 SHA-256 的 IPA，并使用 REA 6.9.0 与可执行的 Rizin。以下 PowerShell 命令在独立的本地分析目录运行，`input.ipa` 代表待复核文件。REA 版本和运行时要求见上游文档。 [REA Apple 应用分析文档](https://github.com/morluto/rea/blob/main/docs/guides/apple/apple-application-analysis.md)

```powershell
Get-FileHash -Algorithm SHA256 ./input.ipa
rea --version
rea inspect-artifact ./input.ipa --detail summary --evidence_output ./ipa.evidence.json --format json > ./ipa.summary.json

$bundle = Get-Content ./ipa.evidence.json -Raw | ConvertFrom-Json
$inventory = $bundle.records | Where-Object operation -eq 'inventory_artifact' | Select-Object -First 1
@{ inventory_evidence = @(@{ kind = 'retained-evidence'; evidence_id = $inventory.evidence_id }) } |
    ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 ./graph-input.json
rea project-apple-application-graph ./graph-input.json --evidence-bundle ./ipa.evidence.json --format json > ./ipa.graph.json
```

从 IPA ZIP 中提取 `Payload/JD4iPhone.app/JD4iPhone` 到当前分析目录。下例从 `PATH` 读取 Rizin 的实际路径。

```powershell
Get-FileHash -Algorithm SHA256 ./JD4iPhone
$env:REA_RIZIN_COMMAND = (Get-Command rizin -CommandType Application).Source
rea execute-rizin-command ./JD4iPhone 'iIj' --format json > ./native-image.json
rea execute-rizin-command ./JD4iPhone 'pd 40 @ 0x1004025ac' --format json > ./cold-start.json
rea execute-rizin-command ./JD4iPhone 'pd 44 @ 0x104185c78' --format json > ./home-promotion.json
rea execute-rizin-command ./JD4iPhone 'pd 30 @ 0x1064498a4' --format json > ./search-ad-status.json
llvm-objdump --macho --private-headers ./JD4iPhone
llvm-objdump --macho --objc-meta-data ./JD4iPhone > ./objc-metadata.txt
```

其余查询与原始 REA 记录编号见 [证据索引](rea-evidence.json)。记录编号来自原分析环境。复核时以文件 SHA-256、IPA 内部路径、方法签名和分支行为为准。
