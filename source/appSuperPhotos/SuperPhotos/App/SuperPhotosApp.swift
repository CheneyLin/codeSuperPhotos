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
        }
    }
}
