//
//  ContentView.swift
//  sumire-keyboard
//
//  Created by Kazuma on 2026-04-18.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let keyRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]

    private var keyBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.25, blue: 0.27)
            : .white
    }

    private var functionKeyBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.19, blue: 0.21)
            : Color.gray.opacity(0.2)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Sumire Keyboard")
                .font(.title2.weight(.semibold))

            Text("ダミー表示（入力処理は未実装）")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(keyRows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            Text(key)
                                .font(.headline)
                                .frame(width: 30, height: 42)
                                .background(keyBackground)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("123")
                        .frame(width: 52, height: 42)
                        .background(functionKeyBackground)
                        .cornerRadius(8)

                    Text("space")
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(keyBackground)
                        .cornerRadius(8)

                    Text("return")
                        .frame(width: 72, height: 42)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(14)

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    ContentView()
}
