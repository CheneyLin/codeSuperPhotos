import SwiftUI

/// 右侧收藏夹区：滚轮式选择“我的相簿”，停在中间的一本即当前收藏夹目标，
/// 照片右滑时飞入这本相簿。
///
/// 呈现：每个条目是一张相簿图标（按相簿 ID 稳定伪随机选用 `icon_folder_*`），
/// 右上角徽章显示该相簿的照片数量，图标下方是 1–2 行相簿名。
/// 选中项只放大 + 提亮，不画描边或选中带。
struct FavoriteAlbumColumn: View {
    let width: CGFloat
    let albums: [AlbumItem]
    let selectedAlbumID: String?
    /// 一次飞入动作进行中，用于给选中的相簿一个强调脉冲。
    let isReceiving: Bool
    let onSelect: (AlbumItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    private var compact: Bool { width < 88 }

    /// 环形排布的几何参数：半径、每行角度、右移量、可见行数都集中在这里，方便微调。
    private enum Ring {
        /// 圆弧半径：圆心在栏中心右侧这么远（落在屏幕外）。
        /// 越大弧线越平、端头右移越少；越小越像挂着一个大环。
        static let radius: CGFloat = 2200
        /// 一屏完整可见的行数：5 行整行可见；再往外的行整行落在容器外，被边缘裁掉。
        static let visibleRows: CGFloat = 5
        /// 极限角度对应的 sin 上限，半径异常小时兜底，避免开方出现负数。
        static let maxSin: CGFloat = 0.98
        /// 端头在纯圆弧之上再叠加的右移量，按 |delta| / (visibleRows / 2) 线性给。
        static let edgeExtraRight: CGFloat = 4
        /// 只渲染这个行距范围内的行（多留半行给拖拽过程），更远的直接跳过。
        static let renderRange: CGFloat = 3.6
        /// 上下边缘的淡出比例：越小越像被容器硬边挡住。
        static let edgeFade: CGFloat = 0.04
        /// 选中图标相对基础尺寸的放大倍数（基础 58 → 约 72.5）。
        static let selectedIconScale: CGFloat = 1.25
    }

    /// 行高严格等于容器高度 / 可见行数。
    ///
    /// 容器高度由三栏区显式给定，这里不再用「最小行高」向父容器要空间——
    /// 否则行高一变大就会反过来撑高整行，把中栏顶上去。
    private func rowHeight(for height: CGFloat) -> CGFloat {
        max(1, height / Ring.visibleRows)
    }

    /// 相簿图标基础边长：跟着栏宽收放；选中项在此基础上再放大 25%。
    private var baseIconSize: CGFloat { min(compact ? 46 : 60, width * 0.66) }

    /// 滚轮位置（以“中间项”为 0 的浮点下标）；拖拽时跟手。
    @State private var wheelPosition: CGFloat = 0
    @State private var dragStartPosition: CGFloat?
    @State private var isDragging = false

    /// 相簿图标只在 `icon_folder_*` 系列里选；命名集中在这里，替换素材只改这一处。
    private static let folderIcons = [
        "icon_folder_album",
        "icon_folder_cat",
        "icon_folder_flower",
        "icon_folder_food",
        "icon_folder_scenery"
    ]

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
            wrapWheelPosition()
            syncWheel(animated: false)
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
                // 无限循环：每一本相簿按“圈数”重复摆放，滚动位置不做边界限制。
                // 渲染窗口里总有内容，跨过首尾时是另一圈的同一本接上，
                // 旧的那份径向距离变大后自然缩淡，不会跳位。
                ForEach(laps, id: \.self) { lap in
                    ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                        let delta = CGFloat(index + lap * albums.count) - wheelPosition
                        // 只渲染窗口内的行，远处行直接跳过。
                        if abs(delta) < Ring.renderRange {
                            row(album, delta: delta)
                                .frame(width: proxy.size.width, height: rh)
                                // 沿大圆弧排布：竖直按行距、水平按圆方程向右弯。
                                .offset(arcOffset(delta: delta, rowHeight: rh))
                                .scaleEffect(rowScale(delta))
                                .opacity(rowOpacity(delta))
                                .rotation3DEffect(
                                    .degrees(Double(min(abs(delta), 3)) * (delta < 0 ? 9 : -9)),
                                    axis: (x: 1, y: 0, z: 0),
                                    anchor: .center,
                                    perspective: 0.55
                                )
                                .zIndex(1000 - Double(abs(delta)))
                                // 循环用的重复圈只给中心那份做无障碍元素。
                                .accessibilityHidden(lap != 0 || abs(delta) > Ring.renderRange - 0.4)
                                .accessibilityLabel("\(album.title)，\(album.count) 张")
                                .accessibilityHint(album.id == selectedAlbumID ? "当前收藏夹" : "点按设为当前收藏夹")
                                .accessibilityAddTraits(album.id == selectedAlbumID ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction {
                                    settle(to: index)
                                }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(rowHeight: rh), including: isScrollable ? .all : .none)
            .simultaneousGesture(
                // 点按由容器统一换算成最近的一行：单行不再各自铺满整宽的可点区域。
                // 行距与 delta 严格线性，弧线只改变绘制位置，所以纵向换算依然有效。
                SpatialTapGesture()
                    .onEnded { value in
                        guard !isDragging, isScrollable else { return }
                        let delta = (value.location.y - proxy.size.height / 2) / rh
                        settle(to: Int((wheelPosition + delta).rounded()))
                    },
                including: isScrollable ? .all : .none
            )
            // 裁掉缩放/透视向外溢出的部分，视觉与命中都严格收在右栏内。
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: Ring.edgeFade),
                        .init(color: .black, location: 1 - Ring.edgeFade),
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
                // 无限循环：位置不做边界限制，越过首尾由渲染时的重复圈接上。
                wheelPosition = base - value.translation.height / rowHeight
            }
            .onEnded { value in
                let base = dragStartPosition ?? wheelPosition
                // 轻甩时按预测位移多走几格，滚轮才有惯性。
                let predicted = base - value.predictedEndTranslation.height / rowHeight
                let target = predicted.rounded()
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
            }
    }

