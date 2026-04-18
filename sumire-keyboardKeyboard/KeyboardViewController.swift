import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum FlickDirection: Equatable {
        case center
        case left
        case up
        case right
        case down
    }

    private struct KanaKey {
        let label: String
        let candidates: [String]
    }

    private enum KeyAction {
        case kana(KanaKey)
        case transform
        case delete
        case space
        case enter
    }

    private final class KeyboardButton: UIButton {
        let action: KeyAction

        init(title: String, action: KeyAction, style: ButtonStyle) {
            self.action = action
            super.init(frame: .zero)

            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            configuration.baseBackgroundColor = style.backgroundColor
            configuration.baseForegroundColor = style.foregroundColor
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)

            self.configuration = configuration
            titleLabel?.font = style.font
            layer.cornerRadius = 8
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = style.shadowOpacity
            layer.shadowRadius = 1
            layer.shadowOffset = CGSize(width: 0, height: 1)
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            return nil
        }
    }

    private struct ButtonStyle {
        let backgroundColor: UIColor
        let foregroundColor: UIColor
        let font: UIFont
        let shadowOpacity: Float

        static let kana = ButtonStyle(
            backgroundColor: .white,
            foregroundColor: .label,
            font: .systemFont(ofSize: 24, weight: .semibold),
            shadowOpacity: 0.16
        )

        static let function = ButtonStyle(
            backgroundColor: .systemGray3,
            foregroundColor: .label,
            font: .systemFont(ofSize: 17, weight: .semibold),
            shadowOpacity: 0.1
        )

        static let primary = ButtonStyle(
            backgroundColor: .systemBlue,
            foregroundColor: .white,
            font: .systemFont(ofSize: 17, weight: .bold),
            shadowOpacity: 0.12
        )
    }

    private let kanaRows: [[KanaKey]] = [
        [
            KanaKey(label: "あ", candidates: ["あ", "い", "う", "え", "お"]),
            KanaKey(label: "か", candidates: ["か", "き", "く", "け", "こ"]),
            KanaKey(label: "さ", candidates: ["さ", "し", "す", "せ", "そ"])
        ],
        [
            KanaKey(label: "た", candidates: ["た", "ち", "つ", "て", "と"]),
            KanaKey(label: "な", candidates: ["な", "に", "ぬ", "ね", "の"]),
            KanaKey(label: "は", candidates: ["は", "ひ", "ふ", "へ", "ほ"])
        ],
        [
            KanaKey(label: "ま", candidates: ["ま", "み", "む", "め", "も"]),
            KanaKey(label: "や", candidates: ["や", "ゆ", "よ"]),
            KanaKey(label: "ら", candidates: ["ら", "り", "る", "れ", "ろ"])
        ],
        [
            KanaKey(label: "゛゜小", candidates: []),
            KanaKey(label: "わ", candidates: ["わ", "を", "ん", "ー"]),
            KanaKey(label: "、。?!", candidates: ["、", "。", "？", "！"])
        ]
    ]

    private var activeKeyLabel: String?
    private var activeCandidateIndex = 0
    private var lastInsertedText = ""
    private var lastInputDate: Date?
    private let multiTapInterval: TimeInterval = 1.1
    private let flickThreshold: CGFloat = 22
    private var suppressNextButtonRelease = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray5
        setupKeyboardLayout()
    }

    private func setupKeyboardLayout() {
        let rootStack = UIStackView()
        rootStack.axis = .horizontal
        rootStack.alignment = .fill
        rootStack.distribution = .fill
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let kanaGrid = makeKanaGrid()
        let controlColumn = makeControlColumn()

        rootStack.addArrangedSubview(kanaGrid)
        rootStack.addArrangedSubview(controlColumn)
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 252),

            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            controlColumn.widthAnchor.constraint(equalTo: kanaGrid.widthAnchor, multiplier: 0.28)
        ])
    }

    private func makeKanaGrid() -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.alignment = .fill
        grid.distribution = .fillEqually
        grid.spacing = 6

        for row in kanaRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6

            for key in row {
                let action: KeyAction = key.candidates.isEmpty ? .transform : .kana(key)
                let button = KeyboardButton(title: key.label, action: action, style: .kana)
                button.addTarget(self, action: #selector(handleKeyRelease(_:event:)), for: [.touchUpInside, .touchUpOutside])
                rowStack.addArrangedSubview(button)
            }

            grid.addArrangedSubview(rowStack)
        }

        return grid
    }

    private func makeControlColumn() -> UIStackView {
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .fill
        column.distribution = .fillEqually
        column.spacing = 6

        let controls: [(String, KeyAction, ButtonStyle)] = [
            ("⌫", .delete, .function),
            ("空白", .space, .function),
            ("Enter", .enter, .primary)
        ]

        for control in controls {
            let button = KeyboardButton(title: control.0, action: control.1, style: control.2)
            button.addTarget(self, action: #selector(handleKeyRelease(_:event:)), for: [.touchUpInside, .touchUpOutside])
            if case .enter = control.1 {
                button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleEnterLongPress(_:))))
            }
            column.addArrangedSubview(button)
        }

        return column
    }

    @objc private func handleKeyRelease(_ sender: KeyboardButton, event: UIEvent) {
        if suppressNextButtonRelease {
            suppressNextButtonRelease = false
            return
        }

        let direction = flickDirection(for: sender, event: event)
        switch sender.action {
        case .kana(let key):
            insertCandidate(for: key, direction: direction)
        case .transform:
            transformPreviousCharacter()
        case .delete:
            resetMultiTapState()
            textDocumentProxy.deleteBackward()
        case .space:
            resetMultiTapState()
            textDocumentProxy.insertText(" ")
        case .enter:
            resetMultiTapState()
            textDocumentProxy.insertText("\n")
        }
    }

    @objc private func handleEnterLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }

        suppressNextButtonRelease = true
        resetMultiTapState()
        advanceToNextInputMode()
    }

    private func flickDirection(for button: KeyboardButton, event: UIEvent) -> FlickDirection {
        guard let touch = event.allTouches?.first else {
            return .center
        }

        let location = touch.location(in: button)
        let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        let delta = CGPoint(x: location.x - center.x, y: location.y - center.y)

        guard max(abs(delta.x), abs(delta.y)) >= flickThreshold else {
            return .center
        }

        if abs(delta.x) > abs(delta.y) {
            return delta.x < 0 ? .left : .right
        }

        return delta.y < 0 ? .up : .down
    }

    private func insertCandidate(for key: KanaKey, direction: FlickDirection) {
        guard !key.candidates.isEmpty else {
            return
        }

        if direction != .center, let text = flickCandidate(for: key, direction: direction) {
            resetMultiTapState()
            textDocumentProxy.insertText(text)
            return
        }

        let now = Date()
        let shouldCycle = activeKeyLabel == key.label
            && lastInsertedText.isEmpty == false
            && lastInputDate.map { now.timeIntervalSince($0) <= multiTapInterval } == true

        if shouldCycle {
            activeCandidateIndex = (activeCandidateIndex + 1) % key.candidates.count
            textDocumentProxy.deleteBackward()
        } else {
            activeKeyLabel = key.label
            activeCandidateIndex = 0
        }

        let text = key.candidates[activeCandidateIndex]
        textDocumentProxy.insertText(text)
        lastInsertedText = text
        lastInputDate = now
    }

    private func flickCandidate(for key: KanaKey, direction: FlickDirection) -> String? {
        switch key.label {
        case "や":
            switch direction {
            case .center:
                return "や"
            case .left:
                return "「"
            case .up:
                return "ゆ"
            case .right:
                return "」"
            case .down:
                return "よ"
            }
        case "わ":
            switch direction {
            case .center:
                return "わ"
            case .left:
                return "を"
            case .up:
                return "ん"
            case .right:
                return "ー"
            case .down:
                return "〜"
            }
        case "、。?!":
            switch direction {
            case .center:
                return "、"
            case .left:
                return "。"
            case .up:
                return "？"
            case .right:
                return "！"
            case .down:
                return "…"
            }
        default:
            guard key.candidates.count >= 5 else {
                return nil
            }

            switch direction {
            case .center:
                return key.candidates[0]
            case .left:
                return key.candidates[1]
            case .up:
                return key.candidates[2]
            case .right:
                return key.candidates[3]
            case .down:
                return key.candidates[4]
            }
        }
    }

    private func transformPreviousCharacter() {
        resetMultiTapState()

        guard let previousCharacter = textDocumentProxy.documentContextBeforeInput?.last,
              let transformedCharacter = transformedCharacter(after: previousCharacter) else {
            return
        }

        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(String(transformedCharacter))
    }

    private func transformedCharacter(after character: Character) -> Character? {
        let cycles: [[Character]] = [
            ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ"], ["え", "ぇ"], ["お", "ぉ"],
            ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["つ", "っ", "づ"], ["わ", "ゎ"],
            ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
            ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
            ["た", "だ"], ["ち", "ぢ"], ["て", "で"], ["と", "ど"],
            ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"],
            ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
            ["カ", "ガ"], ["キ", "ギ"], ["ク", "グ"], ["ケ", "ゲ"], ["コ", "ゴ"],
            ["サ", "ザ"], ["シ", "ジ"], ["ス", "ズ"], ["セ", "ゼ"], ["ソ", "ゾ"],
            ["タ", "ダ"], ["チ", "ヂ"], ["ツ", "ヅ"], ["テ", "デ"], ["ト", "ド"],
            ["ハ", "バ", "パ"], ["ヒ", "ビ", "ピ"], ["フ", "ブ", "プ"],
            ["ヘ", "ベ", "ペ"], ["ホ", "ボ", "ポ"]
        ]

        guard let cycle = cycles.first(where: { $0.contains(character) }),
              let index = cycle.firstIndex(of: character) else {
            return nil
        }

        return cycle[(index + 1) % cycle.count]
    }

    private func resetMultiTapState() {
        activeKeyLabel = nil
        activeCandidateIndex = 0
        lastInsertedText = ""
        lastInputDate = nil
    }
}
