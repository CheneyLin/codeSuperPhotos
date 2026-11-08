import SwiftUI
import UIKit

/// 统一的照片缩略图视图；加载失败时保留凹陷底槽，不闪白。
struct PhotoThumbnailView: View {
    let localID: String
    let targetSize: CGSize
    let thumbnails: ThumbnailProvider
    var cornerRadius: CGFloat = Theme.Radius.card

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.Surface.sunken

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.Shadow.raisedBorder, lineWidth: 1)
        }
        .task(id: localID) {
            image = await thumbnails.image(
                for: localID,
                targetSize: CGSize(
                    width: targetSize.width * UIScreen.main.scale,
                    height: targetSize.height * UIScreen.main.scale
                )
            )
        }
    }
}
