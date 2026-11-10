# 底部道具区升级（五款道具 / 动效 / 音效 / 统计）

2026-11-10。承接 `docs/ui-upgrade-plan.md` 里两个悬而未决的问题——「机器选择器去留」与「纸篓点击热区」——本次给出结论：**选择器不再单独占一条 UI，改为底部道具本身轻点循环切换，并在设置页提供直选**；点击热区固定为道具本体 132 × 100pt。

## 1. 五款道具

`MachineKind.allCases` 的声明顺序就是点击切换顺序，也是设置页与统计页的展示顺序。

| 顺序 | 道具 | rawValue | 素材（`Assets.xcassets/Devices`） | 识别色 | 落入动效 | 音效 | 销毁时长 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 废纸篓 | `bin_waste` | `icon_bin_waste` | 薄荷绿 | 左右衰减摆动 −9° → +7° → −4° → 0 | `device_bin.wav`（纸团摩擦 + 桶底闷响） | 1.3s |
| 2 | 碎纸机 | `shredder` | `icon_paper_cutter` | 珊瑚粉 | 纵向压扁 10% + 轻微抖动 + 刀口白光 | `device_shredder.wav`（马达起停 + 摩擦 + 切断声） | 1.4s |
| 3 | 壁炉 | `fireplace` | `icon_fireplace` | 火焰橙 | 火光暴涨（`plusLighter` 径向辉光）+ 常驻火星 | `device_fireplace.wav`（气流上涌 + 木柴爆裂 + 低频余温） | 1.8s |
| 4 | 邮筒 | `mailbox` | `icon_mailbox` | 深绿 `#507A60`（取自新素材筒身实测中位色，与废纸篓薄荷绿靠明度区分） | 投递回弹 + 投口闪光 | `device_mailbox.wav`（金属投口两响 + 信件滑入 + 小铃） | 1.5s |
| 5 | 任意门 | `any_door` | `icon_door` | 天蓝 | 沿左缘 3D 开门 −38° + 蓝色辉光 | `device_door.wav`（开门低频 + 上行琶音 + 空气感） | 1.7s |

`fireplace` / `shredder` 沿用旧 rawValue，保证已落库的选择、`DestroyOutcome` 与 `UI_TEST_MACHINE=shredder` 入口不失效；新加的三款用素材名派生 rawValue。默认道具由旧 `.fireplace` 改为 **`.wasteBasket`**（与"废纸篓"这一基础形态一致）。

> 本轮开发期间用户把 `icon_mailbox` 从朱红换成了深绿筒身；`Theme.Device.mailbox` 因此按素材实测中位色 `#507A60` 重写（浅色 `#507A60` / 深色 `#83C6A2` / 高对比 `#2C513D` / `#B4E8C8`）。这个色同时驱动指示点、设置页选中态、统计分布条与占比条，五处自动跟随。暗色档刻意提亮，保证深绿在暗底上仍有对比；与废纸篓的薄荷绿靠明度区分。素材本身是用户的改动，本次未触碰。

## 2. 交互与状态

- **切换**：轻点底部道具 → `MachineKind.next` 循环，末位回到首位。切换时播放 `device_switch.wav`、弹跳动效、名称牌（1.4s 自动消失），并往 LCD 推一条「已切换为「碎纸机」」瞬时反馈（2.4s 回落）。
- **状态源**：`DestroyCoordinator.machine` 是运行时的唯一来源，`AppSettings.destroyMachine`（`UserDefaults["settings.destroyMachine"]`）负责持久化。首页 `onAppear` 恢复，`onChange` 同步设置页的直选；首页自己切换时两者已相等，`onChange` 直接跳过，避免弹跳播两次。
- **禁止切换**：结算执行中（`isExecutingTaskEnd`）或销毁流程忙碌（`DestroyPhase.isBusy`）时忽略点击，统计口径与界面不出现分叉。`switchMachine` 改为返回 `Bool`，调用方只在成功时写设置。
- **设置页直选**：设置 →「销毁道具」分组新增 `DevicePickerStrip` 五图标横排，点选即持久化，回到首页自动同步。
- **落入**：照片下滑完成后 `binShakeToken += 1` 触发当前道具的专属动效，同时 `sound.play(device:)` 播放对应音效；统计按 `destroy.machine` 写入。
- **UI 测试**：`UI_TEST_MACHINE` 接受五个 rawValue（`bin_waste` / `shredder` / `fireplace` / `mailbox` / `any_door`），旧的 `shredder` 不变。
- **无障碍**：道具是一个 `.isButton` 元素，标签含当前道具名与本批待删除张数，提示含「轻点切换到下一个销毁道具」及对应动作（投进 / 送进 / 投入 / 寄进）；另提供 `accessibilityAction(named: "切换道具")`。

