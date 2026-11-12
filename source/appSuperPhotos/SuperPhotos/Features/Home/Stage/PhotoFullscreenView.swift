import AVKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// 全屏查看的启动请求；带上当前照片 id，关闭后舞台仍停在这张。
struct FullscreenRequest: Identifiable, Equatable {
    let id: String
}

/// 全屏查看/播放：静态图支持缩放平移，实况照片自动播放，视频带系统播放控件。
/// 下滑关闭（不推进），左右滑或底部箭头切换上一张/下一张。
struct PhotoFullscreenView: View {
    let items: [PhotoItem]
    let startID: String
    let thumbnails: ThumbnailProvider
    let onChangeCurrent: (String) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var index: Int
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: DragAxis?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var panBase: CGSize = .zero

    private enum DragAxis {
        case horizontal
        case vertical
    }

    init(
        items: [PhotoItem],
        startID: String,
        thumbnails: ThumbnailProvider,
        onChangeCurrent: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.items = items
        self.startID = startID
        self.thumbnails = thumbnails
        self.onChangeCurrent = onChangeCurrent
        self.onClose = onClose
        _index = State(initialValue: items.firstIndex { $0.id == startID } ?? 0)
    }

    private var currentItem: PhotoItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private var isZoomed: Bool { zoomScale > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let item = currentItem {
                    mediaContent(item: item, size: proxy.size)
                        .offset(y: max(0, dragOffset.height))
                        .scaleEffect(dismissScale)
                        .opacity(dismissOpacity)
                }

                chrome(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .statusBarHidden(true)
        .onChange(of: index) { _, _ in
            resetGesture()
            resetZoom(animated: false)
            if let id = currentItem?.id {
                onChangeCurrent(id)
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            // 全屏期间照片被删除/筛掉时，把索引夹回有效范围。
            if index >= ids.count {
                index = max(0, ids.count - 1)
            }
        }
    }

    private var dismissScale: CGFloat {
        guard dragOffset.height > 0 else { return 1 }
        return max(0.82, 1 - dragOffset.height / 1600)
    }

    private var dismissOpacity: Double {
        guard dragOffset.height > 0 else { return 1 }
        return max(0.35, 1 - dragOffset.height / 900)
    }

    // MARK: - 媒体

    @ViewBuilder
    private func mediaContent(item: PhotoItem, size: CGSize) -> some View {
        let content = Group {
            switch item.kind {
            case .video:
                FullscreenVideoPlayer(localID: item.id)
                    .padding(.vertical, 56)
            case .livePhoto:
                FullscreenLivePhotoDisplay(
                    localID: item.id,
                    thumbnails: thumbnails,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            default:
                FullscreenStillImage(
                    localID: item.id,
                    thumbnails: thumbnails,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if item.kind == .video {
            // 视频交给系统控件，避免自定义拖拽与进度条抢手势。
            content
        } else {
            content
                .contentShape(Rectangle())
                .gesture(dragGesture(size: size))
                .simultaneousGesture(magnifyGesture)
        }
    }

    // MARK: - 手势

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if isZoomed {
                    let proposed = CGSize(
                        width: panBase.width + value.translation.width,
                        height: panBase.height + value.translation.height
                    )
                    panOffset = clampedPan(proposed, size: size)
                    return
                }

                if dragAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) > 4 else { return }
                    dragAxis = dy > dx ? .vertical : .horizontal
                }

                switch dragAxis {
                case .vertical:
                    // 只跟随下拉；上拉不响应，避免和视频/地图类习惯冲突。
                    dragOffset = CGSize(width: 0, height: max(0, value.translation.height))
                case .horizontal:
                    dragOffset = CGSize(width: value.translation.width * 0.7, height: 0)
                case .none:
                    break
                }
            }
            .onEnded { value in
                if isZoomed {
                    panBase = panOffset
                    return
                }

                let axis = dragAxis
                dragAxis = nil

                switch axis {
                case .vertical:
                    if value.translation.height > 90
                        || value.predictedEndTranslation.height > 220 {
                        onClose()
                    } else {
                        rebound()
                    }
                case .horizontal:
                    let dx = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    if dx <= -60 || predicted <= -120 {
                        step(1)
                    } else if dx >= 60 || predicted >= 120 {
                        step(-1)
                    } else {
                        rebound()
                    }
                case .none:
                    rebound()
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                zoomScale = min(4, max(1, zoomBase * value.magnification))
            }
            .onEnded { _ in
                zoomBase = zoomScale
                if zoomScale < 1.06 {
                    resetZoom(animated: true)
                }
            }
    }

    private func clampedPan(_ value: CGSize, size: CGSize) -> CGSize {
        let maxX = max(0, size.width * (zoomScale - 1) / 2) * 0.85
        let maxY = max(0, size.height * (zoomScale - 1) / 2) * 0.85
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func resetZoom(animated: Bool) {
        let apply = {
            zoomScale = 1
            zoomBase = 1
            panOffset = .zero
            panBase = .zero
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), apply)
        } else {
            apply()
        }
    }

    private func resetGesture() {
        dragAxis = nil
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) {
            dragOffset = .zero
        }
    }

    private func rebound() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = .zero
        }
    }

    private func step(_ delta: Int) {
        let target = index + delta
        guard items.indices.contains(target) else {
            rebound()
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        let animation = reduceMotion ? Animation.easeOut(duration: 0.12) : .easeOut(duration: 0.2)
        withAnimation(animation) {
            dragOffset = .zero
            index = target
        }
    }

    // MARK: - 控件

    private func chrome(size: CGSize) -> some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("关闭全屏".localized)

                Spacer()

                if items.count > 1 {
                    Text("\(index + 1) / \(items.count)")
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            Spacer()

            bottomBar
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
        }
        .opacity(1 - min(1, dragOffset.height / 320))
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // 上一张 / 下一张：临时入口，后续替换成其他切换方式只需改这两个按钮。
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(index > 0 ? .white : .white.opacity(0.28))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .disabled(index <= 0)
            .accessibilityLabel("上一张".localized)

            VStack(spacing: 2) {
                Text(currentItem?.shortDateText ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text(currentItem?.kind.displayName ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                if let item = currentItem {
                    Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height))")
                        .font(.system(size: 9, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(minWidth: 96)

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(index + 1 < items.count ? .white : .white.opacity(0.28))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .disabled(index + 1 >= items.count)
            .accessibilityLabel("下一张".localized)
        }
    }
}

// MARK: - 静态图

private struct FullscreenStillImage: View {
    let localID: String
    let thumbnails: ThumbnailProvider
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    @State private var image: UIImage?
    @State private var failed = false

    private var targetSize: CGSize {
        CGSize(
            width: max(1, size.width * UIScreen.main.scale),
            height: max(1, size.height * UIScreen.main.scale)
        )
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
            } else if failed {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                    Text("无法加载这张照片".localized)
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localID) {
            failed = false
            image = nil
            // 先出低清占位，再换成全尺寸，避免全屏黑屏等待。
            if let quick = await thumbnails.image(for: localID, targetSize: targetSize) {
                image = quick
            }
            if let full = await FullscreenMediaLoader.image(localID: localID, targetSize: targetSize) {
                image = full
            } else if image == nil {
                failed = true
            }
        }
    }
}

// MARK: - 实况照片

private struct FullscreenLivePhotoDisplay: View {
    let localID: String
    let thumbnails: ThumbnailProvider
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    @State private var livePhoto: PHLivePhoto?
    @State private var failed = false

    private var targetSize: CGSize {
        CGSize(
            width: max(1, size.width * UIScreen.main.scale),
            height: max(1, size.height * UIScreen.main.scale)
        )
    }

    var body: some View {
        Group {
            if let livePhoto {
                LivePhotoContainer(livePhoto: livePhoto)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
            } else if failed {
                // 实况资源不可用时退化为静态图。
                FullscreenStillImage(
                    localID: localID,
                    thumbnails: thumbnails,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localID) {
            failed = false
            livePhoto = nil
            livePhoto = await FullscreenMediaLoader.livePhoto(localID: localID, targetSize: targetSize)
            if livePhoto == nil {
                failed = true
            }
        }
    }
}

private struct LivePhotoContainer: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        view.startPlayback(with: .full)
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
            uiView.startPlayback(with: .full)
        }
    }
}

// MARK: - 视频

private struct FullscreenVideoPlayer: View {
    let localID: String

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        Group {
            if let player {
                VideoPlayerContainer(player: player)
            } else if failed {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                    Text("无法加载这段视频".localized)
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localID) {
            failed = false
            player?.pause()
            player = nil
            guard let item = await FullscreenMediaLoader.playerItem(localID: localID) else {
                failed = true
                return
            }
            let created = AVPlayer(playerItem: item)
            player = created
            created.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - 加载

@MainActor
enum FullscreenMediaLoader {
    static func image(localID: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: localID) else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else { return }
                if (info?[PHImageCancelledKey] as? Bool) == true { return }
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    static func livePhoto(localID: String, targetSize: CGSize) async -> PHLivePhoto? {
        guard let asset = asset(for: localID) else { return nil }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                guard !didResume else { return }
                if (info?[PHImageCancelledKey] as? Bool) == true { return }
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                didResume = true
                continuation.resume(returning: livePhoto)
            }
        }
    }

    static func playerItem(localID: String) async -> AVPlayerItem? {
        guard let asset = asset(for: localID) else { return nil }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private static func asset(for localID: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject
    }
}
