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

                Section("変換") {
                    Toggle("Live Conversion", isOn: $liveConversionEnabled)

                    Toggle("Space キーで半角スペースを入力", isOn: $usesHalfWidthSpace)

                    LabeledContent("現在の Space") {
                        Text(usesHalfWidthSpace ? "半角" : "全角")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("共有設定") {
                    Text("設定をキーボードへ反映するには、iOS の設定で Sumire Keyboard の「フルアクセスを許可」をオンにしてください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sumire Keyboard")
        }
    }
}

#Preview {
    ContentView()
}
