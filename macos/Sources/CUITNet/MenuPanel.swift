import CUITNetCore
import SwiftUI

/// 点击菜单栏图标弹出的面板。
/// 设计取向：克制。没有卡片和大色块，颜色只留给状态图标与错误；层级靠字重、留白和发丝线建立。
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingQuit = false

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusHeader()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            PrimaryAction()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            OptionsGroup()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            ActivitySection()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Hairline()
            Footer(confirmingQuit: $confirmingQuit)
        }
        .frame(width: Self.width)
        .alert("退出 CUIT 校园网？", isPresented: $confirmingQuit) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { NSApp.terminate(nil) }
        } message: {
            Text("退出后不再自动保持在线。")
        }
    }
}

// MARK: - 状态

private struct StatusHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { Color(nsColor: model.status.tint) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(scheme == .dark ? 0.20 : 0.14))
                Image(systemName: model.status.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: model.status.isBusy)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isError ? AnyShapeStyle(PanelTheme.danger(scheme)) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.3), value: model.status)
    }

    private var detail: String {
        switch model.status {
        case .rejected(let m), .failed(let m): return m
        default:
            return model.username.isEmpty ? "尚未设置账号" : "\(model.username) · \(model.carrier.displayName)"
        }
    }

    private var isError: Bool {
        switch model.status { case .rejected, .failed: return true; default: return false }
    }
}

private struct PrimaryAction: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasAccount {
                Button { SettingsWindow.show() } label: { label("设置账号") }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            } else if model.status == .online {
                Button { model.logoutNow() } label: { label("下线") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            } else {
                Button { model.loginNow() } label: { label(model.status.isBusy ? "请稍候…" : "立即登录") }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .disabled(model.status.isBusy)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity)
    }}

// MARK: - 选项

private struct OptionsGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            row("自动保持在线", isOn: $model.keepOnline)
            Hairline().padding(.leading, 12)
            row("登录时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        }
        .background { GroupShape().fill(PanelTheme.groupFill(scheme)) }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5))
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

// MARK: - 最近活动

private struct ActivitySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近活动")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.activity.isEmpty {
                    Button("清空") { model.clearLog() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .help("清空最近活动与日志文件")
                }
            }

            if model.activity.isEmpty {
                Text("暂无记录")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.activity.prefix(4)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(entry.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(entry.isError ? AnyShapeStyle(PanelTheme.danger(scheme)) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - 底栏

private struct Footer: View {
    @Binding var confirmingQuit: Bool
    @Environment(AppModel.self) private var model
    private let updater = Updater.shared

    var body: some View {
        HStack(spacing: 2) {
            Text(updater.version.first?.isNumber == true ? "v\(updater.version)" : updater.version)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            IconButton("doc.text", "打开日志") { model.openLog() }
            if updater.canCheck {
                IconButton("arrow.down.circle", "检查更新…") { updater.checkForUpdates() }
            }
            IconButton("gearshape", "设置…") { SettingsWindow.show() }
            IconButton("power", "退出") { confirmingQuit = true }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 36)
    }
}

private struct IconButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    init(_ systemImage: String, _ title: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(hovering ? Color.primary.opacity(0.07) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 与系统一致：独立的整行按钮用胶囊形（macOS 26 的大号按钮也是胶囊）。
private struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(PanelTheme.groupFill(scheme)))
            }
            .overlay {
                if !prominent {
                    Capsule(style: .continuous).strokeBorder(PanelTheme.separator(scheme), lineWidth: 0.5)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 分组底板的形状。
/// macOS 26 起和系统组件一样用同心圆角：圆角 = 面板圆角 − 与面板边缘的距离，由系统按所在容器自动算出；
/// 老系统没有这套机制，退回固定的连续曲率圆角。
private struct GroupShape: Shape {
    func path(in rect: CGRect) -> Path {
        if #available(macOS 26, *) {
            ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true).path(in: rect)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect)
        }
    }
}

private struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(PanelTheme.separator(scheme)).frame(height: 0.5)
    }
}

enum PanelTheme {
    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.09) : .black.opacity(0.08)
    }

    /// 分组底色：比面板底只深/浅一档。
    static func groupFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.05) : .black.opacity(0.035)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.48, blue: 0.42) : Color(red: 0.76, green: 0.24, blue: 0.20)
    }
}
