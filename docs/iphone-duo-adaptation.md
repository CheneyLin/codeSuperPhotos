# iPhone Duo 适配准备说明

> 2026-11-10 · 阶段：**准备（基建）**，不是「完成适配」
> 一期布局范围仍按 [decision-log #138](./decision-log.md) 收敛在 iPhone 全屏机；
> 本次只引入状态识别包与工程前置配置，**不改任何现有页面布局、不新增 Duo 专属分支**。

---

## 1. 做了什么 / 没做什么

| | 内容 |
| --- | --- |
| ✅ 已做 | 移植铰链状态识别包到 `Core/Duo/`；根节点包 `DuoGate`；补 `UIApplicationResizable`；DEBUG 诊断 HUD 与状态模拟；本说明与决策记录 |
| ✅ 已核对 | 部署目标仍 17.6；铰链 API 全部 `#available(iOS 27.1, *)` 隔离；无 `UIRequiresFullScreen` / `UILaunchStoryboardName`；iPhone 横屏方向已放行；无 AppDelegate 方向覆写 |
| ❌ 未做 | 内外屏 / 书本姿态的布局分支、铰链带避让落进业务页、折叠展开时状态保活回归、Duo 真机验收 |
| ❌ 未改 | `HomeView` 三栏公式、LCD、纸篓、舞台卡片尺寸——一期继续按宽度自适应，`duoInfo` 目前没有任何业务读取方 |

**引入理由**：产品方案 13 节原写「不依赖折叠态私有 API」。本次引入的是 iOS 27.1 **公开**铰链 API，
与「私有 API」不是一回事；但为避免范围膨胀，仍约定「包只注入、页面不消费」，等进入 Duo 布局阶段再逐页接入。

---

## 2. 移植来源

| 来源 | 用途 |
| --- | --- |
| `codeSuperLiveWallpaper/.../Model/DuoDevice.swift`（2026/11/6） | 主参考：状态枚举、`duoInfo` 环境键、`DuoGate`、`onHingeChange` 分派、内屏横竖屏 |
| `codeSuperLiveWallpaper/.../Utils/UIUtil.swift` | 原项目的 `DeviceDuoType` / `DuoOrientation` 全局量（**未移植**，见下） |
| `codeSuperClock/Document/iPhone Duo适配技术文档.md` | 工程配置、姿态矩阵、踩坑记录 |
| `codeFMRED_iOS/.../Models/DuoDevice.swift` | 早期精简版，用于对照确认 API 用法 |

与参考实现的三处有意差异：

1. **去掉全局可变变量**。原实现把 `DeviceDuoType` / `DeviceDuoOrientation` 写在 `UIUtil.swift`，
   由铰链回调直接写全局。本项目 Swift 6 并发设置（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`）
   且已有 `@Observable` + Environment 体系，全局可变量既不安全也破坏模块边界；改为全部走 Environment。
2. **状态单点推导**。`DuoDeviceInfo.make(hingeState:layout:)` 从「铰链状态 + 布局快照」两个原始量
   一次算出全部派生字段，替代原实现 4 条 `onChange` 链互相覆盖的写法。
3. **修掉 division 滞留**（下节踩坑 4.3）。铰链状态变化时用 `hingeToken` 强制重读遮挡带，
   不再只依赖 `geo.size` 变化；书本姿态以铰链状态为权威值。

---

## 3. 适配包结构

```
SuperPhotos/Core/Duo/
├─ DuoDevice.swift       状态模型 / duoInfo 环境键 / DuoGate / 27.1 铰链监听
├─ DuoLayout.swift       duoLayout 环境键 / 断点常量 / 铰链带切分与命中校验纯函数
└─ DuoDiagnostics.swift  DEBUG 只读 HUD + 状态模拟；Release 编译为 EmptyView
```

### 3.1 状态模型（iOS 27.1+ 公开 API）

| API | 说明 |
| --- | --- |
| `View.onHingeChange { old, new in }` | 角度高频回调，需自行防抖 |
| `DeviceHinge.status` | **结构体静态常量**（非枚举），必须 `== .closed / .partiallyOpen / .fullyOpen` 分派 |
| `GeometryProxy.reservedRegions(kind: .division)` | 铰链遮挡带；`ReservedRegion` 有 `isActive` 与 `frame` |

SDK 没有 `\.isLaptopPose` 环境变量、没有 `context.display.isInnerDisplay`。

```swift
enum DuoHingeState { case notDuo, closed, partiallyOpen, fullyOpen }

struct DuoDeviceInfo {
    var hingeState, isLaptopPose, isInnerScreen, hingeActive
    var innerIsLandscape, innerIsPortrait
    var isOuterScreen: Bool { hingeState == .closed }
    var isDuo: Bool        { hingeState != .notDuo }
}
```

| 姿态 | 判定 |
| --- | --- |
| 外屏 | `hingeState == .closed` |
| 内屏竖屏 | 内屏 && `fullyOpen` && w < h |
| 内屏横屏 | 内屏 && `fullyOpen` && w > h |
| 书本模式 | `partiallyOpen`（横竖由容器宽高决定） |

> 外屏**不靠**屏幕尺寸或近方形启发式猜（那是不准的路径），以铰链 `.closed` 为权威；
> 非 Duo / iOS < 27.1 时 `duoInfo` 恒为 `.notDuo`，页面走现有普通布局。

### 3.2 布局准备层

`DuoLayoutInfo` 由根节点的 background `GeometryReader` 采集，不影响任何布局：

- `containerSize`、`hingeBand: CGRect?`（仅 27.1+ 且 `isActive` 的区域）
- `isRegular`（≥ 600pt，与 product-plan 4.5 / decision-log #7 同一断点）
- `bandOrientation`：竖向带 → 左右分栏，横向带 → 上下分区

`DuoLayoutMetrics` 提供未来要用的纯函数，**当前零调用方**：

| 函数 | 用途 |
| --- | --- |
| `splitRects(in:band:clearance:)` | 按铰链带切两块可用区域；无带时左右 50/50 |
| `intersectsHinge(_:band:clearance:)` | 校验可点区域是否压到铰链缝 |
| `simulatedBand(_:in:)` | DEBUG 模拟遮挡带 |
| `regularBreakpoint = 600` / `hingeClearance = 8` / `stageMaxWidth = 640` | 与产品方案 4.5「中间 8pt 视觉分隔」「舞台最大 640」对齐 |

---

## 4. 工程配置（已改）

| 项 | 值 | 原因 |
| --- | --- | --- |
| `Info.plist`（`source/appSuperPhotos/Info.plist`）+ `INFOPLIST_FILE` | 仅含 `UIApplicationResizable = true`；Debug + Release 都设 `INFOPLIST_FILE = Info.plist` | **必需**。否则 Duo 内屏只给中间 50% 兼容窗口（superclock 实测）。工程用 `GENERATE_INFOPLIST_FILE = YES`，Xcode 会把这份补充 plist 与自动生成的内容合并，其余键仍由构建设置产生 |
| `UIRequiresFullScreen` | 不存在 | 设为 YES 会触发内屏窗口化 |
| `UILaunchStoryboardName` | 不存在 | 指向不存在的 storyboard 同样触发窗口化 |
| `UIApplicationSceneManifest_Generation` | `YES`（原有，未改） | 自动生成的清单实测为 `UIApplicationSupportsMultipleScenes = true` + 空 `UISceneConfigurations`，与参考项目的单场景配置不同，见下方待确认项 |
| iPhone 方向 | Portrait + LandscapeLeft/Right（原有） | 内屏横屏 / 书本横屏需要 |
| AppDelegate 方向覆写 | 无 | 项目是纯 SwiftUI App，没有 `supportedInterfaceOrientationsFor` 把 iPhone 锁回 `.portrait` 的坑 |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.6`（未改） | 铰链代码全部 `#available(iOS 27.1, *)` 隔离，低版本不进入 Duo 分支 |

工程使用 `PBXFileSystemSynchronizedRootGroup`，新增的 `Core/Duo/*.swift` 会自动进 target，
**无需手工往 `project.pbxproj` 添加文件引用**；本次只给两个配置各加了 1 行 `INFOPLIST_FILE`。

> 踩坑：`INFOPLIST_KEY_UIApplicationResizable = YES` **无效**。Xcode 自动生成 Info.plist 时
> 只识别内置的 `INFOPLIST_KEY_*` 白名单，任意自定义键会被静默忽略（实测编译通过但产物里没有该键）。
> 正确做法是保留 `GENERATE_INFOPLIST_FILE = YES` 的同时指定 `INFOPLIST_FILE` 指向只含补充键的 plist，
> 由 Xcode 合并。补充 plist 放在 `source/appSuperPhotos/` 下（同步组之外），避免被当资源复制进 bundle。
> 构建后已用 `plutil` 确认产物里 `UIApplicationResizable = true`（布尔值），
> 且 `MinimumOSVersion = 17.6`、两个 iPhone 横屏方向、相册权限文案都还在。

**待确认（未改）**：参考项目把 `UIApplicationSupportsMultipleScenes` 设为 `false`（单场景），
本工程自动生成的是 `true`。这项是一期就有的行为，改成 false 会影响 iPad 多窗口，
属于产品范围外的行为变更，本次不动；等 Duo 真机验收时若出现多场景 / 窗口化问题再单独决策。

---

## 5. 调试与验证

铰链 API 只在**真机折叠硬件**上有效，模拟器不会报告任何姿态。本项目沿用 `SP_HIT_DEBUG=1`
的环境变量约定，在 Xcode Scheme → Arguments → Environment Variables 设置：

| 变量 | 值 | 效果 |
| --- | --- | --- |
| `SP_DUO_DEBUG` | `1` | 只显示右上角只读 HUD（状态、尺寸、遮挡带 frame） |
| `SP_DUO_STATE` | `closed` / `partiallyOpen` / `fullyOpen` / `notDuo` | 模拟铰链状态，同时自动显示 HUD |
| `SP_DUO_BAND` | `vertical` / `horizontal` | 在容器中央模拟一条 8pt 遮挡带 |

HUD 在 `#if DEBUG` 内编译，`allowsHitTesting(false)` + `accessibilityHidden(true)`，
Release 下 `DuoDiagnosticsHUD` 是 `EmptyView()`，不产生任何视图与开销。

编译检查（不跑模拟器）：

```bash
cd source/appSuperPhotos
xcodebuild -project appSuperPhotos.xcodeproj -scheme appSuperPhotos \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
# 再检查产物 Info.plist
plutil -p <DerivedData>/Build/Products/Debug-iphoneos/appSuperPhotos.app/Info.plist
```

真机验收时确认：`UIApplicationResizable = 1`、无 `UIRequiresFullScreen`、iPhone 方向含两个横屏。

---

## 6. 踩坑记录（沿用参考项目实测）

1. **ArrangementView 不可用**：自定义 `ArrangementStyle` 只是渲染委托，系统判定不适合拆分时
   会直接丢弃 secondary；`split` 在 compact 宽度下自动折叠为单栏。固定双栏要用
   `GeometryReader + HStack` 自己分，别指望系统自动拆分。
2. **内屏只有中间 50% 可用**：根因是 `UIRequiresFullScreen = YES` 或失效的
   `UILaunchStoryboardName`；修法是删除两者 + `UIApplicationResizable = true`。
3. **division 滞留**：`divisionActive` 若只在 `geo.size` 变化时刷新，半开 → 全开会残留 true，
   导致书本姿态卡住。姿态判定以铰链状态为权威，division 只用于遮挡带避让；
   并且铰链状态变化时要主动重读区域（本包用 `hingeToken`）。
4. **外屏识别**：按宽度 < 500pt / 近方形猜外屏不准，必须用铰链 `.closed`。
5. **横屏不生效**：若将来接入 AppDelegate，注意
   `application(_:supportedInterfaceOrientationsFor:)` 返回值优先级高于 Info.plist，
   不要把非 iPad 硬编码成 `.portrait`。
6. **模拟态不能替代真机**：`SP_DUO_STATE` 只注入 Env 值，`reservedRegions` 的真实带位置、
   安全区与内外屏切换时序仍需真机确认。

---

## 7. 后续适配待办（本次不做）

按依赖顺序，进入 Duo 布局阶段时逐项推进，每项都要补 decision-log：

1. 把 `HomeView.taskWorkspace` 的三栏公式在 320–1024pt 做回归，确认折叠 / 展开时
   任务快照、当前照片 id、坞状态、收藏夹选中项与滚轮位置不丢（product-plan 4.5）。
2. 用 `DuoLayoutMetrics.intersectsHinge` 校验顶部整行三段（左按钮区 / LCD / 右按钮区）、
   纸篓不落在铰链缝上；必要时按 `splitRects` 给书本姿态切左右 / 上下两区。
   注意回退 / 提前结束已在顶栏左右按钮区，不再是三栏行顶部的独立浮层。
3. 内屏横屏 / 书本横屏的双栏容器（参考项目矩阵：左右 50/50，无带时平分）。
4. 舞台卡片与销毁坞遵守 `stageMaxWidth = 640` 居中；铰链带两侧留 8pt。
5. 真机全姿态验收：外屏竖 / 外屏横 / 内屏竖 / 内屏横 / 书本横 / 书本竖，
   并验证折叠展开切换不重置到第 1 张。
6. 若真机发现内屏窗口化，回到第 4 节逐项核对 Info.plist 与方向配置，
   并决定是否把 `UIApplicationSupportsMultipleScenes` 收敛为 `false`。

**数据兼容**：本包不写任何持久化字段、不改 `CleaningTaskSnapshot`、不新增 UserDefaults
（DEBUG 变量只在进程环境变量 / 已有 `debug.*` 命名空间读取），进行中的批次与保险箱数据不受影响。
