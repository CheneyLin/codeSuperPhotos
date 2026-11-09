import AVFoundation
import Foundation
import Observation

/// 音效入口：本地短素材 + AVAudioPlayer 预加载。
/// 使用 `.ambient` 会话，跟随静音键，不打断其他 App 的音频。
@MainActor
@Observable
final class SoundService {
    enum Event {
        case destroyStart
        case destroyFinish
        case vaultImport
        case vaultRestore
        /// 照片落进纸篓的揉纸声。
        case paperCrunch

        var resourceName: String {
            switch self {
            case .destroyStart: "destroy_start"
            case .destroyFinish: "destroy_finish"
            case .vaultImport, .vaultRestore: "vault_import"
            case .paperCrunch: "paper_crunch"
            }
        }
    }

    /// 由 AppSettings.soundEnabled 同步；关闭时所有播放直接返回。
    var isEnabled = true

    @ObservationIgnored private var players: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var didConfigureSession = false

    func play(_ event: Event) {
        guard isEnabled else { return }
        guard let player = player(for: event.resourceName) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for name: String) -> AVAudioPlayer? {
        if let cached = players[name] { return cached }
        guard let url = Self.resourceURL(name: name) else {
            assertionFailure("缺少音效素材：\(name).wav")
            return nil
        }

        configureSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.7
        player.prepareToPlay()
        players[name] = player
        return player
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func resourceURL(name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
    }
}
