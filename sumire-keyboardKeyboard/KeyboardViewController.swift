import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum FlickDirection: Hashable {
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
        case moveLeft
        case moveRight
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

    private final class CandidateButton: UIButton {
        var committedText: String?

        init() {
            super.init(frame: .zero)

            var configuration = UIButton.Configuration.filled()
            configuration.title = "候補"
            configuration.baseBackgroundColor = .white
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .medium
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            self.configuration = configuration
            titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            titleLabel?.adjustsFontSizeToFitWidth = true
            titleLabel?.minimumScaleFactor = 0.72
            titleLabel?.numberOfLines = 1
            titleLabel?.lineBreakMode = .byTruncatingTail
            setContentHuggingPriority(.required, for: .horizontal)
            setContentCompressionResistancePriority(.required, for: .horizontal)
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func configure(title: String, committedText: String?, isEnabled: Bool) {
            self.committedText = committedText
            self.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.55

            var newConfiguration = self.configuration
            newConfiguration?.title = title
            newConfiguration?.baseForegroundColor = isEnabled ? .label : .secondaryLabel
            newConfiguration?.titleLineBreakMode = .byTruncatingTail
            self.configuration = newConfiguration
            titleLabel?.numberOfLines = 1
            titleLabel?.lineBreakMode = .byTruncatingTail
        }
    }

    private final class FlickGuideView: UIView {
        private let labelSize = CGSize(width: 44, height: 36)
        private var labels: [FlickDirection: UILabel] = [:]
        private(set) var showsAllDirections = false

        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .clear
            isUserInteractionEnabled = false

            for direction in [FlickDirection.left, .up, .right, .down, .center] {
                let label = UILabel()
                label.textAlignment = .center
                label.font = .systemFont(ofSize: 20, weight: .bold)
                label.textColor = .white
                label.backgroundColor = UIColor.black.withAlphaComponent(0.78)
                label.layer.cornerRadius = 8
                label.layer.masksToBounds = true
                addSubview(label)
                labels[direction] = label
            }
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func configure(candidates: [FlickDirection: String], selectedDirection: FlickDirection, showsAllDirections: Bool) {
            self.showsAllDirections = showsAllDirections

            for (direction, label) in labels {
                label.text = candidates[direction]
                let shouldShow = showsAllDirections || direction == .center || direction == selectedDirection
                label.isHidden = candidates[direction] == nil || !shouldShow
                label.backgroundColor = direction == selectedDirection
                    ? UIColor.systemBlue.withAlphaComponent(0.9)
                    : UIColor.black.withAlphaComponent(0.78)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            labels[.center]?.frame = CGRect(
                x: center.x - (labelSize.width / 2),
                y: center.y - (labelSize.height / 2),
                width: labelSize.width,
                height: labelSize.height
            )
            labels[.left]?.frame = CGRect(
                x: center.x - labelSize.width - 10,
                y: center.y - (labelSize.height / 2),
                width: labelSize.width,
                height: labelSize.height
            )
            labels[.up]?.frame = CGRect(
                x: center.x - (labelSize.width / 2),
                y: center.y - labelSize.height - 10,
                width: labelSize.width,
                height: labelSize.height
            )
            labels[.right]?.frame = CGRect(
                x: center.x + 10,
                y: center.y - (labelSize.height / 2),
                width: labelSize.width,
                height: labelSize.height
            )
            labels[.down]?.frame = CGRect(
                x: center.x - (labelSize.width / 2),
                y: center.y + 10,
                width: labelSize.width,
                height: labelSize.height
            )
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
    private var composingText = ""
    private var renderedComposingText = ""
    private var conversionRange: Range<Int> = 0..<0
    private var underlineRange: Range<Int>?
    private var kanaKanjiConverter: KanaKanjiConverter?
    private var converterLoadFailureMessage: String?
    private var isLoadingKanaKanjiConverter = false
    private var candidateButtons: [CandidateButton] = []
    private let candidateScrollView = UIScrollView()
    private let candidateStack = UIStackView()
    private let flickGuideView = FlickGuideView()
    private let conversionCandidateLimit = 40
    private let conversionBeamWidth = 20
    private let multiTapInterval: TimeInterval = 1.1
    private let flickThreshold: CGFloat = 22
    private var suppressNextButtonRelease = false
    private var deleteRepeatTimer: Timer?
    private var scheduledKanaKanjiLoad: DispatchWorkItem?
    private var kanaKanjiLoadGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray5
        setupKeyboardLayout()
        updatePreedit()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleKanaKanjiConverterLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scheduledKanaKanjiLoad?.cancel()
        scheduledKanaKanjiLoad = nil
        stopDeleteRepeat()
        commitRenderedComposingTextAsTyped()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        scheduledKanaKanjiLoad?.cancel()
        scheduledKanaKanjiLoad = nil
        kanaKanjiLoadGeneration += 1
        isLoadingKanaKanjiConverter = false
        kanaKanjiConverter = nil
        converterLoadFailureMessage = nil
        updatePreedit()
    }

    private func setupKeyboardLayout() {
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.distribution = .fill
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let candidateBar = makeCandidateBar()
        let keyboardStack = UIStackView()
        keyboardStack.axis = .horizontal
        keyboardStack.alignment = .fill
        keyboardStack.distribution = .fill
        keyboardStack.spacing = 6

        let kanaGrid = makeKanaGrid()
        let controlColumn = makeControlColumn()

        keyboardStack.addArrangedSubview(kanaGrid)
        keyboardStack.addArrangedSubview(controlColumn)
        contentStack.addArrangedSubview(candidateBar)
        contentStack.addArrangedSubview(keyboardStack)
        view.addSubview(contentStack)
        view.addSubview(flickGuideView)
        flickGuideView.isHidden = true

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 292),

            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            candidateBar.heightAnchor.constraint(equalToConstant: 38),
            controlColumn.widthAnchor.constraint(equalTo: kanaGrid.widthAnchor, multiplier: 0.28)
        ])
    }

    private func makeCandidateBar() -> UIView {
        candidateScrollView.showsHorizontalScrollIndicator = true
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.backgroundColor = .clear
        candidateScrollView.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.distribution = .fill
        candidateStack.spacing = 6
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScrollView.addSubview(candidateStack)

        NSLayoutConstraint.activate([
            candidateStack.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor)
        ])

        return candidateScrollView
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
                configureInputTargets(for: button)
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
        column.distribution = .fill
        column.spacing = 6

        var buttons: [KeyboardButton] = []

        let deleteButton = KeyboardButton(title: "⌫", action: .delete, style: .function)
        configureInputTargets(for: deleteButton)
        let deleteLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteLongPress(_:)))
        deleteLongPress.minimumPressDuration = 0.35
        deleteLongPress.cancelsTouchesInView = false
        deleteButton.addGestureRecognizer(deleteLongPress)
        column.addArrangedSubview(deleteButton)
        buttons.append(deleteButton)

        let arrowRow = UIStackView()
        arrowRow.axis = .horizontal
        arrowRow.alignment = .fill
        arrowRow.distribution = .fillEqually
        arrowRow.spacing = 6

        let leftButton = KeyboardButton(title: "←", action: .moveLeft, style: .function)
        let rightButton = KeyboardButton(title: "→", action: .moveRight, style: .function)
        configureInputTargets(for: leftButton)
        configureInputTargets(for: rightButton)
        arrowRow.addArrangedSubview(leftButton)
        arrowRow.addArrangedSubview(rightButton)
        column.addArrangedSubview(arrowRow)

        let spaceButton = KeyboardButton(title: "空白", action: .space, style: .function)
        configureInputTargets(for: spaceButton)
        column.addArrangedSubview(spaceButton)
        buttons.append(spaceButton)

        let enterButton = KeyboardButton(title: "Enter", action: .enter, style: .primary)
        configureInputTargets(for: enterButton)
        let enterLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleEnterLongPress(_:)))
        enterLongPress.minimumPressDuration = 0.45
        enterButton.addGestureRecognizer(enterLongPress)
        column.addArrangedSubview(enterButton)
        buttons.append(enterButton)

        NSLayoutConstraint.activate([
            arrowRow.heightAnchor.constraint(equalTo: deleteButton.heightAnchor)
        ])

        if buttons.count == 3 {
            NSLayoutConstraint.activate([
                buttons[1].heightAnchor.constraint(equalTo: buttons[0].heightAnchor),
                buttons[2].heightAnchor.constraint(equalTo: buttons[0].heightAnchor, multiplier: 2)
            ])
        }

        return column
    }

    private func configureInputTargets(for button: KeyboardButton) {
        button.addTarget(self, action: #selector(handleTouchDown(_:event:)), for: .touchDown)
        button.addTarget(self, action: #selector(handleTouchDrag(_:event:)), for: [.touchDragInside, .touchDragOutside])
        button.addTarget(self, action: #selector(handleKeyRelease(_:event:)), for: [.touchUpInside, .touchUpOutside])
        button.addTarget(self, action: #selector(handleTouchCancel(_:)), for: .touchCancel)

        if case .kana = button.action {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleKanaLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            button.addGestureRecognizer(longPress)
        }
    }

    @objc private func handleTouchDown(_ sender: KeyboardButton, event: UIEvent) {
        guard case .kana(let key) = sender.action else {
            return
        }

        showFlickGuide(for: key, from: sender, selectedDirection: .center, showsAllDirections: false)
    }

    @objc private func handleTouchDrag(_ sender: KeyboardButton, event: UIEvent) {
        guard case .kana(let key) = sender.action else {
            return
        }

        let direction = flickDirection(for: sender, event: event)
        showFlickGuide(
            for: key,
            from: sender,
            selectedDirection: direction,
            showsAllDirections: flickGuideView.showsAllDirections
        )
    }

    @objc private func handleTouchCancel(_ sender: KeyboardButton) {
        stopDeleteRepeat()
        hideFlickGuide()
    }

    @objc private func handleKanaLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? KeyboardButton,
              case .kana(let key) = button.action else {
            return
        }

        showFlickGuide(for: key, from: button, selectedDirection: .center, showsAllDirections: true)
    }

    @objc private func handleKeyRelease(_ sender: KeyboardButton, event: UIEvent) {
        if suppressNextButtonRelease {
            suppressNextButtonRelease = false
            hideFlickGuide()
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
            deleteBackward()
        case .moveLeft:
            resetMultiTapState()
            moveLeftKey()
        case .moveRight:
            resetMultiTapState()
            moveRightKey()
        case .space:
            resetMultiTapState()
            if composingText.isEmpty {
                textDocumentProxy.insertText(" ")
            } else {
                commitDefaultCandidate()
            }
        case .enter:
            resetMultiTapState()
            if composingText.isEmpty {
                textDocumentProxy.insertText("\n")
            } else {
                commitDefaultCandidate()
            }
        }

        hideFlickGuide()
    }

    @objc private func commitCandidate(_ sender: CandidateButton) {
        guard let text = sender.committedText else {
            return
        }

        resetMultiTapState()
        commitComposingText(text)
    }

    @objc private func handleEnterLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }

        suppressNextButtonRelease = true
        resetMultiTapState()
        hideFlickGuide()
        commitRenderedComposingTextAsTyped()
        advanceToNextInputMode()
    }

    @objc private func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            suppressNextButtonRelease = true
            resetMultiTapState()
            hideFlickGuide()
            deleteBackward()
            startDeleteRepeat()
        case .ended, .cancelled, .failed:
            stopDeleteRepeat()
            DispatchQueue.main.async { [weak self] in
                self?.suppressNextButtonRelease = false
            }
        default:
            break
        }
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
            setComposingText(composingText + text)
            return
        }

        let now = Date()
        let shouldCycle = activeKeyLabel == key.label
            && lastInsertedText.isEmpty == false
            && lastInputDate.map { now.timeIntervalSince($0) <= multiTapInterval } == true

        var nextComposingText = composingText
        if shouldCycle {
            activeCandidateIndex = (activeCandidateIndex + 1) % key.candidates.count
            if nextComposingText.isEmpty == false {
                nextComposingText.removeLast()
            }
        } else {
            activeKeyLabel = key.label
            activeCandidateIndex = 0
        }

        let text = key.candidates[activeCandidateIndex]
        nextComposingText.append(text)
        setComposingText(nextComposingText)
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

    private func showFlickGuide(
        for key: KanaKey,
        from button: KeyboardButton,
        selectedDirection: FlickDirection,
        showsAllDirections: Bool
    ) {
        let buttonFrame = button.convert(button.bounds, to: view)
        let guideSize = CGSize(width: 150, height: 150)
        let rawOrigin = CGPoint(
            x: buttonFrame.midX - (guideSize.width / 2),
            y: buttonFrame.midY - (guideSize.height / 2)
        )
        let origin = CGPoint(
            x: min(max(rawOrigin.x, 4), max(view.bounds.width - guideSize.width - 4, 4)),
            y: min(max(rawOrigin.y, 4), max(view.bounds.height - guideSize.height - 4, 4))
        )

        flickGuideView.frame = CGRect(origin: origin, size: guideSize)
        flickGuideView.configure(
            candidates: flickGuideCandidates(for: key),
            selectedDirection: selectedDirection,
            showsAllDirections: showsAllDirections
        )
        flickGuideView.isHidden = false
        view.bringSubviewToFront(flickGuideView)
    }

    private func hideFlickGuide() {
        flickGuideView.isHidden = true
    }

    private func flickGuideCandidates(for key: KanaKey) -> [FlickDirection: String] {
        var candidates: [FlickDirection: String] = [:]
        for direction in [FlickDirection.center, .left, .up, .right, .down] {
            candidates[direction] = flickCandidate(for: key, direction: direction)
        }
        return candidates
    }

    private func updatePreedit() {
        normalizeCompositionRanges()

        let candidates = currentCandidateTexts()

        candidateButtons.removeAll()
        for view in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard candidates.isEmpty == false else {
            addCandidateButton(title: "候補", committedText: nil, isEnabled: false)
            return
        }

        for candidate in candidates {
            addCandidateButton(title: candidate, committedText: candidate, isEnabled: true)
        }
        candidateScrollView.setContentOffset(.zero, animated: false)
    }

    private func addCandidateButton(title: String, committedText: String?, isEnabled: Bool) {
        let button = CandidateButton()
        button.configure(title: title, committedText: committedText, isEnabled: isEnabled)
        button.addTarget(self, action: #selector(commitCandidate(_:)), for: .touchUpInside)
        candidateStack.addArrangedSubview(button)
        candidateButtons.append(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    private func commitDefaultCandidate() {
        guard composingText.isEmpty == false else {
            return
        }

        commitComposingText(currentCandidateTexts().first ?? conversionTargetText())
    }

    private func commitComposingText(_ text: String) {
        guard composingText.isEmpty == false else {
            return
        }

        let activeRange = normalizedConversionRange()
        let remainingUnderlineRange = underlineRange
        let updatedText = replacingText(in: activeRange, with: text)

        replaceRenderedComposingText(with: updatedText)

        if let remainingUnderlineRange,
           let nextRange = adjustedRangeAfterReplacement(
                remainingUnderlineRange,
                replacedRange: activeRange,
                replacementCharacterCount: text.count,
                updatedTextCount: updatedText.count
           ) {
            composingText = updatedText
            renderedComposingText = updatedText
            conversionRange = nextRange
            underlineRange = nil
        } else {
            composingText = ""
            renderedComposingText = ""
            conversionRange = 0..<0
            underlineRange = nil
        }
        updatePreedit()
    }

    private func commitRenderedComposingTextAsTyped() {
        guard composingText.isEmpty == false else {
            return
        }

        composingText = ""
        renderedComposingText = ""
        conversionRange = 0..<0
        underlineRange = nil
        updatePreedit()
    }

    private func setComposingText(_ text: String, resetsConversionRange: Bool = true) {
        replaceRenderedComposingText(with: text)
        composingText = text
        if resetsConversionRange {
            conversionRange = text.isEmpty ? 0..<0 : 0..<text.count
        }
        updateUnderlineRange()
        updatePreedit()
    }

    private func replaceRenderedComposingText(with text: String) {
        guard renderedComposingText != text else {
            return
        }

        let sharedPrefixCount = commonPrefixCount(renderedComposingText, text)
        let deleteCount = renderedComposingText.count - sharedPrefixCount

        for _ in 0..<deleteCount {
            textDocumentProxy.deleteBackward()
        }

        if sharedPrefixCount < text.count {
            let startIndex = stringIndex(in: text, offset: sharedPrefixCount)
            textDocumentProxy.insertText(String(text[startIndex...]))
        }

        renderedComposingText = text
    }

    private func deleteRenderedComposingText() {
        guard renderedComposingText.isEmpty == false else {
            return
        }

        for _ in renderedComposingText {
            textDocumentProxy.deleteBackward()
        }
        renderedComposingText = ""
    }

    private func deleteBackward() {
        guard composingText.isEmpty == false else {
            textDocumentProxy.deleteBackward()
            return
        }

        var nextText = composingText
        nextText.removeLast()
        setComposingText(nextText, resetsConversionRange: false)
    }

    private func moveLeftKey() {
        guard composingText.isEmpty == false else {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            return
        }

        moveConversionUpperBound(by: -1)
    }

    private func moveRightKey() {
        guard composingText.isEmpty == false else {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
            return
        }

        moveConversionUpperBound(by: 1)
    }

    private func moveConversionUpperBound(by offset: Int) {
        let count = composingText.count
        guard count > 0 else {
            return
        }

        let range = normalizedConversionRange()
        let lowerBound = range.lowerBound
        let upperBound = min(max(range.upperBound + offset, lowerBound + 1), count)
        conversionRange = lowerBound..<upperBound
        updateUnderlineRange()
        updatePreedit()
    }

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.deleteBackward()
        }
        deleteRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    private func currentCandidateTexts() -> [String] {
        guard composingText.isEmpty == false else {
            return []
        }

        let targetText = conversionTargetText()
        guard targetText.isEmpty == false else {
            return []
        }

        var seen = Set<String>()
        var candidates: [String] = []

        func appendUnique(_ text: String) {
            guard text.isEmpty == false, seen.insert(text).inserted else {
                return
            }
            candidates.append(text)
        }

        if let kanaKanjiConverter {
            let options = ConversionOptions(limit: conversionCandidateLimit, beamWidth: conversionBeamWidth)
            for candidate in kanaKanjiConverter.convert(targetText, options: options) {
                appendUnique(candidate.text)
            }
        }

        appendUnique(targetText)
        appendUnique(katakanaText(from: targetText))
        appendUnique(halfWidthKatakanaText(from: targetText))

        return candidates
    }

    private func conversionTargetText() -> String {
        text(in: normalizedConversionRange(), from: composingText)
    }

    private func updateUnderlineRange() {
        guard composingText.isEmpty == false else {
            underlineRange = nil
            conversionRange = 0..<0
            return
        }

        let activeRange = normalizedConversionRange()
        conversionRange = activeRange
        underlineRange = activeRange.upperBound < composingText.count
            ? activeRange.upperBound..<composingText.count
            : nil
    }

    private func normalizeCompositionRanges() {
        guard composingText.isEmpty == false else {
            conversionRange = 0..<0
            underlineRange = nil
            return
        }

        conversionRange = normalizedConversionRange()
        if let underlineRange {
            let lowerBound = min(max(underlineRange.lowerBound, 0), composingText.count)
            let upperBound = min(max(underlineRange.upperBound, lowerBound), composingText.count)
            self.underlineRange = lowerBound < upperBound ? lowerBound..<upperBound : nil
        }
    }

    private func normalizedConversionRange() -> Range<Int> {
        let count = composingText.count
        guard count > 0 else {
            return 0..<0
        }

        let lowerBound = min(max(conversionRange.lowerBound, 0), count - 1)
        let upperBound = min(max(conversionRange.upperBound, lowerBound + 1), count)
        return lowerBound..<upperBound
    }

    private func replacingText(in range: Range<Int>, with replacement: String) -> String {
        let lowerIndex = stringIndex(in: composingText, offset: range.lowerBound)
        let upperIndex = stringIndex(in: composingText, offset: range.upperBound)
        var updatedText = composingText
        updatedText.replaceSubrange(lowerIndex..<upperIndex, with: replacement)
        return updatedText
    }

    private func adjustedRangeAfterReplacement(
        _ range: Range<Int>,
        replacedRange: Range<Int>,
        replacementCharacterCount: Int,
        updatedTextCount: Int
    ) -> Range<Int>? {
        let replacedCharacterCount = replacedRange.upperBound - replacedRange.lowerBound
        let delta = replacementCharacterCount - replacedCharacterCount

        let adjustedRange: Range<Int>
        if range.lowerBound >= replacedRange.upperBound {
            adjustedRange = (range.lowerBound + delta)..<(range.upperBound + delta)
        } else if range.upperBound <= replacedRange.lowerBound {
            adjustedRange = range
        } else {
            return nil
        }

        let lowerBound = min(max(adjustedRange.lowerBound, 0), updatedTextCount)
        let upperBound = min(max(adjustedRange.upperBound, lowerBound), updatedTextCount)
        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }

    private func text(in range: Range<Int>, from text: String) -> String {
        let lowerIndex = stringIndex(in: text, offset: range.lowerBound)
        let upperIndex = stringIndex(in: text, offset: range.upperBound)
        return String(text[lowerIndex..<upperIndex])
    }

    private func stringIndex(in text: String, offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(offset, 0), text.count))
    }

    private func commonPrefixCount(_ lhs: String, _ rhs: String) -> Int {
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex
        var count = 0

        while lhsIndex < lhs.endIndex,
              rhsIndex < rhs.endIndex,
              lhs[lhsIndex] == rhs[rhsIndex] {
            count += 1
            lhs.formIndex(after: &lhsIndex)
            rhs.formIndex(after: &rhsIndex)
        }

        return count
    }

    private func scheduleKanaKanjiConverterLoad() {
        guard kanaKanjiConverter == nil,
              isLoadingKanaKanjiConverter == false,
              scheduledKanaKanjiLoad == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.scheduledKanaKanjiLoad = nil
            self.loadKanaKanjiConverter()
        }
        scheduledKanaKanjiLoad = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func loadKanaKanjiConverter() {
        guard kanaKanjiConverter == nil, isLoadingKanaKanjiConverter == false else {
            return
        }

        guard let artifactsDirectory = kanaKanjiArtifactsDirectory() else {
            converterLoadFailureMessage = "KanaKanji resources were not found in the keyboard bundle."
            return
        }

        isLoadingKanaKanjiConverter = true
        let loadGeneration = kanaKanjiLoadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<KanaKanjiConverter, Error>

            do {
                let dictionary = try MozcDictionary(artifactsDirectory: artifactsDirectory)
                let connectionMatrix = try ConnectionMatrix.loadBinaryBigEndianInt16(
                    artifactsDirectory.appendingPathComponent("connection_single_column.bin")
                )
                result = .success(KanaKanjiConverter(
                    dictionary: dictionary,
                    connectionMatrix: connectionMatrix
                ))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self, loadGeneration == self.kanaKanjiLoadGeneration else {
                    return
                }

                self.isLoadingKanaKanjiConverter = false
                switch result {
                case .success(let converter):
                    self.kanaKanjiConverter = converter
                    self.converterLoadFailureMessage = nil
                case .failure(let error):
                    self.kanaKanjiConverter = nil
                    self.converterLoadFailureMessage = error.localizedDescription
                }
                self.updatePreedit()
            }
        }
    }

    private func kanaKanjiArtifactsDirectory() -> URL? {
        let fileManager = FileManager.default
        var candidateDirectories: [URL] = []

        if let bundledDirectory = Bundle.main.url(forResource: "KanaKanjiResources", withExtension: nil) {
            candidateDirectories.append(bundledDirectory)
        }

        if let resourceDirectory = Bundle.main.resourceURL {
            candidateDirectories.append(resourceDirectory.appendingPathComponent("KanaKanjiResources", isDirectory: true))
            candidateDirectories.append(resourceDirectory)
        }

        return candidateDirectories.first { directory in
            MozcDictionary.artifactFileNames.allSatisfy { fileName in
                fileManager.fileExists(atPath: directory.appendingPathComponent(fileName).path)
            }
        }
    }

    private func katakanaText(from text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    private func halfWidthKatakanaText(from text: String) -> String {
        let katakana = katakanaText(from: text)
        return katakana.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? katakana
    }

    private func transformPreviousCharacter() {
        resetMultiTapState()

        if let previousCharacter = composingText.last,
           let transformedCharacter = transformedCharacter(after: previousCharacter) {
            var nextText = composingText
            nextText.removeLast()
            nextText.append(transformedCharacter)
            setComposingText(nextText, resetsConversionRange: false)
        } else if let previousCharacter = textDocumentProxy.documentContextBeforeInput?.last,
                  let transformedCharacter = transformedCharacter(after: previousCharacter) {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(String(transformedCharacter))
        }
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
