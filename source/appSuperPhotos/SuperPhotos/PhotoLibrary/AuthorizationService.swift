import Photos
import PhotosUI
import UIKit

enum LibraryAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied

    var canBrowse: Bool {
        self == .authorized || self == .limited
    }

    init(status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// 授权状态的唯一入口。
@MainActor
final class AuthorizationService {
    func currentState() -> LibraryAccessState {
        LibraryAccessState(status: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> LibraryAccessState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return LibraryAccessState(status: status)
    }

    func presentLimitedLibraryPicker(from viewController: UIViewController? = nil) {
        guard let host = viewController ?? Self.keyWindowRootController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: host)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func keyWindowRootController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