## 3. 动效规格

三段动效互不抢触发源，全部走 SwiftUI 关键帧 / 时间线，不引入第三方动画库：

| 层 | 触发 | 实现 | 时长 |
| --- | --- | --- | --- |
| 切换 | `switchToken` | `keyframeAnimator` 三组轨迹：`scale` 0.86 → 1.08 → 1、角度 −7° → +4° → 0、上抬 −6 → 0；素材用 `.id(machine)` + 非对称 transition（缩小淡入 / 放大淡出）交叉淡化 | 0.38s |
| 落入 | `shakeToken` | 单一 `Impact` 结构体六个字段（角度 / 横向 / 纵向缩放 / 位移 / 门轴 / 辉光），五款道具只改幅度，轨迹结构共用，避免为每款写一套 KeyframeBuilder 分支 | 0.46s |
| 常驻 | 视图生命周期 | `TimelineView(.animation(minimumInterval: 1/15))` + `Canvas`：壁炉 6 粒火星、碎纸机 4 片纸屑、任意门 5 点微光；邮筒与废纸篓不跑时钟 | 循环 |

- **降低动效**：与系统 `Reduce Motion` 取并集。切换弹跳幅度归零（只保留交叉淡化），常驻 TimelineView `paused: true` 退化为静态一帧，落入动效仍保留最小反馈。
- **布局零变化**：核心 ZStack 仍是 `132 × 100`，外层 `.padding(.horizontal, 16)` / `.padding(.bottom, 4 + bottomInset)` 不变；五点序号指示器、名称牌、辉光、粒子全部走 `overlay`，`DockHeightKey` 量到的高度与旧版一致，台面线 / 纸篓锚点 / 三栏落点不动。
- 底部五点用各自识别色指示当前序号，静息可见；按用户要求整体下移 `10pt`（`.offset(y: 10)` 挂在 overlay 上，不占行高），落在道具底边下方的桌面上。名称牌只在切换后短暂出现，不常驻。

## 4. 音效规格

6 个新 WAV 位于 `source/appSuperPhotos/SuperPhotos/Resources/Sounds/`，由 `design/sounds/generate_sounds.py` 本地合成（numpy + 标准库 `wave`），**无外部素材、无版权依赖**。

| 文件 | 时长 | 用途 |
| --- | --- | --- |
| `device_switch.wav` | 0.17s | 点击循环切换的 UI 提示，音量 0.45（比业务音效轻一档） |
| `device_bin.wav` | 0.50s | 废纸篓落入 |
| `device_shredder.wav` | 0.62s | 碎纸机落入 |
| `device_fireplace.wav` | 0.78s | 壁炉落入 |
| `device_mailbox.wav` | 0.56s | 邮筒落入 |
| `device_door.wav` | 0.74s | 任意门落入 |

统一格式：PCM 16-bit / 44.1kHz / 单声道，峰值归一化到 0.82，头尾 6ms 淡入淡出避免起播爆音。工程使用 `PBXFileSystemSynchronizedRootGroup`，新 WAV 自动进 `Copy Bundle Resources`，**无需改 `project.pbxproj`**（已验证 10 个 WAV 全部在产物里）。

`SoundService` 变更：

- 新增 `Event.deviceSwitch` 与 `Event.deviceDrop(MachineKind)`，后者从 `MachineKind.soundName` 取资源名；语义化入口 `play(device:)`。
- `play(_:)` 受 `AppSettings.soundEnabled` 控制；`.ambient` 会话跟随静音键、不打断其他 App 音频。
- 资源缺失时**不再 `assertionFailure`**：道具音效先退回 `paper_crunch.wav`，再退回静音。这样历史安装包或素材漏拷都不会让整理流程崩掉。
- 旧 `Event.paperCrunch` 保留作兜底与兼容，首页已不再直接调用。

