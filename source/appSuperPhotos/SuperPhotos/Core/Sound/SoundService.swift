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
        /// 照片落进废纸篓的揉纸声（保留给旧调用点 / 兜底）。
        case paperCrunch
        /// 轻点底部道具循环切换时的 UI 提示音。
        case deviceSwitch
        /// 照片落入当前道具时的专属音效。
        case deviceDrop(MachineKind)

        var resourceName: String {
            switch self {
            case .destroyStart: "destroy_start"
            case .destroyFinish: "destroy_finish"
            case .vaultImport, .vaultRestore: "vault_import"
            case .paperCrunch: "paper_crunch"
            case .deviceSwitch: "device_switch"
            case .deviceDrop(let machine): machine.soundName
            }
        }

        /// 切换提示比业务音效轻一档，连点时不刺耳。
        var volume: Float {
            self.isDeviceSwitch ? 0.45 : 0.7
        }

        var isDeviceSwitch: Bool {
            if case .deviceSwitch = self { return true }
            return false
        }
    }

    /// 由 AppSettings.soundEnabled 同步；关闭时所有播放直接返回。
    var isEnabled = true

    @ObservationIgnored private var players: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var didConfigureSession = false

    func play(_ event: Event) {
        guard isEnabled else { return }
        guard let player = player(for: event) else { return }
        player.currentTime = 0
        player.play()
    }

    /// 语义化入口：照片落入当前道具时调用。
    func play(device: MachineKind) {
        play(.deviceDrop(device))
    }

    private func player(for event: Event) -> AVAudioPlayer? {
        let name = event.resourceName
        if let cached = players[name] { return cached }

        // 五款道具素材是后加的，任何一份缺失都不能让整理流程崩在断言上：
        // 先退回通用揉纸声，再退回静音。
        var url = Self.resourceURL(name: name)
        if url == nil, case .deviceDrop = event {
            url = Self.resourceURL(name: "paper_crunch")
        }
        guard let resolvedURL = url else { return nil }

        configureSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: resolvedURL) else { return nil }
        player.volume = event.volume
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
