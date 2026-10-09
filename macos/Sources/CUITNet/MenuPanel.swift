import CUITNetCore
import SwiftUI

/// 点击菜单栏图标弹出的面板。
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    private let updater = Updater.shared

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            primaryAction
            VStack(spacing: 10) {
                SettingRow("自动保持在线", isOn: $model.keepOnline)
                SettingRow("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin },
                                                          set: { model.setLaunchAtLogin($0) }))
            }

            if !model.activity.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.activity.prefix(3)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.date, format: .dateTime.hour().minute())
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            Text(entry.text)
                                .foregroundStyle(entry.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .lineLimit(2)
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()
            HStack {
                Button("设置…") { SettingsWindow.show() }
                Button("日志") { model.openLog() }
                if updater.canCheck {
                    Button("检查更新…") { updater.checkForUpdates() }
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(nsColor: model.status.tint).gradient)
                Image(systemName: model.status.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: model.status.isBusy)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .animation(.smooth, value: model.status)
    }

    private var subtitle: String {
        switch model.status {
        case .rejected(let m), .failed(let m): return m
        case .online, .captive, .noNetwork, .checking, .working:
            return model.username.isEmpty ? "尚未设置账号" : "\(model.username) · \(model.carrier.displayName)"
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if !model.hasAccount {
            Button { SettingsWindow.show() } label: { Text("设置账号").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if model.status == .online {
            Button(role: .destructive) { model.logoutNow() } label: { Text("下线").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        } else {
            Button { model.loginNow() } label: {
                Text(model.status.isBusy ? "请稍候…" : "立即登录").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.status.isBusy)
        }
    }
}

/// 标签靠左、开关靠右的设置行。
private struct SettingRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