## 5. 统计升级

### 数据模型

`DayStat` 保留 `fireplace` / `shredder` 两列不动（历史数据无需迁移），新增 `wasteBasket` / `mailbox` / `anyDoor` 三列，均带默认值 `0`，由 SwiftData 轻量迁移补齐。`StatSummary` 同步扩字段，新增 `count(for:)` 与 `topMachine`；日行与汇总都通过 `DayStat.increment(_:by:)` / `count(for:)` 读写，不再在调用点写 switch。

> 兼容性提醒：这是**纯增量加列**。真机从旧版本升级首次启动时会做一次轻量迁移；`AppModelContainer` 仍保留「迁移失败退回内存容器」的既有兜底，但那条路径下统计不落盘。真机验收时请确认旧数据仍在。

### 口径与展示

- `recordDestroy(count:sample:machine:)` 按当时选中的道具分别计数，五款件数之和 = 本周期 `destroyed`（自检样本已按此配平）。
- **统计页**：「道具使用分布」卡片改为五款道具的素材图标 + 名称 + 占比条 + 件数/百分比，顶部显示最常用道具；所有档位可见。
- **设置页**：「统计」分组的入口行内直接展示今日销毁总数、五段彩色分布条与各道具件数摘要；新增「销毁道具」分组做直选。
- **VIP 边界调整**：原「方式偏好」属 VIP，本次把「五款道具的件数与占比」下放为免费（它是"用了哪款道具"的客观记录，不是分析型报告）；VIP 仍保留「本月周期」，趋势图 / 年度报告依旧归二期。`VIPView` 与 `Feature` 文案已同步。
- DEBUG 自检样本 `seedSelfCheckSamples()` 已覆盖五款道具，PASS 判据（今日 5 件 / 50MB / 1 未知，累计 9 件 / 60MB / 3 未知）不变。

## 6. 改动文件

| 类型 | 文件 |
| --- | --- |
| 新增 | `Core/DesignSystem/DeviceTheme.swift`、`Features/Statistics/DeviceDistributionView.swift`、`Resources/Sounds/device_*.wav` ×6、`design/sounds/generate_sounds.py`、`docs/device-dock-upgrade.md` |
| 重写 | `Core/Models/MachineKind.swift`、`Features/Destroy/DestroyDock.swift`、`Core/Sound/SoundService.swift` |
| 修改 | `Core/Settings/AppSettings.swift`、`Features/Destroy/DestroyCoordinator.swift`、`Features/Home/HomeView.swift`、`Core/Statistics/StatModels.swift`、`Core/Statistics/StatisticsService.swift`、`Features/Statistics/StatisticsView.swift`、`Features/Settings/SettingsView.swift`、`Features/Settings/VIPView.swift`、`Core/Entitlements/Feature.swift` |

## 7. 真机验收清单

1. 连续轻点底部道具 5 次，顺序为废纸篓 → 碎纸机 → 壁炉 → 邮筒 → 任意门 → 废纸篓；每次有弹跳、素材交叉淡化、名称牌、切换音与 LCD 反馈。
2. 五款道具各具不同的「照片落入」动效与音效；音效开关关闭后全静音，系统静音键生效。
3. 开启系统「降低动效」：切换只剩淡化、常驻粒子静止，落入仍有最小反馈，不出现大幅旋转。
4. 杀进程重启后道具保持；设置页直选后返回首页即时同步；结算执行中点按不切换。
5. 底部五点指示器、名称牌不撑高 `DockHeightKey`；台面线、纸篓下移量、三栏落点与升级前一致。
6. 用 DEBUG 自检样本验证五款道具件数之和 = 已销毁件数；统计页与设置页读数一致；旧版本升级后历史统计仍在。
7. VoiceOver：道具可读出当前名称、待删除张数与「切换道具」动作。

## 8. 已知限制

- 五款道具只是**表现层**（动效 / 音效 / 统计口径），删除仍走同一条 `DeleteService` 通道，不改变照片删除逻辑。
- `Machines.swift` 里的 `FireplaceMouth` / `ShredderMouth` 是早期「内凹机器口」预览，当前首页不再使用，保留仅作设计参考。
- 音效是合成音色，不是实录；如需拟真录音，替换同名 WAV 即可，`SoundService` 无需改动。
