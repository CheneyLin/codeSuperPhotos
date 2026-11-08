import SwiftUI

/// 关于与隐私：版本、数据边界、字体与音效说明、统计重置。
struct AboutView: View {
    @Environment(StatisticsService.self) private var statistics
    @Environment(\.openURL) private var openURL

    @State private var isResetConfirmPresented = false
    @State private var toastMessage: ToastMessage?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("设计语言")
                    Spacer()
                    Text("新拟物 · 明暗双套")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("应用")
            }

            Section {
                Text("照片、保险箱副本、统计与偏好全部保存在本机。App 不发起业务网络请求，不上传照片与元数据。")
                    .font(.footnote)
                Text("系统『最近删除』保留 30 天；保险箱副本的磁盘空间由系统延迟回收。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("隐私与数据")
            }

            Section {
                LabeledContent("界面字体", value: "SF Pro / SF Rounded")
                LabeledContent("字号", value: "随 Dynamic Type 缩放")
                LabeledContent("音效", value: "开关已保留，素材待补")
            } header: {
                Text("字体与音效")
            } footer: {
                Text("音效素材将在后续版本补齐；当前关闭开关会立即静音所有音效调用。")
            }

            Section {
                Button("发送反馈邮件") {
                    openFeedbackMail()
                }
                Text("也可以在 TestFlight 内直接提交反馈与截图。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("反馈")
            }

            Section {
                Button(role: .destructive) {
                    isResetConfirmPresented = true
                } label: {
                    Text("重置统计")
                }
            } header: {
                Text("统计")
            } footer: {
                Text("只清空整理记录与空间估算，不影响照片与保险箱。")
            }
        }
        .navigationTitle("关于与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .alert("重置统计？", isPresented: $isResetConfirmPresented) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                statistics.reset()
                toastMessage = ToastMessage(text: "统计已重置，照片与保险箱不受影响", kind: .warning)
            }
        } message: {
            Text("此操作不可撤销。照片、保险箱副本与清单都不会被删除。")
        }
        .toast($toastMessage, topPadding: 8)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func openFeedbackMail() {
        guard let url = URL(string: "mailto:?subject=SuperPhotos%20%E5%8F%8D%E9%A6%88") else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .environment(StatisticsService())
    }
}
