import CUITNetCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""
    @State private var carrier: Carrier = .cmcc
    @State private var portal = ""
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("CUIT 校园网").font(.title2.bold())
                Text("连上校园网后自动完成认证，掉线自动重连")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 8)

            Form {
                Section {
                    TextField("学号", text: $username, prompt: Text("例如 2023xxxxxx"))
                        .textContentType(.username)
                    SecureField("密码", text: $password, prompt: Text("统一身份认证密码"))
                        .textContentType(.password)
                    Picker("运营商", selection: $carrier) {
                        ForEach(Carrier.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("密码保存在「钥匙串」中，只会发送给学校的认证服务器。")
                        .foregroundStyle(.secondary)
                }

                Section("高级") {
                    TextField("认证服务器", text: $portal)
                    LabeledContent("接入设备", value: model.nasIP.isEmpty ? "首次登录后自动识别" : model.nasIP)
                    Button("打开自助服务中心") { model.openSelfService() }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
                Button("保存并登录", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty
                              || (password.isEmpty && !model.hasAccount))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 545)
        .onAppear {
            username = model.username
            password = model.password()
            carrier = model.carrier
            portal = model.portal
        }
    }

    private func save() {
        error = nil
        guard URL(string: portal)?.host != nil else {
            error = "认证服务器地址不正确"
            return
        }
        do {
            model.portal = portal
            try model.saveAccount(username: username, password: password, carrier: carrier)
            saved = true
            model.loginNow()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
