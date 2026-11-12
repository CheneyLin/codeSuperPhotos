# 2026-11-12（续）

## SuperPhotos 多语言支持（英文 / 简中 / 繁中）— 已完成并提交

commit `4f9cd96` "feat: 增加多语言支持（英文 / 简中 / 繁中）"

### 方案
沿用 appFMRed 项目的「中文原文即 key」模式：
- `SuperPhotos/Core/Support/Localization.swift`：`String.localized`（`NSLocalizedString(self, comment: "")`）
  与 `String.localized(_ args: Any...)`（按 `%@` 顺序替换，不用 `String(format:)`，避免 `%@` + Int 崩溃）
- `.lproj` 直接放在同步根组 `SuperPhotos/` 下（与 appFMRed 一致），**不是** `SuperPhotos/Localization/`
- 工程用 `PBXFileSystemSynchronizedRootGroup`，新增 `.swift` / `.lproj` 无需手动注册 pbxproj

### 产物
- `SuperPhotos/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings` —— 各 502 条
- `SuperPhotos/{en,zh-Hans,zh-Hant}.lproj/InfoPlist.strings` —— 4 条（含两个相册权限说明）
- `Info.plist` 加 `CFBundleLocalizations = [en, zh-Hans, zh-Hant]`
- pbxproj `knownRegions` 加 `zh-Hans` / `zh-Hant`；`developmentRegion` 保持 `en`

### 翻译产出方法（可复用）
- 英文：手写字典（`/tmp/tr_en*.py`）
- 繁中：`opencc-python-reimplemented` 的 `s2twp` + 人工术语校订表
  （舞臺→舞台、訪問→取用、許可權→權限、賬戶→帳戶、反饋→回饋、恢復→取回、鏈接→連結、後設資料→中繼資料）

### 关键技术坑
1. **枚举 rawValue 不能本地化** —— Swift 要求字面量，且承担持久化/身份标识职责
2. **含插值的字符串不能直接 `.localized`** —— 运行时 key 会变成动态串，查找必失败；必须改写成 `%@` 占位符形式
3. **文案前缀判断会失效** —— `errorText?.hasPrefix("已锁定")` 在英文/繁中下永不匹配；改为 `isLockCountdownError` 状态位（`VaultLockView`）
4. **日期格式化硬编码 `zh_Hans_CN`** —— `PhotoItem` / `VaultRecord` / `SnoozeListView` / `VaultSyncEngine` 已改为 `locale = .current` + `setLocalizedDateFormatFromTemplate`
5. **多行字符串字面量** —— 转换器把 `\n` 写成真实换行导致 `Unterminated string literal`；`SettingsTips.swift` / `VaultResetView.swift` 已修回 `\n` 转义
6. **转换器类型名子串误伤** —— `struct VaultPreviewDrawer` 含 "Preview" 被整体跳过（真实界面）；`DesignSystemPreviewView` 同理。已手工补齐这两个文件

### 验证
- Debug + Release `xcodebuild` 均 BUILD SUCCEEDED，error 0
- 产物中 3 个 `.lproj` 各 502 条，`PropertyListSerialization` 解析通过，占位符数量全部匹配
- 语言匹配实测：`zh-Hans-CN→zh-Hans`、`zh-Hant-TW/zh-HK→zh-Hant`、`ja/fr→en` 回退
- 剩余 73 处未本地化中文全部是 `#Preview` 名称 / `log()` 调试输出 / 枚举 rawValue / 崩溃诊断，属正确保留

### 待办
- IMA 知识库根目录仍有一份重复的 `SuperPhoto App Store Document.md`，需用户手动删除（IMA MCP 无删除能力）
- 繁体中文文案建议由母语者再过一遍（当前为 OpenCC + 术语表产出）
