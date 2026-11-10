import AVKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// 保险箱全屏查看的启动请求。
struct VaultFullscreenRequest: Identifiable, Equatable {
    let id: UUID
}

/// 保险箱内容的全屏欣赏：交互与整理时的照片预览一致。
/// 静态图缩放平移、实况自动播放一次、视频交给系统控件；下滑关闭、左右滑或底部箭头切换。
struct VaultFullscreenView: View {
    let records: [VaultRecord]
    let startID: UUID
    let onClose: () -> Void

    @Environment(VaultStore.self) private var vault
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

    init(records: [VaultRecord], startID: UUID, onClose: @escaping () -> Void) {
        self.records = records
        self.startID = startID
        self.onClose = onClose
        _index = State(initialValue: records.firstIndex { $0.id == startID } ?? 0)
    }

    private var currentRecord: VaultRecord? {
        guard records.indices.contains(index) else { return nil }
        return records[index]
    }

    private var isZoomed: Bool { zoomScale > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let record = currentRecord {
                    mediaContent(record: record, size: proxy.size)
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
    private func mediaContent(record: VaultRecord, size: CGSize) -> some View {
        let content = Group {
            switch record.mediaKind {
            case .video:
                VaultVideoPlayer(record: record)
                    .padding(.vertical, 56)
            case .livePhoto:
                VaultLivePhotoDisplay(
                    record: record,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            default:
                VaultStillImage(
                    record: record,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if record.mediaKind == .video {
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
        guard records.indices.contains(target) else {
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
                .accessibilityLabel("关闭全屏")

                Spacer()

                if records.count > 1 {
                    Text("\(index + 1) / \(records.count)")
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
            .accessibilityLabel("上一张")

            VStack(spacing: 2) {
                Text(currentRecord?.displayDateText ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text(currentRecord?.mediaKind.displayName ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                if let record = currentRecord {
                    Text(VaultLimits.readableBytes(record.byteSize))
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
                    .foregroundStyle(index + 1 < records.count ? .white : .white.opacity(0.28))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .disabled(index + 1 >= records.count)
            .accessibilityLabel("下一张")
        }
    }
}

// MARK: - 静态图

private struct VaultStillImage: View {
    let record: VaultRecord
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    @Environment(VaultStore.self) private var vault
    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadingText = "正在读取…"

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
                    Text("无法读取这个保险箱文件")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView().tint(.white)
                    Text(loadingText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: record.id) {
            failed = false
            image = nil
            loadingText = vault.encryptionMode == .strong ? "正在解密…" : "正在读取…"

            guard let media = try? await vault.prepareMedia(for: record) else {
                failed = true
                return
            }
            guard !Task.isCancelled else {
                if media.isTemporary { media.cleanup() }
                return
            }

            let pixel = max(targetSize.width, targetSize.height)
            let loaded = await Task.detached(priority: .userInitiated) {
                VaultMediaDecoder.image(url: media.imageURL, maxPixel: pixel)
            }.value
            if media.isTemporary { media.cleanup() }

            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

// MARK: - 实况照片

private struct VaultLivePhotoDisplay: View {
    let record: VaultRecord
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    @Environment(VaultStore.self) private var vault
    @State private var livePhoto: PHLivePhoto?
    @State private var failed = false
    @State private var loadingText = "正在读取…"
    @State private var prepared: VaultPreparedMedia?

    private var targetSize: CGSize {
        CGSize(
            width: max(1, size.width * UIScreen.main.scale),
            height: max(1, size.height * UIScreen.main.scale)
        )
    }

    var body: some View {
        Group {
            if let livePhoto {
                VaultLivePhotoContainer(livePhoto: livePhoto)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
            } else if failed {
                // 实况资源不可用时退化为静态图。
                VaultStillImage(
                    record: record,
                    size: size,
                    zoomScale: zoomScale,
                    panOffset: panOffset
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView().tint(.white)
                    Text(loadingText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: record.id) {
            failed = false
            livePhoto = nil
            prepared?.cleanup()
            prepared = nil
            loadingText = vault.encryptionMode == .strong ? "正在解密…" : "正在读取…"

            guard let media = try? await vault.prepareMedia(for: record),
                  let videoURL = media.videoURL else {
                failed = true
                return
            }
            guard !Task.isCancelled else {
                media.cleanup()
                return
            }
            // PHLivePhoto 播放时仍会读取配对视频，临时文件要保留到本页离开。
            prepared = media

            let created = await VaultMediaDecoder.livePhoto(
                imageURL: media.imageURL,
                videoURL: videoURL,
                targetSize: targetSize
            )

            guard !Task.isCancelled else { return }
            if let created {
                livePhoto = created
            } else {
                failed = true
            }
        }
        .onDisappear {
            prepared?.cleanup()
            prepared = nil
        }
    }
}

private struct VaultLivePhotoContainer: UIViewRepresentable {
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

private struct VaultVideoPlayer: View {
    let record: VaultRecord

    @Environment(VaultStore.self) private var vault
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var loadingText = "正在读取…"
    @State private var prepared: VaultPreparedMedia?

    var body: some View {
        Group {
            if let player {
                VaultVideoPlayerContainer(player: player)
            } else if failed {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                    Text("无法读取这段保险箱视频")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView().tint(.white)
                    Text(loadingText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: record.id) {
            failed = false
            player?.pause()
            player = nil
            prepared?.cleanup()
            prepared = nil
            loadingText = vault.encryptionMode == .strong ? "正在解密…" : "正在读取…"

            guard let media = try? await vault.prepareMedia(for: record) else {
                failed = true
                return
            }
            guard !Task.isCancelled else {
                media.cleanup()
                return
            }

            prepared = media
            let created = AVPlayer(url: media.imageURL)
            player = created
            created.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
            prepared?.cleanup()
            prepared = nil
        }
    }
}

private struct VaultVideoPlayerContainer: UIViewControllerRepresentable {
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

// MARK: - 解码

enum VaultMediaDecoder {
    static func image(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    static func livePhoto(imageURL: URL, videoURL: URL, targetSize: CGSize) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            var didResume = false
            PHLivePhoto.request(
                withResourceFileURLs: [imageURL, videoURL],
                placeholderImage: nil,
                targetSize: targetSize,
                contentMode: .aspectFit
            ) { livePhoto, info in
                guard !didResume else { return }
                if (info[PHLivePhotoInfoCancelledKey] as? Bool) == true { return }
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                didResume = true
                continuation.resume(returning: livePhoto)
            }
        }
    }
}
