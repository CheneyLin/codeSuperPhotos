import SwiftUI
import UIKit

/// 右侧收藏夹区：纯上下滚动的相簿选择器，停在中间的一本即当前收藏夹目标，
/// 照片右滑时飞入这本相簿。
///
/// 非循环、有边界：相簿只渲染一遍，滚轮位置钳制在 `[0, count-1]`，滑到首尾即停；
/// 始终有一本居中并处于选中态（不允许「不选择」），首屏默认选中第一项。
///
/// 呈现：每行尺寸完全一致；所有相簿共用同一张文件夹贴图
/// （未选 `icon_folder`，选中 `icon_folder_selected`），文件夹前盖中央嵌一张
/// 4:3 裁切、带 2pt 白边的封面缩略图，右上角徽章显示张数。
/// 一屏行数、图标尺寸、标题 / 徽章字号全部由 `DeviceLayoutConfig` 的
/// `FavoriteSettings` 显式传入；组件内不再按窗口 / 设备自动推导形态。
/// 实际图标仍受栏宽与行高钳制；选中项只做一次「放大回弹」，静息时不常驻放大。
struct FavoriteAlbumColumn: View {
    let width: CGFloat
    let albums: [AlbumItem]
    let selectedAlbumID: String?
    /// 一次飞入动作进行中，用于给选中的相簿一个强调脉冲。
    let isReceiving: Bool
    /// 相簿封面缩略图统一走照片库的缓存加载器。
    let thumbnails: ThumbnailProvider
    /// 当前形态的收藏夹配置（行数 / 图标尺寸 / 字号），来自 `DeviceLayoutConfig`。
    let config: FavoriteSettings
    let onSelect: (AlbumItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// 与形态无关的几何常量集中在这里；形态相关的数值一律来自 `config`。
    private enum Layout {
        /// 渲染窗口 = 可见行数的一半 + 1.2 行余量，给拖拽过程留缓冲。
        static let renderRangeExtra: CGFloat = 1.2
        /// 图标宽度安全上限（占栏宽比例）：只防溢出，正常配置不会触发。
        static let maxIconWidthRatio: CGFloat = 0.90
        /// 行内给两行标题预留的高度、图标与标题间距、上下安全留白。
        /// 三者合起来是图标的行高钳制量（rowHeight − 50）。
        static let titleReserve: CGFloat = 24
        static let rowSpacing: CGFloat = 2
        static let verticalInset: CGFloat = 10
        /// 图标边长下限：极短屏也不会缩成看不见。
        static let minIconSize: CGFloat = 24
        /// 上下边缘的淡出比例：越小越像被容器硬边挡住。
        static let edgeFade: CGFloat = 0.04
        /// 封面内容宽度 / 图标边长；高度按 4:3 反推。
        static let coverWidthRatio: CGFloat = 0.60
        /// 封面外白边（pt）：图标放大后仍固定 2pt，不跟着一起变粗。
        static let coverBorder: CGFloat = 2
        /// 封面中心相对图标中心下移：对准文件夹前盖的视觉中心。
        static let coverCenterYRatio: CGFloat = 0.055
        /// 徽章相对图标右上角的外扩比例（随图标等比缩放）。
        static let badgeOffsetXRatio: CGFloat = 0.10
        static let badgeOffsetYRatio: CGFloat = 0.085
        /// 选中瞬间放大的峰值倍数，动画结束回到 1（保持统一大小）。
        static let selectionPop: CGFloat = 1.14
    }

    /// 同一套行数贯穿：行高、渲染窗口、拖拽吸附与点按换算全部共用。
    /// 转屏只改变每行的 pt 高度，`wheelPosition` 仍以「行」为单位，不需要重置。
    private var visibleRows: CGFloat { CGFloat(max(1, config.rows)) }

    private var renderRange: CGFloat { visibleRows / 2 + Layout.renderRangeExtra }

    /// 行高严格等于容器高度 / 可见行数。
    ///
    /// 容器高度由三栏区显式给定，这里不再用「最小行高」向父容器要空间——
    /// 否则行高一变大就会反过来撑高整行，把中栏顶上去。
    private func rowHeight(for height: CGFloat) -> CGFloat {
        max(1, height / visibleRows)
    }

    /// 图标边长 = 配置值，仅在会溢出栏宽 / 行高时收住；选中态不乘放大系数。
    private func iconSize(rowHeight: CGFloat) -> CGFloat {
        let widthBound = width * Layout.maxIconWidthRatio
        let heightBound = rowHeight
            - Layout.titleReserve
            - Layout.rowSpacing
            - Layout.verticalInset
        return max(Layout.minIconSize, min(config.iconSize, widthBound, heightBound))
    }

    /// 滚轮位置（以“中间项”为 0 的浮点下标，范围 `[0, count-1]`，非循环、有边界）。
    @State private var wheelPosition: CGFloat = 0
    @State private var dragStartPosition: CGFloat?
    @State private var isDragging = false
    /// 每次落定自增，驱动选中项「放大一下」的回弹动效。
    @State private var selectionPulseToken = 0

    var body: some View {
        // 延后入口已移到设置页：这里只剩滚轮本体，滚轮中心与左右栏同一套整行居中。
        Group {
            if albums.isEmpty {
                emptyState
            } else {
                wheel
            }
        }
        .frame(width: width)
        // 高度由三栏区显式传入（.frame(height:)），这里不再声明 maxHeight，
        // 免得收藏夹的最小高度反过来参与整行的高度协商。
        .onAppear {
            syncWheel(animated: false)
        }
        .onChange(of: selectedAlbumID) { _, _ in
            // 外部（抽屉、右滑后）改变默认相簿时，把对应那本转到中间。
            if !isDragging {
                syncWheel(animated: true)
            }
        }
        .onChange(of: albums) { _, _ in
            // 列表变化后重新对齐到当前选择；若当前选择已失效，回退到第一项
            // （收藏夹不允许「不选择」状态）。
            if let id = selectedAlbumID, albums.contains(where: { $0.id == id }) {
                syncWheel(animated: false)
            } else if let first = albums.first {
                onSelect(first)
            }
        }
    }

    // MARK: - 滚轮

    private var wheel: some View {
        GeometryReader { proxy in
            // 行高严格等于容器高度 / 可见行数；吸附距离与渲染行高共用同一个值。
            let rh = rowHeight(for: proxy.size.height)
            let isScrollable = albums.count > 1
            // 手势只挂在这个明确尺寸的容器上：不会越出右栏，也不会漏到中央按钮。
            ZStack {
                // 非循环：每一本相簿只渲染一次，滚轮位置钳制在 [0, count-1]，
                // 滑到首尾即停，不会重复、不会跳位。
                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                    let delta = CGFloat(index) - wheelPosition
                    // 只渲染窗口内的行，远处行直接跳过。
                    if abs(delta) < renderRange {
                        row(album, rowHeight: rh)
                            .frame(width: proxy.size.width, height: rh)
                            // 纯上下滚动：只按行距做纵向位移，没有横向弧线，
                            // 也没有 3D 透视 / 逐行缩放 / 逐行透明度。
                            .offset(y: delta * rh)
                            .zIndex(1000 - Double(abs(delta)))
                            .accessibilityHidden(abs(delta) > renderRange - 0.4)
                            .accessibilityLabel("\(album.title)，\(album.count) 张")
                            .accessibilityHint(album.id == selectedAlbumID ? "当前收藏夹" : "点按设为当前收藏夹")
                            .accessibilityAddTraits(album.id == selectedAlbumID ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction {
                                settle(to: index)
                            }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(rowHeight: rh), including: isScrollable ? .all : .none)
            .simultaneousGesture(
                // 点按由容器统一换算成最近的一行：单行不再各自铺满整宽的可点区域。
                // 行距与 delta 严格线性，所以纵向换算依然有效。
                SpatialTapGesture()
                    .onEnded { value in
                        guard !isDragging, isScrollable else { return }
                        let delta = (value.location.y - proxy.size.height / 2) / rh
                        settle(to: Int((wheelPosition + delta).rounded()))
                    },
                including: isScrollable ? .all : .none
            )
            // 裁掉选中回弹向外溢出的部分，视觉与命中都严格收在右栏内。
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: Layout.edgeFade),
                        .init(color: .black, location: 1 - Layout.edgeFade),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("收藏夹滚轮")
            .accessibilityValue(currentAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                guard albums.count > 1 else { return }
                switch direction {
                case .increment:
                    settle(to: Int(wheelPosition.rounded()) + 1)
                case .decrement:
                    settle(to: Int(wheelPosition.rounded()) - 1)
                @unknown default:
                    break
                }
            }
        }
        // 宽度定死、高度取 VStack 剩余空间（GeometryReader 本身弹性），
        // 不再写 maxHeight: .infinity 去参与父级高度协商。
        .frame(width: width)
        .hitDebugRegion("收藏夹滚轮")
    }

    private func dragGesture(rowHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = wheelPosition
                    isDragging = true
                }
                let base = dragStartPosition ?? wheelPosition
                // 手指下滑 = 内容下移 = 更靠前的相簿转到中间。
                // 非循环：位置钳制在 [0, count-1]，越过首尾停在原地（不允许滑出）。
                let raw = base - value.translation.height / rowHeight
                wheelPosition = min(maxPosition, max(0, raw))
            }
            .onEnded { value in
                let base = dragStartPosition ?? wheelPosition
                // 轻甩时按预测位移多走几格，滚轮才有惯性。
                let predicted = base - value.predictedEndTranslation.height / rowHeight
                // 非循环：落点同样钳制在 [0, count-1] 边界内。
                let target = min(maxPosition, max(0, predicted.rounded()))
                dragStartPosition = nil
                isDragging = false
                if reduceMotion {
                    wheelPosition = target
                } else {
                    withAnimation(Theme.Motion.animation(.spring, reduceMotion: false)) {
                        wheelPosition = target
                    }
                }
                commitSelection(at: Int(target))
                // 落定即回弹一次；震动仍由外部 selectDefaultAlbum 触发。
                selectionPulseToken += 1
            }
    }

