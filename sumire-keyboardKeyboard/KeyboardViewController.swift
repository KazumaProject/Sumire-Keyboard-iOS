import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum KeyboardTheme {
        static let keyboardBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
                : .systemGray5
        }

        static let keyBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1)
                : .white
        }

        static let keyHighlightedBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1)
                : .systemGray3
        }

        static let functionKeyBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1)
                : .systemGray3
        }

        static let functionKeyHighlightedBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1)
                : .systemGray2
        }

        static let candidateBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)
                : .white
        }

        static let popupBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.26, green: 0.26, blue: 0.28, alpha: 1)
                : .white
        }

        static let popupStroke = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.separator.withAlphaComponent(0.18)
        }
    }

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

    private enum InputStatus: Equatable {
        case direct
        case precomposition(PrecompositionStatus)
    }

    private enum PrecompositionLanguage: String, Equatable {
        case japanese
        case english
        case number
    }

    private enum PrecompositionPhase: Equatable {
        case empty
        case composing
        case converting(selectedCandidateIndex: Int)
    }

    private enum CompositionDisplayMode: Equatable {
        case liveCandidate
        case reading
    }

    private struct PrecompositionStatus: Equatable {
        var language: PrecompositionLanguage
        var phase: PrecompositionPhase
        var liveConversionEnabled: Bool
        var displayMode: CompositionDisplayMode

        var isConverting: Bool {
            if case .converting = phase {
                return true
            }
            return false
        }
    }

    private final class KeyboardButton: UIButton {
        let action: KeyAction
        private let normalBackgroundColor: UIColor
        private let highlightedBackgroundColor: UIColor

        init(title: String, action: KeyAction, style: ButtonStyle) {
            self.action = action
            self.normalBackgroundColor = style.backgroundColor
            self.highlightedBackgroundColor = style.highlightedBackgroundColor
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

        override var isHighlighted: Bool {
            didSet {
                updateBackgroundForCurrentState()
            }
        }

        override var isSelected: Bool {
            didSet {
                updateBackgroundForCurrentState()
            }
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateBackgroundForCurrentState()
        }

        required init?(coder: NSCoder) {
            return nil
        }

        private func updateBackgroundForCurrentState() {
            var updatedConfiguration = configuration
            updatedConfiguration?.baseBackgroundColor = (isHighlighted || isSelected)
                ? highlightedBackgroundColor
                : normalBackgroundColor
            configuration = updatedConfiguration
        }

        func updateTitle(_ title: String) {
            var updatedConfiguration = configuration
            updatedConfiguration?.title = title
            configuration = updatedConfiguration
        }
    }

    private final class CandidateButton: UIButton {
        var committedText: String?

        init() {
            super.init(frame: .zero)

            var configuration = UIButton.Configuration.filled()
            configuration.title = "候補"
            configuration.baseBackgroundColor = KeyboardTheme.candidateBackground
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
            layer.cornerRadius = 8
            layer.borderWidth = 0.5
            layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateColorsForCurrentTraits()
        }

        func configure(title: String, committedText: String?, isEnabled: Bool, isSelected: Bool = false) {
            self.committedText = committedText
            self.isEnabled = isEnabled
            self.isSelected = isSelected
            alpha = isEnabled ? 1 : 0.55

            var newConfiguration = self.configuration
            newConfiguration?.title = title
            newConfiguration?.baseBackgroundColor = isSelected ? .systemBlue : KeyboardTheme.candidateBackground
            newConfiguration?.baseForegroundColor = isSelected ? .white : (isEnabled ? .label : .secondaryLabel)
            newConfiguration?.titleLineBreakMode = .byTruncatingTail
            self.configuration = newConfiguration
            titleLabel?.numberOfLines = 1
            titleLabel?.lineBreakMode = .byTruncatingTail
            updateColorsForCurrentTraits()
        }

        private func updateColorsForCurrentTraits() {
            var newConfiguration = self.configuration
            newConfiguration?.baseBackgroundColor = isSelected ? .systemBlue : KeyboardTheme.candidateBackground
            newConfiguration?.baseForegroundColor = isSelected ? .white : (isEnabled ? .label : .secondaryLabel)
            self.configuration = newConfiguration
            layer.borderColor = UIColor.separator
                .withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.28 : 0.16)
                .resolvedColor(with: traitCollection)
                .cgColor
        }
    }

    private final class FlickGuideView: UIView {
        enum Mode {
            case flick
            case longPress
        }

        private final class CandidateView: UIView {
            private let shapeLayer = CAShapeLayer()
            private let label = UILabel()
            private var pointerDirection: FlickDirection?
            private var fillColor = UIColor.systemBackground
            private var strokeColor = UIColor.clear
            private var labelFrame = CGRect.zero
            private var usesFlickShape = false

            override init(frame: CGRect) {
                super.init(frame: frame)

                isUserInteractionEnabled = false
                backgroundColor = .clear
                layer.allowsEdgeAntialiasing = true
                layer.addSublayer(shapeLayer)

                label.textAlignment = .center
                label.adjustsFontSizeToFitWidth = true
                label.minimumScaleFactor = 0.7
                label.textColor = .label
                addSubview(label)
            }

            required init?(coder: NSCoder) {
                return nil
            }

            func configure(
                text: String?,
                isSelected: Bool,
                isDimmed: Bool,
                pointerDirection: FlickDirection?
            ) {
                self.pointerDirection = pointerDirection
                usesFlickShape = pointerDirection != nil
                label.text = text
                isHidden = text == nil

                fillColor = usesFlickShape || isSelected == false ? KeyboardTheme.popupBackground : .systemBlue
                strokeColor = usesFlickShape ? .clear : KeyboardTheme.popupStroke
                label.textColor = usesFlickShape
                    ? .label
                    : (isSelected ? .white : (isDimmed ? .secondaryLabel : .label))
                setNeedsLayout()
            }

            override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                super.traitCollectionDidChange(previousTraitCollection)
                setNeedsLayout()
            }

            override func layoutSubviews() {
                super.layoutSubviews()

                shapeLayer.frame = bounds
                shapeLayer.path = makePath(in: bounds).cgPath
                shapeLayer.fillColor = fillColor.resolvedColor(with: traitCollection).cgColor
                shapeLayer.strokeColor = strokeColor.resolvedColor(with: traitCollection).cgColor
                shapeLayer.lineWidth = 0.5

                label.frame = labelFrame.insetBy(dx: 4, dy: 2)
                let fontSize = min(42, max(26, labelFrame.height * 0.52))
                label.font = .systemFont(ofSize: fontSize, weight: .regular)
            }

            private func makePath(in bounds: CGRect) -> UIBezierPath {
                let cornerRadius = min(18, bounds.height * 0.22)
                guard let pointerDirection else {
                    labelFrame = bounds
                    return UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
                }

                let tailLength = min(36, max(22, min(bounds.width, bounds.height) * 0.28))

                switch pointerDirection {
                case .left:
                    labelFrame = CGRect(x: 0, y: 0, width: bounds.width - tailLength, height: bounds.height)
                    return makeRightTailPath(bodyRect: labelFrame, tipX: bounds.maxX, cornerRadius: cornerRadius)
                case .right:
                    labelFrame = CGRect(x: tailLength, y: 0, width: bounds.width - tailLength, height: bounds.height)
                    return makeLeftTailPath(bodyRect: labelFrame, tipX: bounds.minX, cornerRadius: cornerRadius)
                case .up:
                    labelFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - tailLength)
                    return makeBottomTailPath(bodyRect: labelFrame, tipY: bounds.maxY, cornerRadius: cornerRadius)
                case .down:
                    labelFrame = CGRect(x: 0, y: tailLength, width: bounds.width, height: bounds.height - tailLength)
                    return makeTopTailPath(bodyRect: labelFrame, tipY: bounds.minY, cornerRadius: cornerRadius)
                case .center:
                    labelFrame = bounds
                    return UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
                }
            }

            private func makeRightTailPath(bodyRect: CGRect, tipX: CGFloat, cornerRadius: CGFloat) -> UIBezierPath {
                let radius = min(cornerRadius, bodyRect.width / 2, bodyRect.height / 2)
                let path = UIBezierPath()

                path.move(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: tipX, y: bodyRect.midY))
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY))
                path.addLine(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - radius),
                    controlPoint: CGPoint(x: bodyRect.minX, y: bodyRect.maxY)
                )
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY),
                    controlPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY)
                )
                path.close()
                return path
            }

            private func makeLeftTailPath(bodyRect: CGRect, tipX: CGFloat, cornerRadius: CGFloat) -> UIBezierPath {
                let radius = min(cornerRadius, bodyRect.width / 2, bodyRect.height / 2)
                let path = UIBezierPath()

                path.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + radius),
                    controlPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
                )
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - radius))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.maxY),
                    controlPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
                )
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY))
                path.addLine(to: CGPoint(x: tipX, y: bodyRect.midY))
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
                path.close()
                return path
            }

            private func makeBottomTailPath(bodyRect: CGRect, tipY: CGFloat, cornerRadius: CGFloat) -> UIBezierPath {
                let radius = min(cornerRadius, bodyRect.width / 2, bodyRect.height / 2)
                let path = UIBezierPath()

                path.move(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + radius),
                    controlPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
                )
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY))
                path.addLine(to: CGPoint(x: bodyRect.midX, y: tipY))
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY))
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY),
                    controlPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY)
                )
                path.close()
                return path
            }

            private func makeTopTailPath(bodyRect: CGRect, tipY: CGFloat, cornerRadius: CGFloat) -> UIBezierPath {
                let radius = min(cornerRadius, bodyRect.width / 2, bodyRect.height / 2)
                let path = UIBezierPath()

                path.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: bodyRect.midX, y: tipY))
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY))
                path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - radius))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.maxY),
                    controlPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
                )
                path.addLine(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - radius),
                    controlPoint: CGPoint(x: bodyRect.minX, y: bodyRect.maxY)
                )
                path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
                path.addQuadCurve(
                    to: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                    controlPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY)
                )
                path.close()
                return path
            }
        }

        private let flickTailOverlap: CGFloat = 0
        private var candidateViews: [FlickDirection: CandidateView] = [:]
        private(set) var showsAllDirections = false

        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .clear
            clipsToBounds = false
            isUserInteractionEnabled = false

            for direction in [FlickDirection.left, .up, .right, .down, .center] {
                let candidateView = CandidateView()
                addSubview(candidateView)
                candidateViews[direction] = candidateView
            }
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func configure(
            candidates: [FlickDirection: String],
            selectedDirection: FlickDirection,
            mode: Mode,
            keyFrame: CGRect
        ) {
            showsAllDirections = mode == .longPress

            guard mode == .longPress || selectedDirection != .center else {
                isHidden = true
                return
            }

            let layoutFrames = makeLayoutFrames(
                keyFrame: keyFrame,
                selectedDirection: selectedDirection,
                mode: mode
            )
            guard let containerFrame = layoutFrames.values.reduce(nil, { partial, frame in
                partial?.union(frame) ?? frame
            }) else {
                isHidden = true
                return
            }

            frame = containerFrame

            for (direction, candidateView) in candidateViews {
                guard let candidateFrame = layoutFrames[direction] else {
                    candidateView.isHidden = true
                    continue
                }

                let isSelected = direction == selectedDirection
                let pointerDirection = mode == .flick ? selectedDirection : nil
                candidateView.frame = candidateFrame.offsetBy(
                    dx: -containerFrame.minX,
                    dy: -containerFrame.minY
                )
                candidateView.configure(
                    text: candidates[direction],
                    isSelected: isSelected,
                    isDimmed: false,
                    pointerDirection: pointerDirection
                )
            }

            isHidden = false
        }

        private func makeLayoutFrames(
            keyFrame: CGRect,
            selectedDirection: FlickDirection,
            mode: Mode
        ) -> [FlickDirection: CGRect] {
            switch mode {
            case .longPress:
                let stepX = keyFrame.width
                let stepY = keyFrame.height
                return [
                    .center: keyFrame,
                    .left: keyFrame.offsetBy(dx: -stepX, dy: 0),
                    .up: keyFrame.offsetBy(dx: 0, dy: -stepY),
                    .right: keyFrame.offsetBy(dx: stepX, dy: 0),
                    .down: keyFrame.offsetBy(dx: 0, dy: stepY)
                ]
            case .flick:
                let tailLength = min(36, max(22, min(keyFrame.width, keyFrame.height) * 0.28))
                let frame: CGRect
                switch selectedDirection {
                case .left:
                    frame = CGRect(
                        x: keyFrame.minX - keyFrame.width,
                        y: keyFrame.minY,
                        width: keyFrame.width + tailLength,
                        height: keyFrame.height
                    )
                case .right:
                    frame = CGRect(
                        x: keyFrame.maxX - tailLength + flickTailOverlap,
                        y: keyFrame.minY,
                        width: keyFrame.width + tailLength,
                        height: keyFrame.height
                    )
                case .up:
                    frame = CGRect(
                        x: keyFrame.minX,
                        y: keyFrame.minY - keyFrame.height,
                        width: keyFrame.width,
                        height: keyFrame.height + tailLength
                    )
                case .down:
                    frame = CGRect(
                        x: keyFrame.minX,
                        y: keyFrame.maxY - tailLength + flickTailOverlap,
                        width: keyFrame.width,
                        height: keyFrame.height + tailLength
                    )
                case .center:
                    return [:]
                }
                return [selectedDirection: frame]
            }
        }

        func hideAndReset() {
            showsAllDirections = false
            isHidden = true
        }
    }

    private struct ButtonStyle {
        let backgroundColor: UIColor
        let highlightedBackgroundColor: UIColor
        let foregroundColor: UIColor
        let font: UIFont
        let shadowOpacity: Float

        static let kana = ButtonStyle(
            backgroundColor: KeyboardTheme.keyBackground,
            highlightedBackgroundColor: KeyboardTheme.keyHighlightedBackground,
            foregroundColor: .label,
            font: .systemFont(ofSize: 24, weight: .semibold),
            shadowOpacity: 0.16
        )

        static let function = ButtonStyle(
            backgroundColor: KeyboardTheme.functionKeyBackground,
            highlightedBackgroundColor: KeyboardTheme.functionKeyHighlightedBackground,
            foregroundColor: .label,
            font: .systemFont(ofSize: 17, weight: .semibold),
            shadowOpacity: 0.1
        )

        static let primary = ButtonStyle(
            backgroundColor: .systemBlue,
            highlightedBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.72),
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
    private var inputStatus: InputStatus = .precomposition(PrecompositionStatus(
        language: .japanese,
        phase: .empty,
        liveConversionEnabled: UserDefaults.standard.object(forKey: KeyboardViewController.liveConversionDefaultsKey) as? Bool ?? true,
        displayMode: .liveCandidate
    ))
    private var composingText = ""
    private var composingCursorPosition = 0
    private var renderedComposingText = ""
    private var renderedCursorPosition = 0
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
    private weak var activeKanaButton: KeyboardButton?
    private weak var spaceButton: KeyboardButton?
    private var activeFlickDirection: FlickDirection = .center
    private var deleteRepeatTimer: Timer?
    private var cursorRepeatTimer: Timer?
    private var scheduledKanaKanjiLoad: DispatchWorkItem?
    private var kanaKanjiLoadGeneration = 0
    private static var cachedKanaKanjiConverter: KanaKanjiConverter?
    private static let liveConversionDefaultsKey = "SumireKeyboardLiveConversionEnabled"

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = KeyboardTheme.keyboardBackground
        view.clipsToBounds = false
        setupKeyboardLayout()
        updatePreedit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.backgroundColor = KeyboardTheme.keyboardBackground
        flickGuideView.setNeedsLayout()
        candidateButtons.forEach { $0.setNeedsLayout() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleKanaKanjiConverterLoad(delay: 0.25)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scheduledKanaKanjiLoad?.cancel()
        scheduledKanaKanjiLoad = nil
        stopDeleteRepeat()
        stopCursorRepeat()
        commitRenderedComposingTextAsTyped()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        scheduledKanaKanjiLoad?.cancel()
        scheduledKanaKanjiLoad = nil
        kanaKanjiLoadGeneration += 1
        isLoadingKanaKanjiConverter = false
        kanaKanjiConverter = nil
        Self.cachedKanaKanjiConverter = nil
        converterLoadFailureMessage = nil
        renderCurrentComposingText()
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
        self.spaceButton = spaceButton
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
        } else if case .moveLeft = button.action {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCursorLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            button.addGestureRecognizer(longPress)
        } else if case .moveRight = button.action {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCursorLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            button.addGestureRecognizer(longPress)
        }
    }

    @objc private func handleTouchDown(_ sender: KeyboardButton, event: UIEvent) {
        guard case .kana = sender.action else {
            return
        }

        activeKanaButton = sender
        activeFlickDirection = .center
        sender.isHighlighted = true
        hideFlickGuide()
    }

    @objc private func handleTouchDrag(_ sender: KeyboardButton, event: UIEvent) {
        guard case .kana(let key) = sender.action else {
            return
        }

        activeKanaButton = sender
        sender.isHighlighted = true
        let direction = flickDirection(for: sender, event: event)
        if direction == .center, flickGuideView.showsAllDirections == false {
            activeFlickDirection = .center
            hideFlickGuide()
            return
        }

        activeFlickDirection = direction
        showFlickGuide(
            for: key,
            from: sender,
            selectedDirection: direction,
            mode: flickGuideView.showsAllDirections ? .longPress : .flick
        )
    }

    @objc private func handleTouchCancel(_ sender: KeyboardButton) {
        stopDeleteRepeat()
        stopCursorRepeat()
        clearActiveKanaButton()
        activeFlickDirection = .center
        hideFlickGuide()
    }

    @objc private func handleKanaLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? KeyboardButton,
              case .kana(let key) = button.action else {
            return
        }

        activeKanaButton = button
        activeFlickDirection = .center
        button.isHighlighted = true
        showFlickGuide(for: key, from: button, selectedDirection: .center, mode: .longPress)
    }

    @objc private func handleKeyRelease(_ sender: KeyboardButton, event: UIEvent) {
        if suppressNextButtonRelease {
            suppressNextButtonRelease = false
            clearActiveKanaButton()
            activeFlickDirection = .center
            hideFlickGuide()
            return
        }

        switch sender.action {
        case .kana(let key):
            insertCandidate(for: key, direction: activeFlickDirection)
        case .transform:
            transformPreviousCharacter()
        case .delete:
            resetMultiTapState()
            handleDeleteKey()
        case .moveLeft:
            resetMultiTapState()
            handleMoveLeftKey()
        case .moveRight:
            resetMultiTapState()
            handleMoveRightKey()
        case .space:
            resetMultiTapState()
            handleSpaceKey()
        case .enter:
            resetMultiTapState()
            handleEnterKey()
        }

        clearActiveKanaButton()
        activeFlickDirection = .center
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

    @objc private func handleCursorLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyboardButton else {
            return
        }

        switch gesture.state {
        case .began:
            suppressNextButtonRelease = true
            resetMultiTapState()
            hideFlickGuide()
            handleCursorRepeat(for: button.action)
            startCursorRepeat(for: button.action)
        case .ended, .cancelled, .failed:
            stopCursorRepeat()
            DispatchQueue.main.async { [weak self] in
                self?.suppressNextButtonRelease = false
            }
        default:
            break
        }
    }

    private func flickDirection(for button: KeyboardButton, event: UIEvent) -> FlickDirection {
        guard let touch = event.touches(for: button)?.first ?? event.allTouches?.first else {
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
            insertText(text)
            return
        }

        let now = Date()
        let shouldCycle = activeKeyLabel == key.label
            && lastInsertedText.isEmpty == false
            && lastInputDate.map { now.timeIntervalSince($0) <= multiTapInterval } == true

        if shouldCycle {
            activeCandidateIndex = (activeCandidateIndex + 1) % key.candidates.count
        } else {
            activeKeyLabel = key.label
            activeCandidateIndex = 0
        }

        let text = key.candidates[activeCandidateIndex]
        if isDirectMode {
            if shouldCycle {
                for _ in lastInsertedText {
                    textDocumentProxy.deleteBackward()
                }
            }
            textDocumentProxy.insertText(text)
        } else {
            if shouldCycle {
                replacePreviousComposingCharacter(with: text)
            } else {
                insertText(text)
            }
        }
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
        mode: FlickGuideView.Mode
    ) {
        let buttonFrame = button.convert(button.bounds, to: view)
        flickGuideView.configure(
            candidates: flickGuideCandidates(for: key),
            selectedDirection: selectedDirection,
            mode: mode,
            keyFrame: buttonFrame
        )
        view.bringSubviewToFront(flickGuideView)
    }

    private func hideFlickGuide() {
        flickGuideView.hideAndReset()
    }

    private func clearActiveKanaButton() {
        activeKanaButton?.isHighlighted = false
        activeKanaButton = nil
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
        updateSpaceButtonTitle()

        let candidates = currentCandidateTexts()
        let selectedCandidateIndex = currentSelectedCandidateIndex(candidateCount: candidates.count)

        candidateButtons.removeAll()
        for view in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard isDirectMode == false else {
            return
        }

        guard candidates.isEmpty == false else {
            addCandidateButton(title: "候補", committedText: nil, isEnabled: false)
            return
        }

        for (index, candidate) in candidates.enumerated() {
            addCandidateButton(
                title: candidate,
                committedText: candidate,
                isEnabled: true,
                isSelected: index == selectedCandidateIndex
            )
        }

        if let selectedCandidateIndex {
            scrollCandidateIntoView(at: selectedCandidateIndex)
        } else {
            candidateScrollView.setContentOffset(.zero, animated: false)
        }
    }

    private func updateSpaceButtonTitle() {
        spaceButton?.updateTitle(canUseSpaceAsConversionKey ? "変換" : "空白")
    }

    private var canUseSpaceAsConversionKey: Bool {
        guard composingText.isEmpty == false,
              case .precomposition(let status) = inputStatus,
              status.language == .japanese,
              normalizedConversionRange().isEmpty == false else {
            return false
        }

        return true
    }

    private func addCandidateButton(
        title: String,
        committedText: String?,
        isEnabled: Bool,
        isSelected: Bool = false
    ) {
        let button = CandidateButton()
        button.configure(title: title, committedText: committedText, isEnabled: isEnabled, isSelected: isSelected)
        button.addTarget(self, action: #selector(commitCandidate(_:)), for: .touchUpInside)
        candidateStack.addArrangedSubview(button)
        candidateButtons.append(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    private func scrollCandidateIntoView(at index: Int) {
        guard candidateButtons.indices.contains(index) else {
            return
        }

        let button = candidateButtons[index]
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button else {
                return
            }

            let frame = button.convert(button.bounds, to: self.candidateScrollView)
            self.candidateScrollView.scrollRectToVisible(frame.insetBy(dx: -8, dy: 0), animated: true)
        }
    }

    private func handleDeleteKey() {
        if isDirectMode || composingText.isEmpty {
            textDocumentProxy.deleteBackward()
            return
        }

        deleteBackward()
    }

    private func handleMoveLeftKey() {
        switch inputStatus {
        case .direct:
            moveCursor(byCharacterOffset: -1)
        case .precomposition(let status):
            if status.isConverting {
                moveSelectedConversionCandidate(by: -1)
            } else {
                moveComposingCursor(by: -1)
            }
        }
    }

    private func handleMoveRightKey() {
        switch inputStatus {
        case .direct:
            moveCursor(byCharacterOffset: 1)
        case .precomposition(let status):
            if status.isConverting {
                moveSelectedConversionCandidate(by: 1)
            } else {
                moveComposingCursor(by: 1)
            }
        }
    }

    private func handleSpaceKey() {
        switch inputStatus {
        case .direct:
            textDocumentProxy.insertText(" ")
        case .precomposition(let status):
            guard composingText.isEmpty == false else {
                textDocumentProxy.insertText(" ")
                return
            }

            if status.language == .japanese {
                guard canUseSpaceAsConversionKey else {
                    insertText(" ")
                    return
                }

                switch status.phase {
                case .converting:
                    moveSelectedConversionCandidate(by: 1)
                case .empty, .composing:
                    enterConversionMode()
                }
            } else {
                insertText(" ")
            }
        }
    }

    private func handleEnterKey() {
        switch inputStatus {
        case .direct:
            textDocumentProxy.insertText("\n")
        case .precomposition:
            if composingText.isEmpty {
                textDocumentProxy.insertText("\n")
            } else {
                commitSelectedOrDefaultCandidate()
            }
        }
    }

    private func commitDefaultCandidate() {
        guard composingText.isEmpty == false else {
            return
        }

        commitComposingText(currentCandidateTexts().first ?? conversionTargetText())
    }

    private func commitSelectedOrDefaultCandidate() {
        let candidates = currentCandidateTexts()
        if let selectedIndex = currentSelectedCandidateIndex(candidateCount: candidates.count),
           candidates.indices.contains(selectedIndex) {
            commitComposingText(candidates[selectedIndex])
            return
        }

        commitDefaultCandidate()
    }

    private var isDirectMode: Bool {
        if case .direct = inputStatus {
            return true
        }
        return false
    }

    private var currentPrecompositionStatus: PrecompositionStatus? {
        if case .precomposition(let status) = inputStatus {
            return status
        }
        return nil
    }

    private func currentSelectedCandidateIndex(candidateCount: Int) -> Int? {
        guard candidateCount > 0,
              case .precomposition(let status) = inputStatus,
              case .converting(let selectedCandidateIndex) = status.phase else {
            return nil
        }

        return min(max(selectedCandidateIndex, 0), candidateCount - 1)
    }

    private func setPrecompositionPhase(_ phase: PrecompositionPhase) {
        guard case .precomposition(var status) = inputStatus else {
            return
        }

        status.phase = phase
        inputStatus = .precomposition(status)
    }

    private func setCompositionDisplayMode(_ displayMode: CompositionDisplayMode) {
        guard case .precomposition(var status) = inputStatus else {
            return
        }

        status.displayMode = displayMode
        inputStatus = .precomposition(status)
    }

    private func setLiveConversionEnabled(_ isEnabled: Bool) {
        guard case .precomposition(var status) = inputStatus else {
            return
        }

        status.liveConversionEnabled = isEnabled
        status.displayMode = isEnabled ? .liveCandidate : .reading
        inputStatus = .precomposition(status)
        UserDefaults.standard.set(isEnabled, forKey: Self.liveConversionDefaultsKey)
        renderCurrentComposingText()
        updatePreedit()
    }

    private func syncPrecompositionPhaseForCurrentText() {
        guard case .precomposition(var status) = inputStatus else {
            return
        }

        status.phase = composingText.isEmpty ? .empty : .composing
        if composingText.isEmpty {
            status.displayMode = .liveCandidate
        }
        inputStatus = .precomposition(status)
    }

    private func enterConversionMode() {
        guard composingText.isEmpty == false,
              normalizedConversionRange().isEmpty == false else {
            return
        }

        setCompositionDisplayMode(.liveCandidate)
        setPrecompositionPhase(.converting(selectedCandidateIndex: 0))
        renderCurrentComposingText()
        updatePreedit()
    }

    private func moveSelectedConversionCandidate(by offset: Int) {
        let candidates = currentCandidateTexts()
        guard candidates.isEmpty == false,
              case .precomposition(var status) = inputStatus else {
            return
        }

        let currentIndex: Int
        if case .converting(let selectedCandidateIndex) = status.phase {
            currentIndex = min(max(selectedCandidateIndex, 0), candidates.count - 1)
        } else {
            currentIndex = 0
        }

        let nextIndex = (currentIndex + offset + candidates.count) % candidates.count
        status.phase = .converting(selectedCandidateIndex: nextIndex)
        status.displayMode = .liveCandidate
        inputStatus = .precomposition(status)
        renderCurrentComposingText()
        updatePreedit()
    }

    private func insertText(_ text: String) {
        guard text.isEmpty == false else {
            return
        }

        guard isDirectMode == false else {
            textDocumentProxy.insertText(text)
            return
        }

        var nextText = composingText
        let insertionIndex = stringIndex(in: nextText, offset: composingCursorPosition)
        nextText.insert(contentsOf: text, at: insertionIndex)
        if canEditReadingDisplayDirectly {
            textDocumentProxy.insertText(text)
            composingText = nextText
            renderedComposingText = nextText
            composingCursorPosition += text.count
            renderedCursorPosition += text.count
            updateCompositionStateAfterTextMutation(resetsConversionRange: true)
        } else {
            composingCursorPosition += text.count
            setComposingText(nextText)
        }
    }

    private func replacePreviousComposingCharacter(with text: String) {
        guard isDirectMode == false else {
            textDocumentProxy.insertText(text)
            return
        }

        guard composingText.isEmpty == false, composingCursorPosition > 0 else {
            insertText(text)
            return
        }

        var nextText = composingText
        let lowerIndex = stringIndex(in: nextText, offset: composingCursorPosition - 1)
        let upperIndex = stringIndex(in: nextText, offset: composingCursorPosition)
        nextText.replaceSubrange(lowerIndex..<upperIndex, with: text)
        if canEditReadingDisplayDirectly {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(text)
            composingText = nextText
            renderedComposingText = nextText
            composingCursorPosition = composingCursorPosition - 1 + text.count
            renderedCursorPosition = renderedCursorPosition - 1 + text.count
            updateCompositionStateAfterTextMutation(resetsConversionRange: true)
        } else {
            composingCursorPosition = composingCursorPosition - 1 + text.count
            setComposingText(nextText)
        }
    }

    private func commitComposingText(_ text: String) {
        guard composingText.isEmpty == false else {
            return
        }

        let activeRange = normalizedConversionRange()
        guard activeRange.isEmpty == false else {
            return
        }

        let remainingText = self.text(in: activeRange.upperBound..<composingText.count, from: composingText)
        let updatedText = replacingText(in: activeRange, with: text)

        replaceRenderedComposingText(with: updatedText)

        if remainingText.isEmpty == false {
            composingText = remainingText
            renderedComposingText = remainingText
            composingCursorPosition = remainingText.count
            renderedCursorPosition = remainingText.count
            conversionRange = conversionRangeBeforeCursor()
            underlineRange = nil
            syncPrecompositionPhaseForCurrentText()
            renderCurrentComposingText()
        } else {
            composingText = ""
            renderedComposingText = ""
            composingCursorPosition = 0
            renderedCursorPosition = 0
            conversionRange = 0..<0
            underlineRange = nil
            syncPrecompositionPhaseForCurrentText()
        }
        updatePreedit()
    }

    private func commitRenderedComposingTextAsTyped() {
        guard composingText.isEmpty == false else {
            return
        }

        composingText = ""
        renderedComposingText = ""
        composingCursorPosition = 0
        renderedCursorPosition = 0
        conversionRange = 0..<0
        underlineRange = nil
        syncPrecompositionPhaseForCurrentText()
        updatePreedit()
    }

    private func setComposingText(_ text: String, resetsConversionRange: Bool = true) {
        composingText = text
        composingCursorPosition = min(max(composingCursorPosition, 0), text.count)
        updateCompositionStateAfterTextMutation(resetsConversionRange: resetsConversionRange, updatesPreedit: false)
        renderCurrentComposingText()
        updatePreedit()
    }

    private func updateCompositionStateAfterTextMutation(
        resetsConversionRange: Bool,
        updatesPreedit: Bool = true
    ) {
        if resetsConversionRange {
            conversionRange = conversionRangeBeforeCursor()
        }
        updateUnderlineRange()
        syncPrecompositionPhaseForCurrentText()
        if updatesPreedit {
            updatePreedit()
        }
    }

    private func renderCurrentComposingText() {
        replaceRenderedComposingText(with: renderedTextForCurrentComposition())
    }

    private func renderedTextForCurrentComposition() -> String {
        guard composingText.isEmpty == false,
              let status = currentPrecompositionStatus,
              status.liveConversionEnabled,
              status.language == .japanese,
              status.displayMode == .liveCandidate else {
            return composingText
        }

        let candidates = currentCandidateTexts()
        let replacement: String
        if let selectedIndex = currentSelectedCandidateIndex(candidateCount: candidates.count),
           candidates.indices.contains(selectedIndex) {
            replacement = candidates[selectedIndex]
        } else {
            replacement = candidates.first ?? conversionTargetText()
        }

        return replacingText(in: normalizedConversionRange(), with: replacement)
    }

    private func replaceRenderedComposingText(with text: String) {
        guard renderedComposingText != text else {
            return
        }

        moveHostCursorToRenderedEnd()

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
        renderedCursorPosition = text.count
    }

    private func moveHostCursorToRenderedEnd() {
        let offset = renderedComposingText.count - renderedCursorPosition
        guard offset != 0 else {
            return
        }

        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        renderedCursorPosition += offset
    }

    private func deleteRenderedComposingText() {
        guard renderedComposingText.isEmpty == false else {
            return
        }

        for _ in renderedComposingText {
            textDocumentProxy.deleteBackward()
        }
        renderedComposingText = ""
        renderedCursorPosition = 0
    }

    private func deleteBackward() {
        guard composingText.isEmpty == false else {
            textDocumentProxy.deleteBackward()
            return
        }

        guard composingCursorPosition > 0 else {
            return
        }

        var nextText = composingText
        let lowerIndex = stringIndex(in: nextText, offset: composingCursorPosition - 1)
        let upperIndex = stringIndex(in: nextText, offset: composingCursorPosition)
        nextText.removeSubrange(lowerIndex..<upperIndex)
        if canEditReadingDisplayDirectly {
            textDocumentProxy.deleteBackward()
            composingText = nextText
            renderedComposingText = nextText
            composingCursorPosition -= 1
            renderedCursorPosition -= 1
            updateCompositionStateAfterTextMutation(resetsConversionRange: false)
        } else {
            composingCursorPosition -= 1
            setComposingText(nextText, resetsConversionRange: false)
        }
    }

    private func moveLeftKey() {
        moveCursor(byCharacterOffset: -1)
    }

    private func moveRightKey() {
        moveCursor(byCharacterOffset: 1)
    }

    private func moveCursor(byCharacterOffset offset: Int) {
        if composingText.isEmpty == false {
            commitRenderedComposingTextAsTyped()
        }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    private func moveComposingCursor(by offset: Int) {
        guard composingText.isEmpty == false else {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            return
        }

        let nextCursorPosition = min(max(composingCursorPosition + offset, 0), composingText.count)
        switchToReadingDisplayForCursorEditingIfNeeded()

        let hostCursorOffset = nextCursorPosition - renderedCursorPosition
        composingCursorPosition = nextCursorPosition
        renderedCursorPosition = nextCursorPosition
        conversionRange = conversionRangeBeforeCursor()
        updateUnderlineRange()
        if hostCursorOffset != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: hostCursorOffset)
        }
        updatePreedit()
    }

    private func switchToReadingDisplayForCursorEditingIfNeeded() {
        guard case .precomposition(let status) = inputStatus,
              status.language == .japanese,
              status.liveConversionEnabled,
              status.displayMode == .liveCandidate,
              composingText.isEmpty == false else {
            return
        }

        setCompositionDisplayMode(.reading)
        renderCurrentComposingText()
    }

    private var canEditReadingDisplayDirectly: Bool {
        guard case .precomposition(let status) = inputStatus,
              status.displayMode == .reading,
              renderedComposingText == composingText else {
            return false
        }

        return true
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

    private func startCursorRepeat(for action: KeyAction) {
        stopCursorRepeat()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.handleCursorRepeat(for: action)
        }
        cursorRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCursorRepeat() {
        cursorRepeatTimer?.invalidate()
        cursorRepeatTimer = nil
    }

    private func handleCursorRepeat(for action: KeyAction) {
        switch action {
        case .moveLeft:
            handleMoveLeftKey()
        case .moveRight:
            handleMoveRightKey()
        default:
            break
        }
    }

    private func currentCandidateTexts() -> [String] {
        guard isDirectMode == false, composingText.isEmpty == false else {
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

        guard currentPrecompositionStatus?.language == .japanese else {
            appendUnique(targetText)
            return candidates
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

    private func conversionRangeBeforeCursor() -> Range<Int> {
        guard composingText.isEmpty == false, composingCursorPosition > 0 else {
            return 0..<0
        }

        let upperBound = min(max(composingCursorPosition, 0), composingText.count)
        return 0..<upperBound
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
        guard conversionRange.isEmpty == false else {
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

    private func scheduleKanaKanjiConverterLoad(delay: TimeInterval = 0.05) {
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
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func loadKanaKanjiConverter() {
        guard kanaKanjiConverter == nil, isLoadingKanaKanjiConverter == false else {
            return
        }

        if let cachedConverter = Self.cachedKanaKanjiConverter {
            kanaKanjiConverter = cachedConverter
            converterLoadFailureMessage = nil
            renderCurrentComposingText()
            updatePreedit()
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
                    Self.cachedKanaKanjiConverter = converter
                    self.converterLoadFailureMessage = nil
                case .failure(let error):
                    self.kanaKanjiConverter = nil
                    self.converterLoadFailureMessage = error.localizedDescription
                }
                self.renderCurrentComposingText()
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
