import SwiftUI

@main
struct SuperPhotosApp: App {
    @State private var entitlements = EntitlementStore()
    @State private var vault = VaultStore()
    @State private var settings = AppSettings()
    @State private var statistics = StatisticsService()
    @State private var sound = SoundService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // DuoGate：iOS 27.1+ 注入铰链姿态与布局快照，低版本 / 非 Duo 设备
            // 直接渲染原布局（duoInfo 恒为 .notDuo），当前页面不读它、行为零变化。
            DuoGate {
                ZStack {
                    HomeView()
                        .environment(entitlements)
                        .environment(vault)
                        .environment(settings)
                        .environment(statistics)
                        .environment(sound)

                    if scenePhase != .active {
                        VaultPrivacyShield()
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
                .modifier(SettingsEnvironmentModifier(settings: settings))
                .preferredColorScheme(settings.preferredColorScheme)
                .background {
                    WindowTraitConfigurator(highContrast: settings.highContrast)
                }
                .animation(.easeOut(duration: 0.12), value: scenePhase)
                .onAppear {
                    sound.isEnabled = settings.soundEnabled
                }
                .onChange(of: settings.soundEnabled) { _, enabled in
                    sound.isEnabled = enabled
                }
                .onChange(of: scenePhase) { _, newPhase in
                    vault.handleScenePhase(newPhase)
                }
                // DEBUG 只读 HUD，默认不渲染；Release 下是 EmptyView。
                .overlay(alignment: .topTrailing) {
                    DuoDiagnosticsHUD()
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
        }
    }
}