    // MARK: - 行

    private func row(_ album: AlbumItem, rowHeight: CGFloat) -> some View {
        let isSelected = album.id == selectedAlbumID
        let icon = iconSize(rowHeight: rowHeight)
        return VStack(spacing: Layout.rowSpacing) {
            // 所有相簿的图标、封面与徽章尺寸完全一致；选中只换贴图 + 一次回弹。
            ZStack {
                Image(isSelected ? "icon_folder_selected" : "icon_folder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: icon, height: icon)
                    .shadow(
                        color: .black.opacity(0.16),
                        radius: max(4, icon * 0.07),
                        x: 0,
                        y: max(3, icon * 0.05)
                    )

                FavoriteAlbumCover(
                    localID: album.coverLocalID,
                    thumbnails: thumbnails,
                    width: icon * Layout.coverWidthRatio,
                    border: Layout.coverBorder
                )
                .offset(y: icon * Layout.coverCenterYRatio)
            }
            .overlay(alignment: .topTrailing) {
                // 数量徽章贴在图标右上角内侧，避免被滚动容器的裁剪切掉。
                countBadge(album.count, iconSize: icon)
                    .offset(x: icon * Layout.badgeOffsetXRatio, y: -icon * Layout.badgeOffsetYRatio)
            }
            .background {
                if isSelected {
                    Circle()
                        .fill(Theme.Device.door.opacity(0.20))
                        .frame(width: icon * 1.3, height: icon * 1.3)
                        .blur(radius: max(10, icon * 0.17))
                }
            }
            .keyframeAnimator(
                initialValue: SelectionPulse(),
                trigger: selectionPulseToken
            ) { content, value in
                content.scaleEffect(isSelected ? value.scale : 1)
            } keyframes: { _ in
                let amplitude: CGFloat = reduceMotion ? 0 : 1
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1, duration: 0.02)
                    CubicKeyframe(1 + (Layout.selectionPop - 1) * amplitude, duration: 0.12)
                    CubicKeyframe(1, duration: 0.20)
                }
            }

            Text(album.title)
                .font(.system(size: config.titleSize, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.Device.door : Theme.Text.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // 飞入时的轻微脉冲与「选中回弹」是两条独立通道，互不影响。
        .scaleEffect(isSelected && isReceiving ? 1.06 : 1)
        .shadow(
            color: isSelected && isReceiving ? Theme.Device.door.opacity(0.5) : .clear,
            radius: 8
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.7),
            value: isReceiving
        )
    }

    /// 选中回弹的可动画量；只放大一下，随后回到 1 保持统一大小。
    private struct SelectionPulse {
        var scale: CGFloat = 1
    }

    /// 相簿照片数量徽章：只显示数字，封面缩略图另画在前盖中央。
    /// 小于 10000 显示完整数字；大于等于 10000 折叠为「10k+」。
    private func countBadge(_ count: Int, iconSize: CGFloat) -> some View {
        let label = count >= 10000 ? "10k+" : "\(count)"
        return Text(label)
            .font(.system(size: config.badgeSize, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.Text.onWhite)
            .padding(.horizontal, 4)
            .frame(
                minWidth: max(16, iconSize * 0.16),
                minHeight: max(15, iconSize * 0.15)
            )
            .background(Theme.Surface.pill, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: max(12, config.iconSize * 0.15), weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)
            Text("没有相簿")
                .font(.system(size: max(10, config.iconSize * 0.10), weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - 滚轮计算

    /// 非循环：滚轮位置被钳制在 `[0, count-1]`，首尾就是边界，不重复摆放。
    private var maxPosition: CGFloat { CGFloat(max(0, albums.count - 1)) }

    /// 把任意下标钳制到合法范围 `[0, count-1]`（非循环：越界直接停在首尾）。
    private func clampedIndex(_ index: Int) -> Int {
        guard !albums.isEmpty else { return 0 }
        return min(max(0, index), albums.count - 1)
    }

    /// 点按或无障碍调节：把指定行转到中间并提交（已钳制在 `[0, count-1]` 边界）。
    private func settle(to index: Int) {
        guard !albums.isEmpty else { return }
        let clamped = clampedIndex(index)
        let target = CGFloat(clamped)
        if reduceMotion {
            wheelPosition = target
        } else {
            withAnimation(Theme.Motion.animation(.spring, reduceMotion: false)) {
                wheelPosition = target
            }
        }
        commitSelection(at: clamped)
        selectionPulseToken += 1
    }

    private func commitSelection(at index: Int) {
        guard !albums.isEmpty else { return }
        let album = albums[clampedIndex(index)]
        guard album.id != selectedAlbumID else { return }
        onSelect(album)
    }

    /// 非循环：滚轮位置即相簿下标本身（范围 `[0, count-1]`），无需按圈取最近落点。
    private func nearestPosition(forIndex index: Int) -> CGFloat {
        CGFloat(clampedIndex(index))
    }

    /// 让滚轮对齐当前默认相簿；列表首次加载、外部改选、相簿增删时调用。
    private func syncWheel(animated: Bool) {
        guard let id = selectedAlbumID,
              let index = albums.firstIndex(where: { $0.id == id }) else { return }
        let target = nearestPosition(forIndex: index)
        guard abs(target - wheelPosition) > 0.01 else { return }
        if animated, !reduceMotion {
            withAnimation(Theme.Motion.animation(.spring, reduceMotion: false)) {
                wheelPosition = target
            }
        } else {
            wheelPosition = target
        }
    }

    private var currentAccessibilityValue: String {
        guard !albums.isEmpty else { return "无相簿" }
        let album = albums[clampedIndex(Int(wheelPosition.rounded()))]
        return "\(album.title)，\(album.count) 张"
    }
}

/// 文件夹前盖中央的封面缩略图：4:3 比例裁切 + 2pt 白边。
/// 空相簿或加载中保持凹陷底槽，不闪白、不撑大图标。
private struct FavoriteAlbumCover: View {
    let localID: String?
    let thumbnails: ThumbnailProvider
    /// 内容区宽度；高度固定为宽度的 3/4。
    let width: CGFloat
    /// 白边宽度：横屏图标放大后仍固定 2pt，不跟着变粗。
    let border: CGFloat

    @State private var image: UIImage?

    private var contentHeight: CGFloat { width * 3 / 4 }

    var body: some View {
        ZStack {
            Theme.Surface.sunken

            if let image {
                Image(uiImage: image)
                    .resizable()
                    // 4:3 取景：等比放大填满后裁掉多余部分，不拉伸照片。
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: max(9, width * 0.24), weight: .regular))
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .frame(width: width, height: contentHeight)
        .clipped()
        .padding(border)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
        .task(id: localID) {
            guard let localID else {
                image = nil
                return
            }
            let scale = UIScreen.main.scale
            image = await thumbnails.image(
                for: localID,
                targetSize: CGSize(width: width * scale, height: contentHeight * scale)
            )
        }
    }
}

enum FavoriteAlbumPreviewData {
    static let albums: [AlbumItem] = [
        AlbumItem(id: "1", title: "旅行", kind: .user, count: 32, symbolName: "folder", coverLocalID: "ui-test-photo-01"),
        AlbumItem(id: "2", title: "家人合影", kind: .user, count: 108, symbolName: "folder", coverLocalID: "ui-test-photo-02"),
        AlbumItem(id: "3", title: "截图整理", kind: .user, count: 12, symbolName: "folder", coverLocalID: "ui-test-photo-03"),
        AlbumItem(id: "4", title: "壁纸", kind: .user, count: 64, symbolName: "folder", coverLocalID: "ui-test-photo-04"),
        AlbumItem(id: "5", title: "美食", kind: .user, count: 27, symbolName: "folder", coverLocalID: "ui-test-photo-05")
    ]
}

#Preview("iPhone 竖屏 · 5 行原尺寸") {
    FavoriteAlbumColumn(
        width: 88,
        albums: FavoriteAlbumPreviewData.albums,
        selectedAlbumID: "3",
        isReceiving: false,
        thumbnails: ThumbnailProvider(),
        config: DeviceLayoutConfig.iPhonePortrait.favorites,
        onSelect: { _ in }
    )
    .frame(height: 600)
    .padding()
    .background(Theme.Scenery.backdrop)
}

#Preview("任意横屏 · 3 行放大") {
    FavoriteAlbumColumn(
        width: 158,
        albums: FavoriteAlbumPreviewData.albums,
        selectedAlbumID: "3",
        isReceiving: false,
        thumbnails: ThumbnailProvider(),
        config: DeviceLayoutConfig.iPadLandscape.favorites,
        onSelect: { _ in }
    )
    .frame(height: 600)
    .padding()
    .background(Theme.Scenery.backdrop)
}

#Preview("iPad 竖屏 · 5 行放大") {
    FavoriteAlbumColumn(
        width: 158,
        albums: FavoriteAlbumPreviewData.albums,
        selectedAlbumID: "3",
        isReceiving: false,
        thumbnails: ThumbnailProvider(),
        config: DeviceLayoutConfig.iPadPortrait.favorites,
        onSelect: { _ in }
    )
    .frame(height: 900)
    .padding()
    .background(Theme.Scenery.backdrop)
}