    // MARK: - 行

    private func row(_ album: AlbumItem, delta: CGFloat) -> some View {
        let isSelected = album.id == selectedAlbumID
        // 选中项图标放大 25%（相对基础 58），不再叠加整体缩放去放大文字。
        let iconSize = baseIconSize * (isSelected ? Ring.selectedIconScale : 1)

        return VStack(spacing: 5) {
            Image(folderIconName(for: album.id))
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize * 0.88)
                .opacity(isSelected ? 1 : 0.84)
                .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 3)
                .overlay(alignment: .topTrailing) {
                    // 数量徽章贴在图标右上角内侧，避免被滚动容器的裁剪切掉。
                    countBadge(album.count)
                        .offset(x: 6, y: -5)
                }
                .background {
                    if isSelected {
                        Circle()
                            .fill(Theme.Accent.brass.opacity(0.20))
                            .frame(width: iconSize * 1.3, height: iconSize * 1.3)
                            .blur(radius: 10)
                    }
                }

            Text(album.title)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.Accent.brass : Theme.Text.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // 选中只靠图标放大 + 提亮表达，不画描边/选中带；这里只保留飞入时的轻微脉冲。
        .scaleEffect(isSelected && isReceiving ? 1.06 : 1)
        .shadow(
            color: isSelected && isReceiving ? Theme.Accent.brass.opacity(0.5) : .clear,
            radius: 8
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.7),
            value: isReceiving
        )
        .animation(
            Theme.Motion.animation(.spring, reduceMotion: reduceMotion),
            value: isSelected
        )
    }

    /// 相簿照片数量徽章：只显示数字，不再加载封面缩略图。
    private func countBadge(_ count: Int) -> some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.Text.onWhite)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 15)
            .background(Theme.Surface.pill, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)
            Text("没有相簿")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - 图标

    /// 按相簿 ID 稳定选图标：同一次安装、同一本相簿每次都一样，不随刷新变化。
    private func folderIconName(for id: String) -> String {
        Self.folderIcons[Self.stableHash(id) % Self.folderIcons.count]
    }

    /// FNV-1a：不依赖 Swift 每次启动都会变的 `hashValue`。
    private static func stableHash(_ value: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(truncatingIfNeeded: hash) & 0x7fff_ffff
    }

    // MARK: - 滚轮计算

    /// 需要重复摆放的圈数：窗口比一圈还高时，同一本相簿会在上下同时出现，
    /// 这样跨首尾是“另一份逐渐淡入/淡出”，而不是同一项突然跳位。
    private var laps: [Int] {
        guard albums.count > 1 else { return [0] }
        let extra = Int((Ring.renderRange / CGFloat(albums.count)).rounded(.up))
        return Array(-extra...extra)
    }

    /// 圆弧落点：竖直方向严格保持「行距 × 下标差」，
    /// 水平方向按「圆心在栏中心右侧 Ring.radius 处」的圆方程向右弯。
    /// 中间项正好落在栏中心，越往上下两端越靠右，形成挂在右侧的大环。
    private func arcOffset(delta: CGFloat, rowHeight: CGFloat) -> CGSize {
        let dy = delta * rowHeight
        let limit = Ring.radius * Ring.maxSin
        let cappedDy = min(max(-limit, dy), limit)
        // dx = R - √(R² - dy²)：圆心在右边，圆上的点只会相对圆心向左，越远越靠右。
        let dx = Ring.radius - (Ring.radius * Ring.radius - cappedDy * cappedDy).squareRoot()
        // 端头再加一点额外右移（按可见半程线性给），让环更明显。
        let extraRight = Ring.edgeExtraRight * min(abs(delta) / (Ring.visibleRows / 2), 1)
        return CGSize(width: dx + extraRight, height: dy)
    }

    private func rowScale(_ delta: CGFloat) -> CGFloat {
        // 边缘行（|delta|≈2）只缩到 0.9，避免被压得过小。
        max(0.84, 1 - abs(delta) * 0.05)
    }

    private func rowOpacity(_ delta: CGFloat) -> Double {
        // 边缘行保留 0.6 以上，配合更窄的上下遮罩，两端干净地消失在容器边缘。
        max(0.6, 1 - Double(abs(delta)) * 0.13)
    }

    /// 把任意下标折回 0..<count（无限循环用）。
    private func wrappedIndex(_ index: Int) -> Int {
        guard !albums.isEmpty else { return 0 }
        let count = albums.count
        return ((index % count) + count) % count
    }

    /// 点按或无障碍调节：把指定行转到离当前位置最近的那一圈并提交。
    private func settle(to index: Int) {
        guard albums.count > 0 else { return }
        guard albums.count > 1 else { return }
        let wrapped = wrappedIndex(index)
        let target = nearestPosition(forIndex: wrapped)
        if reduceMotion {
            wheelPosition = target
        } else {
            withAnimation(Theme.Motion.animation(.spring, reduceMotion: false)) {
                wheelPosition = target
            }
        }
        commitSelection(at: wrapped)
    }

    private func commitSelection(at index: Int) {
        guard !albums.isEmpty else { return }
        let album = albums[wrappedIndex(index)]
        guard album.id != selectedAlbumID else { return }
        onSelect(album)
    }

    /// 同一本相簿在环上有无数个落点，取离当前位置最近的那个：
    /// 外部改选时只就近转一小段，不会绕整圈。
    private func nearestPosition(forIndex index: Int) -> CGFloat {
        guard albums.count > 1 else { return CGFloat(index) }
        let count = CGFloat(albums.count)
        let base = CGFloat(index)
        let turns = ((wheelPosition - base) / count).rounded()
        return base + turns * count
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

    /// 把位置折回一圈内，保持数值不越滚越大。
    /// 平移整圈对渲染没有影响（重复圈会接上），所以这一步在视觉上是无缝的。
    private func wrapWheelPosition() {
        guard !albums.isEmpty else {
            wheelPosition = 0
            return
        }
        let count = CGFloat(albums.count)
        var position = wheelPosition.truncatingRemainder(dividingBy: count)
        if position < 0 { position += count }
        wheelPosition = position
    }

    private var currentAccessibilityValue: String {
        guard !albums.isEmpty else { return "无相簿" }
        let album = albums[wrappedIndex(Int(wheelPosition.rounded()))]
        return "\(album.title)，\(album.count) 张"
    }
}

#Preview {
    FavoriteAlbumColumn(
        width: 78,
        albums: [
            AlbumItem(id: "1", title: "旅行", kind: .user, count: 32, symbolName: "folder"),
            AlbumItem(id: "2", title: "家人合影", kind: .user, count: 108, symbolName: "folder"),
            AlbumItem(id: "3", title: "截图整理", kind: .user, count: 12, symbolName: "folder"),
            AlbumItem(id: "4", title: "壁纸", kind: .user, count: 64, symbolName: "folder")
        ],
        selectedAlbumID: "2",
        isReceiving: false,
        onSelect: { _ in }
    )
    .frame(height: 520)
    .padding()
    .background(Theme.Scenery.backdrop)
}
