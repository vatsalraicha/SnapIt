import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            HotkeysPreferencesView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(1)

            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(2)

            AdvancedPreferencesView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(3)

            UploadPreferencesView()
                .tabItem { Label("Upload", systemImage: "icloud.and.arrow.up") }
                .tag(4)
        }
        .frame(width: 660, height: 430)
        .padding()
    }
}

// MARK: - General Tab

struct GeneralPreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)

            HStack {
                Text("Save folder:")
                Text(prefs.defaultSaveFolder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Choose...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        prefs.defaultSaveFolder = url.path
                    }
                }
            }

            Toggle("Auto-save screenshots", isOn: $prefs.autoSave)
            Toggle("Auto-copy to clipboard", isOn: $prefs.autoCopyToClipboard)

            Picker("Esc key behavior:", selection: $prefs.escBehavior) {
                ForEach(EscBehavior.allCases) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
        }
        .padding()
    }
}

// MARK: - Hotkeys Tab

struct HotkeysPreferencesView: View {
    var body: some View {
        Form {
            Section {
                ForEach(CaptureHotkey.allCases, id: \.rawValue) { hotkey in
                    HStack {
                        Text(hotkey.displayName)
                        Spacer()
                        HotkeyRecorderView(hotkey: hotkey)
                            .frame(width: 150)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Appearance Tab

struct AppearancePreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Picker("Window capture shadow:", selection: $prefs.windowShadowMode) {
                ForEach(WindowShadowMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle("Fit to window on open", isOn: $prefs.defaultZoomFit)

            HStack {
                Text("Default annotation color:")
                ColorPicker("", selection: annotationColorBinding)
                    .labelsHidden()
            }
        }
        .padding()
    }

    private var annotationColorBinding: Binding<Color> {
        Binding(
            get: {
                if let nsColor = NSColor(hex: prefs.annotationColor) {
                    return Color(nsColor)
                }
                return .red
            },
            set: { newColor in
                let nsColor = NSColor(newColor)
                prefs.annotationColor = nsColor.hexString
            }
        )
    }
}

// MARK: - Advanced Tab

struct AdvancedPreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    private let allLanguages = [
        ("en-US", "English"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
        ("pt-BR", "Portuguese"),
        ("ru", "Russian"),
        ("uk", "Ukrainian"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]

    var body: some View {
        Form {
            Section("OCR Languages") {
                ForEach(allLanguages, id: \.0) { code, name in
                    Toggle(name, isOn: Binding(
                        get: { prefs.ocrLanguages.contains(code) },
                        set: { isOn in
                            if isOn {
                                prefs.ocrLanguages.append(code)
                            } else {
                                prefs.ocrLanguages.removeAll { $0 == code }
                            }
                        }
                    ))
                }
            }

            Picker("Color format:", selection: $prefs.colorFormat) {
                ForEach(ColorFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            Toggle("Use physical pixels (Retina)", isOn: $prefs.usePhysicalPixels)
            Toggle("Strip line breaks in OCR output", isOn: $prefs.stripLineBreaks)
        }
        .padding()
    }
}

// MARK: - Upload Tab

struct UploadPreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Section("S3-Compatible Storage") {
                TextField("Endpoint URL:", text: $prefs.s3Endpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Bucket:", text: $prefs.s3Bucket)
                    .textFieldStyle(.roundedBorder)
                TextField("Access Key:", text: $prefs.s3AccessKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret Key:", text: $prefs.s3SecretKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Region:", text: $prefs.s3Region)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Supports AWS S3, MinIO, Backblaze B2, and other S3-compatible services.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
