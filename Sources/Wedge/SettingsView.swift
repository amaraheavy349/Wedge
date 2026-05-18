import SwiftUI
import ServiceManagement
import AppKit

enum LanguageOption: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System default"
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    var storageValue: String? {
        self == .system ? nil : rawValue
    }

    static func from(_ stored: String?) -> LanguageOption {
        switch stored {
        case "en": return .english
        case "ru": return .russian
        default:   return .system
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var hasSavedPassword: Bool

    @Published var dimDisplayOnLidClose: Bool {
        didSet { Preferences.dimDisplayOnLidClose = dimDisplayOnLidClose }
    }

    @Published var language: LanguageOption {
        didSet {
            guard language != LanguageOption.from(Preferences.preferredLanguage) else { return }
            Preferences.preferredLanguage = language.storageValue
            promptRestart()
        }
    }

    var brightnessAvailable: Bool { BrightnessController.isAvailable }

    init() {
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        self.hasSavedPassword = (KeychainStore.load() != nil)
        self.dimDisplayOnLidClose = Preferences.dimDisplayOnLidClose
        self.language = LanguageOption.from(Preferences.preferredLanguage)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let currentlyEnabled = (SMAppService.mainApp.status == .enabled)
        if enabled == currentlyEnabled {
            launchAtLogin = currentlyEnabled
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    func forgetPassword() {
        KeychainStore.delete()
        hasSavedPassword = false
    }

    func refresh() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        hasSavedPassword = (KeychainStore.load() != nil)
        dimDisplayOnLidClose = Preferences.dimDisplayOnLidClose
        language = LanguageOption.from(Preferences.preferredLanguage)
    }

    private func promptRestart() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Restart to apply language")
        alert.informativeText = L10n.tr("Wedge will close and reopen with the new language.")
        alert.addButton(withTitle: L10n.tr("Restart now"))
        alert.addButton(withTitle: L10n.tr("Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Self.relaunch()
        }
    }

    private static func relaunch() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    private var version: String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "?"
        let build = dict?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Launch Wedge at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))

                Toggle(isOn: $model.dimDisplayOnLidClose) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn off internal display when lid closes")
                        Text("Saves battery while Wedge keeps the Mac awake.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.brightnessAvailable)

                LabeledContent("Saved password") {
                    HStack(spacing: 8) {
                        Text(model.hasSavedPassword ? "Stored in Keychain" : "Not stored")
                            .foregroundStyle(.secondary)
                        if model.hasSavedPassword {
                            Button("Forget", role: .destructive) {
                                model.forgetPassword()
                            }
                        }
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: $model.language) {
                    ForEach(LanguageOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Source") {
                    Link("github.com/wwaannttyy/Wedge",
                         destination: URL(string: "https://github.com/wwaannttyy/Wedge")!)
                }
                Text("Wedge holds your Mac awake by toggling pmset disablesleep. It needs your admin password the first time you use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        .onAppear { model.refresh() }
    }
}
