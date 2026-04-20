//
//  ContentView.swift
//  sumire-keyboard
//
//  Created by Kazuma on 2026-04-18.
//

import SwiftUI

struct ContentView: View {
    @AppStorage(
        KeyboardSettings.Keys.japaneseFlickInputMode,
        store: KeyboardSettings.defaults
    )
    private var japaneseFlickInputModeRawValue = KeyboardSettings.JapaneseFlickInputMode.toggle.rawValue

    @AppStorage(
        KeyboardSettings.Keys.liveConversionEnabled,
        store: KeyboardSettings.defaults
    )
    private var liveConversionEnabled = true

    @AppStorage(
        KeyboardSettings.Keys.usesHalfWidthSpace,
        store: KeyboardSettings.defaults
    )
    private var usesHalfWidthSpace = false

    @State private var keyboards: [KeyboardSettings.SumireKeyboard] = []
    @State private var currentKeyboardID = ""
    @State private var keyboardEditorRoute: KeyboardEditorRoute?

    private var japaneseFlickInputMode: Binding<KeyboardSettings.JapaneseFlickInputMode> {
        Binding(
            get: {
                KeyboardSettings.JapaneseFlickInputMode(
                    rawValue: japaneseFlickInputModeRawValue
                ) ?? .toggle
            },
            set: { nextMode in
                japaneseFlickInputModeRawValue = nextMode.rawValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                keyboardListSection
                japaneseFlickSection
                conversionSection
                sharedSettingsSection
            }
            .navigationTitle("Sumire Keyboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        keyboardEditorRoute = .add
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("キーボードを追加")
                }
            }
            .sheet(item: $keyboardEditorRoute) { route in
                KeyboardEditorView(route: route) {
                    reloadKeyboards()
                }
            }
            .onAppear {
                reloadKeyboards()
            }
        }
    }

    private var keyboardListSection: some View {
        Section("キーボード一覧") {
            if keyboards.isEmpty {
                Text("日本語 Flick")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keyboards) { keyboard in
                    Button {
                        keyboardEditorRoute = .edit(keyboard)
                    } label: {
                        KeyboardRow(
                            keyboard: keyboard,
                            isCurrent: keyboard.id == currentKeyboardID,
                            canDelete: keyboards.count > 1
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: keyboards.count > 1) {
                        if keyboards.count > 1 {
                            Button("削除", role: .destructive) {
                                deleteKeyboard(keyboard)
                            }
                        }
                    }
                }
            }

            Button {
                keyboardEditorRoute = .add
            } label: {
                Label("キーボードを追加", systemImage: "plus")
            }

            Text("キーボードは常に 1 件以上必要です。1 件だけの場合は削除できません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var japaneseFlickSection: some View {
        Section("日本語 Flick") {
            Picker("入力モード", selection: japaneseFlickInputMode) {
                ForEach(KeyboardSettings.JapaneseFlickInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("フリックモードでは、同じキーの連打で「あ」から「い」へ進む Toggle 入力を無効にします。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var conversionSection: some View {
        Section("変換") {
            Toggle("Live Conversion", isOn: $liveConversionEnabled)

            Toggle("Space キーで半角スペースを入力", isOn: $usesHalfWidthSpace)

            LabeledContent("現在の Space") {
                Text(usesHalfWidthSpace ? "半角" : "全角")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sharedSettingsSection: some View {
        Section("共有設定") {
            Text("設定をキーボードへ反映するには、iOS の設定で Sumire Keyboard の「フルアクセスを許可」をオンにしてください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func reloadKeyboards() {
        keyboards = KeyboardSettings.keyboards
        currentKeyboardID = KeyboardSettings.currentKeyboardID
    }

    private func deleteKeyboard(_ keyboard: KeyboardSettings.SumireKeyboard) {
        guard KeyboardSettings.deleteKeyboard(id: keyboard.id) else {
            return
        }
        reloadKeyboards()
    }
}

private struct KeyboardRow: View {
    let keyboard: KeyboardSettings.SumireKeyboard
    let isCurrent: Bool
    let canDelete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(keyboard.name)
                        .foregroundStyle(.primary)

                    if isCurrent {
                        Text("使用中")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Text(keyboard.displayKind)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if canDelete == false {
                Text("削除不可")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private var iconName: String {
        switch keyboard.kind {
        case .japaneseFlick:
            return "rectangle.grid.3x2"
        case .qwerty:
            return "keyboard"
        }
    }
}

private enum KeyboardEditorRoute: Identifiable {
    case add
    case edit(KeyboardSettings.SumireKeyboard)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let keyboard):
            return keyboard.id
        }
    }

    var title: String {
        switch self {
        case .add:
            return "キーボードを追加"
        case .edit:
            return "キーボードを編集"
        }
    }
}

private struct KeyboardEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let route: KeyboardEditorRoute
    let onChange: () -> Void

    @State private var name: String
    @State private var kind: KeyboardSettings.KeyboardKind
    @State private var qwertyLanguage: KeyboardSettings.QWERTYLanguage

    init(route: KeyboardEditorRoute, onChange: @escaping () -> Void) {
        self.route = route
        self.onChange = onChange

        switch route {
        case .add:
            _name = State(initialValue: KeyboardSettings.defaultKeyboardName(kind: .qwerty, qwertyLanguage: .japanese))
            _kind = State(initialValue: .qwerty)
            _qwertyLanguage = State(initialValue: .japanese)
        case .edit(let keyboard):
            _name = State(initialValue: keyboard.name)
            _kind = State(initialValue: keyboard.kind)
            _qwertyLanguage = State(initialValue: keyboard.qwertyLanguage ?? .japanese)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("キーボード名", text: $name)
                }

                Section("種類") {
                    Picker("キーボード", selection: $kind) {
                        ForEach(KeyboardSettings.KeyboardKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    if kind == .qwerty {
                        Picker("QWERTY モード", selection: $qwertyLanguage) {
                            ForEach(KeyboardSettings.QWERTYLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }
                    }
                }

                if case .edit(let keyboard) = route {
                    Section {
                        Button("このキーボードを使用") {
                            KeyboardSettings.currentKeyboardID = keyboard.id
                            onChange()
                            dismiss()
                        }

                        Button("削除", role: .destructive) {
                            guard KeyboardSettings.deleteKeyboard(id: keyboard.id) else {
                                return
                            }
                            onChange()
                            dismiss()
                        }
                        .disabled(KeyboardSettings.canDeleteKeyboard(id: keyboard.id) == false)
                    } footer: {
                        if KeyboardSettings.canDeleteKeyboard(id: keyboard.id) == false {
                            Text("キーボードが 1 件だけの場合は削除できません。")
                        }
                    }
                }
            }
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let keyboardName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch route {
        case .add:
            KeyboardSettings.addKeyboard(
                name: keyboardName,
                kind: kind,
                qwertyLanguage: kind == .qwerty ? qwertyLanguage : nil
            )
        case .edit(let keyboard):
            var updatedKeyboard = keyboard
            updatedKeyboard.name = keyboardName
            updatedKeyboard.kind = kind
            updatedKeyboard.qwertyLanguage = kind == .qwerty ? qwertyLanguage : nil
            KeyboardSettings.updateKeyboard(updatedKeyboard)
        }

        onChange()
        dismiss()
    }
}

#Preview {
    ContentView()
}
