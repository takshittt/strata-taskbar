import AppKit
import SwiftUI

/// Name and icon for a bundle ID, for lists of apps.
struct AppInfo {
    let bundleID: String

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var name: String {
        guard let url else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var icon: NSImage {
        guard let url else { return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AppRow<Trailing: View>: View {
    let bundleID: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let info = AppInfo(bundleID: bundleID)
        HStack {
            Image(nsImage: info.icon).resizable().frame(width: 20, height: 20)
            Text(info.name)
            Spacer()
            trailing
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                Picker("Alignment", selection: $settings.alignment) {
                    ForEach(BarAlignment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Bar height") {
                    Slider(value: $settings.barHeight, in: 28...64, step: 1)
                    Text("\(Int(settings.barHeight)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Text size") {
                    Slider(value: $settings.fontSize, in: 10...16, step: 1)
                    Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Opacity") {
                    Slider(value: $settings.opacity, in: 0.3...1)
                    Text("\(Int(settings.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle("Show window titles", isOn: $settings.showTitles)
            }

            Section("Bar") {
                Picker("Show a bar on", selection: $settings.barScope) {
                    ForEach(BarScope.allCases) { Text($0.title).tag($0) }
                }
                Picker("Each bar shows", selection: $settings.windowScope) {
                    ForEach(WindowScope.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Group windows by app", isOn: $settings.groupByApp)
                Picker("Start button opens", selection: $settings.startAction) {
                    ForEach(StartAction.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                List {
                    ForEach(settings.pinnedBundleIDs, id: \.self) { bundleID in
                        AppRow(bundleID: bundleID) {
                            Button {
                                settings.unpin(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Unpin")
                        }
                    }
                    .onMove { settings.pinnedBundleIDs.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 120)
                Button("Add…", action: addPinnedApp)
            } header: {
                Text("Pinned apps")
            } footer: {
                Text("Drag to reorder.").foregroundStyle(.secondary)
            }

            Section("Hidden apps") {
                if settings.hiddenBundleIDs.isEmpty {
                    Text("No apps are hidden from the bar.").foregroundStyle(.secondary)
                }
                ForEach(settings.hiddenBundleIDs, id: \.self) { bundleID in
                    AppRow(bundleID: bundleID) {
                        Button("Show Again") { settings.unhide(bundleID) }
                    }
                }
            }

            SettingsExtraSections()

            Section("Windows") {
                Toggle("Shrink windows that overlap the bar", isOn: $settings.avoidBarOverlap)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
    }

    private func addPinnedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { settings.pin(bundleID) }
        }
    }
}

/// Sections for features added in later phases (snapping, system integration).
struct SettingsExtraSections: View {
    var body: some View {
        SnappingSection()
    }
}

private struct SnappingSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var hotKeys = HotKeys.shared

    var body: some View {
        Section("Window snapping") {
            Toggle("Enable built-in snap shortcuts", isOn: $settings.hotKeysEnabled)
            LabeledContent("Gap when snapping") {
                Slider(value: $settings.windowGap, in: 0...24, step: 1)
                Text("\(Int(settings.windowGap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            DisclosureGroup("Shortcuts") {
                ForEach(SnapAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        if settings.hotKeysEnabled, hotKeys.unavailable.contains(.snap(action)) {
                            Text("in use elsewhere").font(.caption).foregroundStyle(.orange)
                        }
                        Text(action.defaultShortcut.displayString)
                            .monospaced()
                            .foregroundStyle(settings.hotKeysEnabled ? .primary : .secondary)
                    }
                }
            }
        }
    }
}

/// Settings window. ⌘W closes it even though the app has no visible menu bar.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = KeyCommandWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Strata Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 560, height: 680))
            window.center()
            self.window = window
        }
        WindowActions.activateSelf()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A window that handles ⌘W itself, since an accessory app has no menu bar to route it.
final class KeyCommandWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
