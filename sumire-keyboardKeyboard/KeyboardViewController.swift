import UIKit

final class KeyboardViewController: UIInputViewController, UICollectionViewDataSource, UICollectionViewDelegate {
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

        static let candidateBackground = UIColor { _ in
            .clear
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

    private struct ConversionCandidateItem: Equatable {
        let text: String
        let consumedReadingLength: Int
    }

    private enum KeyAction {
        case kana(KanaKey)
        case flickOnly(KanaKey)
        case transform
        case reverseCycle
        case switchMode
        case switchToJapanese
        case switchToEnglish
        case switchToNumber
        case emojiKeyboard
        case togglePreviousAlphabetCase
        case nextKeyboard
        case qwertyText(String)
        case qwertyShift
        case qwertySwitchSymbols
        case qwertySwitchSymbolPage
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

    private enum MainKeyboardPanel: Equatable {
        case text
        case emoji
    }

    // mainKeyboardPanel は通常パネルの種類、こちらは mainKeyboardContainer の表示内容を分けて管理するために使う。
    private enum MainKeyboardContentMode: Equatable {
        case keyboard
        case candidateList
    }

    private enum QWERTYMode: Equatable {
        case normal
        case symbols
        case moreSymbols
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

    private enum ResizeHandlePosition: CaseIterable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left

        enum HorizontalEdge {
            case left
            case right
        }

        var horizontalEdge: HorizontalEdge? {
            switch self {
            case .topLeft, .left, .bottomLeft:
                return .left
            case .topRight, .right, .bottomRight:
                return .right
            case .top, .bottom:
                return nil
            }
        }

        var verticalSign: CGFloat {
            switch self {
            case .topLeft, .top, .topRight:
                return -1
            case .bottomLeft, .bottom, .bottomRight:
                return 1
            case .left, .right:
                return 0
            }
        }
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

    private struct ResizePanStartState {
        var metrics: KeyboardSettings.KeyboardLayoutMetrics
        var leadingOffset: CGFloat
        var width: CGFloat
        var height: CGFloat
        var containerWidth: CGFloat
    }

    private final class KeyboardButton: UIButton, KeyboardContentHidable {
        let action: KeyAction
        private let normalBackgroundColor: UIColor
        private let highlightedBackgroundColor: UIColor
        private let normalForegroundColor: UIColor
        private var stackedTitleStack: UIStackView?
        private var isKeyboardContentHidden = false
        var usesTapOnlyHighlight = false {
            didSet {
                updateBackgroundForCurrentState()
            }
        }
        private var tapHighlightIsVisible = false

        init(
            title: String? = nil,
            systemImageName: String? = nil,
            symbolPointSize: CGFloat = 19,
            action: KeyAction,
            style: ButtonStyle
        ) {
            self.action = action
            self.normalBackgroundColor = style.backgroundColor
            self.highlightedBackgroundColor = style.highlightedBackgroundColor
            self.normalForegroundColor = style.foregroundColor
            super.init(frame: .zero)

            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            if let systemImageName {
                configuration.image = UIImage(systemName: systemImageName)
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                    pointSize: symbolPointSize,
                    weight: .semibold
                )
            }
            configuration.baseBackgroundColor = style.backgroundColor
            configuration.baseForegroundColor = style.foregroundColor
            configuration.cornerStyle = .medium
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)

            self.configuration = configuration
            titleLabel?.font = style.font
            titleLabel?.adjustsFontSizeToFitWidth = true
            titleLabel?.minimumScaleFactor = 0.62
            titleLabel?.numberOfLines = 1
            titleLabel?.lineBreakMode = .byTruncatingTail
            layer.cornerRadius = 8
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = style.shadowOpacity
            layer.shadowRadius = 1
            layer.shadowOffset = CGSize(width: 0, height: 1)
            isMultipleTouchEnabled = true
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
            let showsHighlight = isSelected
                || (usesTapOnlyHighlight ? tapHighlightIsVisible : isHighlighted)
            updatedConfiguration?.baseBackgroundColor = showsHighlight
                ? highlightedBackgroundColor
                : normalBackgroundColor
            updatedConfiguration?.baseForegroundColor = currentForegroundColor()
            configuration = updatedConfiguration
            applyContentVisibility()
        }

        func flashTapHighlight() {
            tapHighlightIsVisible = true
            updateBackgroundForCurrentState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.tapHighlightIsVisible = false
                self?.updateBackgroundForCurrentState()
            }
        }

        func updateTitle(_ title: String) {
            removeStackedTitle()
            var updatedConfiguration = configuration
            updatedConfiguration?.title = title
            updatedConfiguration?.image = nil
            updatedConfiguration?.baseForegroundColor = currentForegroundColor()
            configuration = updatedConfiguration
            applyContentVisibility()
        }

        func updateSystemImage(_ systemImageName: String) {
            removeStackedTitle()
            var updatedConfiguration = configuration
            updatedConfiguration?.title = nil
            updatedConfiguration?.image = UIImage(systemName: systemImageName)
            updatedConfiguration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 19,
                weight: .semibold
            )
            updatedConfiguration?.baseForegroundColor = currentForegroundColor()
            configuration = updatedConfiguration
            applyContentVisibility()
        }

        func setFunctionEnabled(_ isEnabled: Bool) {
            self.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.38
            var updatedConfiguration = configuration
            updatedConfiguration?.baseForegroundColor = currentForegroundColor()
            configuration = updatedConfiguration
            applyContentVisibility()
        }

        func configureStackedTitle(
            primary: String,
            secondary: String,
            primaryFontSize: CGFloat = 26,
            secondaryFontSize: CGFloat = 15
        ) {
            var updatedConfiguration = configuration
            updatedConfiguration?.title = nil
            updatedConfiguration?.image = nil
            configuration = updatedConfiguration

            removeStackedTitle()

            let primaryLabel = UILabel()
            primaryLabel.text = primary
            primaryLabel.textColor = normalForegroundColor
            primaryLabel.font = .systemFont(ofSize: primaryFontSize, weight: .regular)
            primaryLabel.textAlignment = .center
            primaryLabel.adjustsFontSizeToFitWidth = true
            primaryLabel.minimumScaleFactor = 0.72

            let secondaryLabel = UILabel()
            secondaryLabel.text = secondary
            secondaryLabel.textColor = normalForegroundColor
            secondaryLabel.font = .systemFont(ofSize: secondaryFontSize, weight: .regular)
            secondaryLabel.textAlignment = .center
            secondaryLabel.adjustsFontSizeToFitWidth = true
            secondaryLabel.minimumScaleFactor = 0.7

            let stack = UIStackView(arrangedSubviews: [primaryLabel, secondaryLabel])
            stack.axis = .vertical
            stack.alignment = .center
            stack.distribution = .fill
            stack.spacing = 0
            stack.isUserInteractionEnabled = false
            stack.translatesAutoresizingMaskIntoConstraints = false

            addSubview(stack)
            stackedTitleStack = stack
            applyContentVisibility()
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
            ])
        }

        func setKeyboardContentHidden(_ isHidden: Bool) {
            guard isKeyboardContentHidden != isHidden else {
                return
            }

            isKeyboardContentHidden = isHidden
            updateBackgroundForCurrentState()
        }

        private func currentForegroundColor() -> UIColor {
            if isKeyboardContentHidden {
                return .clear
            }

            return isEnabled ? normalForegroundColor : .secondaryLabel
        }

        private func applyContentVisibility() {
            let contentAlpha: CGFloat = isKeyboardContentHidden ? 0 : 1
            titleLabel?.alpha = contentAlpha
            imageView?.alpha = contentAlpha
            stackedTitleStack?.alpha = contentAlpha
            tintColor = currentForegroundColor()
        }

        private func removeStackedTitle() {
            stackedTitleStack?.removeFromSuperview()
            stackedTitleStack = nil
        }
    }

    private final class CandidateButton: UIButton {
        var committedCandidate: ConversionCandidateItem?

        init() {
            super.init(frame: .zero)

            var configuration = UIButton.Configuration.filled()
            configuration.title = "候補"
            configuration.baseBackgroundColor = KeyboardTheme.candidateBackground
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .medium
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)
            self.configuration = configuration
            titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            titleLabel?.adjustsFontSizeToFitWidth = true
            titleLabel?.minimumScaleFactor = 0.72
            titleLabel?.numberOfLines = 1
            titleLabel?.lineBreakMode = .byTruncatingTail
            setContentHuggingPriority(.required, for: .horizontal)
            setContentCompressionResistancePriority(.required, for: .horizontal)
            layer.cornerRadius = 8
            layer.borderWidth = 0
            layer.borderColor = UIColor.clear.cgColor
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateColorsForCurrentTraits()
        }

        func configure(
            title: String,
            committedCandidate: ConversionCandidateItem?,
            isEnabled: Bool,
            isSelected: Bool = false
        ) {
            self.committedCandidate = committedCandidate
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
            layer.borderWidth = isSelected ? 0.5 : 0
            layer.borderColor = isSelected
                ? UIColor.systemBlue.resolvedColor(with: traitCollection).cgColor
                : UIColor.clear.cgColor
        }
    }

    private final class CandidateListCell: UICollectionViewCell {
        static let reuseIdentifier = "CandidateListCell"
        private static let maximumTitleWidth: CGFloat = 220
        private static let minimumCellWidth: CGFloat = 44
        private static let minimumCellHeight: CGFloat = 30

        private let titleLabel = UILabel()
        private let dividerLabel = UILabel()
        private let contentStack = UIStackView()

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 8
            contentView.layer.masksToBounds = true

            titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
            titleLabel.textColor = .label
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byCharWrapping
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            dividerLabel.text = "｜"
            dividerLabel.font = .systemFont(ofSize: 14, weight: .regular)
            dividerLabel.textColor = .separator
            dividerLabel.textAlignment = .center
            dividerLabel.setContentHuggingPriority(.required, for: .horizontal)
            dividerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            contentStack.axis = .horizontal
            contentStack.alignment = .center
            contentStack.distribution = .fill
            contentStack.spacing = 5
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(contentStack)
            contentStack.addArrangedSubview(titleLabel)
            contentStack.addArrangedSubview(dividerLabel)

            NSLayoutConstraint.activate([
                contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
                contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
                contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
                titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumTitleWidth),
                contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumCellHeight)
            ])
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            titleLabel.text = nil
            dividerLabel.isHidden = false
            isSelected = false
        }

        override func preferredLayoutAttributesFitting(
            _ layoutAttributes: UICollectionViewLayoutAttributes
        ) -> UICollectionViewLayoutAttributes {
            setNeedsLayout()
            layoutIfNeeded()

            let fittingSize = contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
            attributes.frame.size = CGSize(
                width: max(Self.minimumCellWidth, ceil(fittingSize.width)),
                height: max(Self.minimumCellHeight, ceil(fittingSize.height))
            )
            return attributes
        }

        override var isSelected: Bool {
            didSet {
                updateSelectionAppearance()
            }
        }

        func configure(title: String, showsDivider: Bool, isSelected: Bool) {
            titleLabel.text = title
            dividerLabel.isHidden = showsDivider == false
            self.isSelected = isSelected
            updateSelectionAppearance()
        }

        private func updateSelectionAppearance() {
            contentView.backgroundColor = isSelected ? .systemBlue : .clear
            titleLabel.textColor = isSelected ? .white : .label
            dividerLabel.textColor = isSelected ? UIColor.white.withAlphaComponent(0.7) : .separator
        }
    }

    private final class LeftAlignedCollectionViewFlowLayout: UICollectionViewFlowLayout {
        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            guard let originalAttributes = super.layoutAttributesForElements(in: rect) else {
                return nil
            }

            let attributes = originalAttributes.compactMap {
                $0.copy() as? UICollectionViewLayoutAttributes
            }
            let cellAttributes = attributes
                .filter { $0.representedElementCategory == .cell }
                .sorted {
                    if abs($0.frame.minY - $1.frame.minY) > 1 {
                        return $0.frame.minY < $1.frame.minY
                    }
                    return $0.frame.minX < $1.frame.minX
                }

            var leftInset = sectionInset.left
            var currentRowMinY: CGFloat?
            for attribute in cellAttributes {
                if let rowMinY = currentRowMinY,
                   abs(attribute.frame.minY - rowMinY) <= 1 {
                    attribute.frame.origin.x = leftInset
                    leftInset = attribute.frame.maxX + minimumInteritemSpacing
                } else {
                    currentRowMinY = attribute.frame.minY
                    leftInset = sectionInset.left
                    attribute.frame.origin.x = leftInset
                    leftInset = attribute.frame.maxX + minimumInteritemSpacing
                }
            }

            return attributes
        }
    }

    private final class PreeditReadingView: UIView {
        private static let rowHeight: CGFloat = 18
        private static let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        private static let emphasizedFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

        private let scrollView = UIScrollView()
        private let label = UILabel()

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight)
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .clear
            clipsToBounds = false
            translatesAutoresizingMaskIntoConstraints = false

            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = true
            scrollView.backgroundColor = .clear
            scrollView.clipsToBounds = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scrollView)

            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            scrollView.addSubview(label)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

                label.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
                label.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16)
            ])
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func configure(
            text: String,
            conversionRange: Range<Int>,
            nonTargetRanges: [Range<Int>]
        ) {
            let attributedText = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: attributedText.length)
            attributedText.addAttributes([
                .font: Self.font,
                .foregroundColor: UIColor.label
            ], range: fullRange)

            if let targetRange = nsRange(for: conversionRange, in: text) {
                attributedText.addAttributes([
                    .backgroundColor: UIColor.systemBlue.withAlphaComponent(0.18),
                    .font: Self.emphasizedFont
                ], range: targetRange)
            }

            for range in nonTargetRanges {
                guard let underlineRange = nsRange(for: range, in: text) else {
                    continue
                }
                attributedText.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: UIColor.secondaryLabel
                ], range: underlineRange)
            }

            label.attributedText = attributedText
            isHidden = false
        }

        func clear() {
            label.attributedText = nil
            isHidden = true
            scrollView.setContentOffset(.zero, animated: false)
        }

        private func nsRange(for range: Range<Int>, in text: String) -> NSRange? {
            let lowerBound = min(max(range.lowerBound, 0), text.count)
            let upperBound = min(max(range.upperBound, lowerBound), text.count)
            guard lowerBound < upperBound else {
                return nil
            }

            let lowerIndex = text.index(text.startIndex, offsetBy: lowerBound)
            let upperIndex = text.index(text.startIndex, offsetBy: upperBound)
            return NSRange(lowerIndex..<upperIndex, in: text)
        }
    }

    private final class ResizeHandleView: UIView {
        let position: ResizeHandlePosition

        init(position: ResizeHandlePosition) {
            self.position = position
            super.init(frame: .zero)

            backgroundColor = .systemBlue
            layer.cornerRadius = 8
            layer.borderWidth = 2
            layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) {
            return nil
        }
    }

    private final class KeyboardMoveHandleView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .systemBlue
            layer.cornerRadius = 18
            layer.borderWidth = 2
            layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
            translatesAutoresizingMaskIntoConstraints = false
            isAccessibilityElement = true
            accessibilityLabel = "キーボードの移動"

            let imageView = UIImageView(image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right"))
            imageView.tintColor = .white
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 19),
                imageView.heightAnchor.constraint(equalToConstant: 19)
            ])
        }

        required init?(coder: NSCoder) {
            return nil
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
            KanaKey(label: "あ", candidates: ["あ", "い", "う", "え", "お", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
            KanaKey(label: "か", candidates: ["か", "き", "く", "け", "こ"]),
            KanaKey(label: "さ", candidates: ["さ", "し", "す", "せ", "そ"])
        ],
        [
            KanaKey(label: "た", candidates: ["た", "ち", "つ", "て", "と", "っ"]),
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

    private let numberRows: [[KanaKey]] = [
        [
            KanaKey(label: "1★♪→", candidates: ["1", "★", "♪", "→"]),
            KanaKey(label: "2¥$€", candidates: ["2", "¥", "$", "€"]),
            KanaKey(label: "3%°#", candidates: ["3", "%", "°", "#"])
        ],
        [
            KanaKey(label: "4○*・", candidates: ["4", "○", "*", "・"]),
            KanaKey(label: "5+×÷", candidates: ["5", "+", "×", "÷"]),
            KanaKey(label: "6<=>", candidates: ["6", "<", "=", ">"])
        ],
        [
            KanaKey(label: "7「」:", candidates: ["7", "「", "」", ":"]),
            KanaKey(label: "8〒々〆", candidates: ["8", "〒", "々", "〆"]),
            KanaKey(label: "9^|\\", candidates: ["9", "^", "|", "\\"])
        ],
        [
            KanaKey(label: "()[]", candidates: ["(", ")", "[", "]"]),
            KanaKey(label: "0~⋯", candidates: ["0", "~", "⋯"]),
            KanaKey(label: ".,-/", candidates: [".", ",", "-", "/"])
        ]
    ]

    private var activeKeyLabel: String?
    private var activeCandidateIndex = 0
    private var activeKeyCandidates: [String] = []
    private var lastInsertedText = ""
    private var lastInputDate: Date?
    private var mainKeyboardPanel: MainKeyboardPanel = .text
    private var mainKeyboardContentMode: MainKeyboardContentMode = .keyboard
    private var sumireKeyboards = KeyboardSettings.keyboards
    private var currentSumireKeyboard = KeyboardSettings.currentKeyboard
    private var qwertyMode: QWERTYMode = .normal
    private var qwertyShiftEnabled = false
    private var qwertyCapsLockEnabled = false
    private var lastQWERTYShiftTapDate: Date?
    private var qwertyRawInput = ""
    private var preeditReadingPreviewEnabled = KeyboardSettings.preeditReadingPreviewEnabled
    private var omissionSearchEnabled = KeyboardSettings.omissionSearchEnabled
    private var inputStatus: InputStatus = .precomposition(PrecompositionStatus(
        language: .japanese,
        phase: .empty,
        liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
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
    private var candidateListCandidates: [ConversionCandidateItem] = []
    private var candidateListSelectedCandidateIndex: Int?
    private let preeditReadingView = PreeditReadingView()
    private let candidateRowContainer = UIStackView()
    private let candidateScrollView = UIScrollView()
    private let candidateStack = UIStackView()
    private let candidateToggleContainer = UIView()
    private let candidateListToggleButton = UIButton(type: .system)
    private let emptyPreeditToolbar = UIStackView()
    private let contentStack = UIStackView()
    private let keyboardStack = UIStackView()
    private let mainKeyboardContainer = UIView()
    private weak var candidateListCollectionView: UICollectionView?
    private let flickGuideView = FlickGuideView()
    private lazy var keyboardVisualModeController = KeyboardVisualModeController(contentRootView: keyboardStack)
    private lazy var cursorMoveController = CursorMoveController(
        trackingView: self.view,
        canBegin: { [weak self] in
            self?.canBeginSpaceCursorMoveMode == true
        },
        adjustTextPosition: { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        },
        onModeBegan: { [weak self] in
//            self?.beginSpaceCursorMoveMode()
        },
        onModeEnded: { [weak self] in
            self?.endSpaceCursorMoveMode()
        },
        onTrackingFinished: { [weak self] in
            self?.finishSpaceCursorMoveTracking()
        }
    )
    private var keyboardLayoutConstraints: [NSLayoutConstraint] = []
    private let conversionCandidateLimit = 10
    private let conversionBeamWidth = 20
    private let keyboardHorizontalInset = CGFloat(KeyboardSettings.defaultKeyboardLeadingOffset)
    private let keyboardBaseHeight = CGFloat(KeyboardSettings.defaultKeyboardHeight)
    private let keyboardDefaultBottomMargin = CGFloat(KeyboardSettings.defaultKeyboardBottomMargin)
    private let keyboardMinimumWidth: CGFloat = 260
    private let keyboardMinimumHeight: CGFloat = 190
    private let keyboardMaximumHeight: CGFloat = 520
    private let keyboardBottomMarginStep: CGFloat = 4
    private let keyboardMaximumBottomMargin: CGFloat = 80
    private let multiTapInterval: TimeInterval = 1.1
    private let flickThreshold: CGFloat = 22
    private var suppressNextButtonRelease = false
    private weak var activeKanaButton: KeyboardButton?
    private weak var activeKanaTouch: UITouch?
    private weak var spaceButton: KeyboardButton?
    private weak var activeQWERTYButton: KeyboardButton?
    private weak var activeQWERTYTouch: UITouch?
    private var qwertyButtons: [KeyboardButton] = []
    private var activeFlickDirection: FlickDirection = .center
    private var suppressedReleaseTouchIDs = Set<ObjectIdentifier>()
    private var suppressedReleaseButtonIDs = Set<ObjectIdentifier>()
    private var deleteRepeatTimer: Timer?
    private var cursorRepeatTimer: Timer?
    private var reverseCycleStateTimer: Timer?
    private weak var reverseCycleButton: KeyboardButton?
    private weak var modeSwitchButton: KeyboardButton?
    private var scheduledKanaKanjiLoad: DispatchWorkItem?
    private var kanaKanjiLoadGeneration = 0
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var appliedKeyboardOrientation: KeyboardSettings.KeyboardOrientation?
    private var currentLayoutMetrics = KeyboardSettings.KeyboardLayoutMetrics(
        width: nil,
        leadingOffset: KeyboardSettings.defaultKeyboardLeadingOffset,
        height: KeyboardSettings.defaultKeyboardHeight,
        bottomMargin: KeyboardSettings.defaultKeyboardBottomMargin
    )
    private var resizePanStartState: ResizePanStartState?
    private weak var resizeOverlayView: UIView?
    private static var cachedKanaKanjiConverter: KanaKanjiConverter?

    override func loadView() {
        let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        inputView.isMultipleTouchEnabled = true
        view = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        _ = syncSumireKeyboardSettings()
        configureInputStatusForCurrentSumireKeyboard()
        view.backgroundColor = KeyboardTheme.keyboardBackground
        view.clipsToBounds = false
        setupKeyboardLayout()
        updatePreedit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.backgroundColor = KeyboardTheme.keyboardBackground
        flickGuideView.setNeedsLayout()
        updatePreeditReadingPreview()
        candidateButtons.forEach { $0.setNeedsLayout() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyStoredKeyboardLayoutMetricsIfNeeded(force: true)
        scheduleKanaKanjiConverterLoad(delay: 0.25)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyStoredKeyboardLayoutMetricsIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncSharedSettings()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scheduledKanaKanjiLoad?.cancel()
        scheduledKanaKanjiLoad = nil
        stopDeleteRepeat()
        stopCursorRepeat()
        cursorMoveController.cancelTracking()
        stopReverseCycleStateTimer()
        exitKeyboardResizeMode()
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
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.distribution = .fill
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let candidateBar = makeCandidateBar()
        keyboardStack.axis = .horizontal
        keyboardStack.alignment = .fill
        keyboardStack.distribution = .fill
        keyboardStack.spacing = 6

        mainKeyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        preeditReadingView.isHidden = true
        contentStack.addArrangedSubview(candidateBar)
        contentStack.addArrangedSubview(keyboardStack)
        view.addSubview(contentStack)
        view.addSubview(flickGuideView)
        flickGuideView.isHidden = true

        let keyboardHeightConstraint = view.heightAnchor.constraint(equalToConstant: keyboardBaseHeight)
        keyboardHeightConstraint.priority = UILayoutPriority(999)
        self.keyboardHeightConstraint = keyboardHeightConstraint
        let contentBottomConstraint = contentStack.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -keyboardDefaultBottomMargin
        )
        self.contentBottomConstraint = contentBottomConstraint
        let contentLeadingConstraint = contentStack.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: keyboardHorizontalInset
        )
        let contentTrailingConstraint = contentStack.trailingAnchor.constraint(
            equalTo: view.trailingAnchor,
            constant: -keyboardHorizontalInset
        )
        self.contentLeadingConstraint = contentLeadingConstraint
        self.contentTrailingConstraint = contentTrailingConstraint

        NSLayoutConstraint.activate([
            keyboardHeightConstraint,

            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            contentLeadingConstraint,
            contentTrailingConstraint,
            contentBottomConstraint,

            candidateBar.heightAnchor.constraint(equalToConstant: 38)
        ])

        applyStoredKeyboardLayoutMetricsIfNeeded(force: true)

        rebuildKeyboardLayout()
        updateModeSwitchButtonTitle()
        updateReverseCycleButtonState()
    }

    private func makeCandidateBar() -> UIView {
        let candidateBar = UIStackView()
        candidateBar.axis = .vertical
        candidateBar.alignment = .fill
        candidateBar.distribution = .fill
        candidateBar.spacing = 0
        candidateBar.translatesAutoresizingMaskIntoConstraints = false

        candidateRowContainer.axis = .horizontal
        candidateRowContainer.alignment = .fill
        candidateRowContainer.distribution = .fill
        candidateRowContainer.spacing = 0
        candidateRowContainer.translatesAutoresizingMaskIntoConstraints = false

        candidateScrollView.showsHorizontalScrollIndicator = true
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.backgroundColor = .clear
        candidateScrollView.translatesAutoresizingMaskIntoConstraints = false

        candidateToggleContainer.backgroundColor = .clear
        candidateToggleContainer.translatesAutoresizingMaskIntoConstraints = false

        let toggleButton = makeCandidateListToggleButton()
        candidateToggleContainer.addSubview(toggleButton)

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.distribution = .fill
        candidateStack.spacing = 6
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScrollView.addSubview(candidateStack)
        configureEmptyPreeditToolbar()

        candidateRowContainer.addArrangedSubview(candidateScrollView)
        candidateRowContainer.addArrangedSubview(candidateToggleContainer)

        NSLayoutConstraint.activate([
            candidateStack.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor),

            // Toggle 領域を Auto Layout 上で分離し、候補が右端ボタンの下へ潜り込まないようにする。
            candidateToggleContainer.widthAnchor.constraint(equalToConstant: 42),
            toggleButton.centerXAnchor.constraint(equalTo: candidateToggleContainer.centerXAnchor),
            toggleButton.centerYAnchor.constraint(equalTo: candidateToggleContainer.centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 38),
            toggleButton.topAnchor.constraint(greaterThanOrEqualTo: candidateToggleContainer.topAnchor),
            toggleButton.bottomAnchor.constraint(lessThanOrEqualTo: candidateToggleContainer.bottomAnchor)
        ])

        candidateBar.addArrangedSubview(preeditReadingView)
        candidateBar.addArrangedSubview(candidateRowContainer)
        candidateBar.addArrangedSubview(emptyPreeditToolbar)
        emptyPreeditToolbar.isHidden = true
        updateCandidateListToggleAppearance()
        return candidateBar
    }

    private func makeCandidateListToggleButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 16,
            weight: .semibold
        )
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

        candidateListToggleButton.configuration = configuration
        candidateListToggleButton.backgroundColor = .clear
        candidateListToggleButton.tintColor = .label
        candidateListToggleButton.accessibilityLabel = "候補一覧を表示"
        candidateListToggleButton.addTarget(self, action: #selector(handleCandidateListToggle), for: .touchUpInside)
        candidateListToggleButton.translatesAutoresizingMaskIntoConstraints = false
        return candidateListToggleButton
    }

    private func configureEmptyPreeditToolbar() {
        guard emptyPreeditToolbar.arrangedSubviews.isEmpty else {
            return
        }

        emptyPreeditToolbar.axis = .horizontal
        emptyPreeditToolbar.alignment = .center
        emptyPreeditToolbar.distribution = .fill
        emptyPreeditToolbar.spacing = 6
        emptyPreeditToolbar.translatesAutoresizingMaskIntoConstraints = false

        let settingsButton = makeCandidateToolbarButton(
            systemImageName: "gearshape",
            accessibilityLabel: "設定",
            action: #selector(openKeyboardSettingsApp)
        )
        let resizeButton = makeCandidateToolbarButton(
            systemImageName: "arrow.up.left.and.arrow.down.right",
            accessibilityLabel: "キーボードのResize",
            action: #selector(enterKeyboardResizeMode)
        )
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        emptyPreeditToolbar.addArrangedSubview(settingsButton)
        emptyPreeditToolbar.addArrangedSubview(resizeButton)
        emptyPreeditToolbar.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: 40),
            resizeButton.widthAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func makeCandidateToolbarButton(
        systemImageName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: systemImageName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 16,
            weight: .semibold
        )
        configuration.baseBackgroundColor = KeyboardTheme.functionKeyBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func openKeyboardSettingsApp() {
        resetMultiTapState()
        hideFlickGuide()
        guard let url = KeyboardSettings.settingsURL else {
            return
        }
        extensionContext?.open(url, completionHandler: nil)
    }

    @objc private func enterKeyboardResizeMode() {
        guard resizeOverlayView == nil else {
            return
        }

        resetMultiTapState()
        hideFlickGuide()
        clearActiveKanaButton()
        clearActiveQWERTYButton()
        applyStoredKeyboardLayoutMetricsIfNeeded(force: true)

        let overlay = UIView()
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        resizeOverlayView = overlay

        addResizeOverlayControls(to: overlay)
        addResizeHandles(to: overlay)
        addKeyboardMoveHandle(to: overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.bringSubviewToFront(overlay)
    }

    private func addResizeOverlayControls(to overlay: UIView) {
        let topStack = UIStackView()
        topStack.axis = .horizontal
        topStack.alignment = .center
        topStack.distribution = .fill
        topStack.spacing = 8
        topStack.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = makeResizeOverlayButton(
            title: "デフォルト",
            systemImageName: "arrow.counterclockwise",
            action: #selector(resetKeyboardSizeToDefault)
        )
        let doneButton = makeResizeOverlayButton(
            title: "完了",
            systemImageName: "checkmark",
            action: #selector(exitKeyboardResizeMode)
        )
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        topStack.addArrangedSubview(resetButton)
        topStack.addArrangedSubview(topSpacer)
        topStack.addArrangedSubview(doneButton)

        let bottomStack = UIStackView()
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.distribution = .fill
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        let removeMarginButton = makeResizeOverlayButton(
            title: "下余白 -",
            systemImageName: "minus",
            action: #selector(removeKeyboardBottomMargin)
        )
        let addMarginButton = makeResizeOverlayButton(
            title: "下余白 +",
            systemImageName: "plus",
            action: #selector(addKeyboardBottomMargin)
        )
        let bottomSpacer = UIView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(removeMarginButton)
        bottomStack.addArrangedSubview(bottomSpacer)
        bottomStack.addArrangedSubview(addMarginButton)

        overlay.addSubview(topStack)
        overlay.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 8),
            topStack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 12),
            topStack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),

            bottomStack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -8)
        ])
    }

    private func makeResizeOverlayButton(
        title: String,
        systemImageName: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePadding = 5
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        configuration.baseBackgroundColor = KeyboardTheme.popupBackground.withAlphaComponent(0.92)
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func addResizeHandles(to overlay: UIView) {
        for position in ResizeHandlePosition.allCases {
            let handle = ResizeHandleView(position: position)
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
            handle.addGestureRecognizer(panGesture)
            overlay.addSubview(handle)

            NSLayoutConstraint.activate([
                handle.widthAnchor.constraint(equalToConstant: 28),
                handle.heightAnchor.constraint(equalToConstant: 28)
            ])

            switch position {
            case .topLeft:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.leadingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.topAnchor)
                ])
            case .top:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.topAnchor)
                ])
            case .topRight:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.trailingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.topAnchor)
                ])
            case .right:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.trailingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
                ])
            case .bottomRight:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.trailingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.bottomAnchor)
                ])
            case .bottom:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.bottomAnchor)
                ])
            case .bottomLeft:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.leadingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.bottomAnchor)
                ])
            case .left:
                NSLayoutConstraint.activate([
                    handle.centerXAnchor.constraint(equalTo: overlay.leadingAnchor),
                    handle.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
                ])
            }
        }
    }

    private func addKeyboardMoveHandle(to overlay: UIView) {
        let handle = KeyboardMoveHandleView()
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleKeyboardMovePan(_:)))
        handle.addGestureRecognizer(panGesture)
        overlay.addSubview(handle)

        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let handle = gesture.view as? ResizeHandleView else {
            return
        }

        if gesture.state == .began || resizePanStartState == nil {
            resizePanStartState = ResizePanStartState(
                metrics: currentLayoutMetrics,
                leadingOffset: currentResizableKeyboardLeadingOffset(),
                width: currentResizableKeyboardWidth(),
                height: CGFloat(currentLayoutMetrics.height),
                containerWidth: currentResizableKeyboardContainerWidth()
            )
        }

        let translation = gesture.translation(in: view)
        guard translation != .zero, let startState = resizePanStartState else {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                resizePanStartState = nil
            }
            return
        }

        var metrics = startState.metrics
        var leadingOffset = startState.leadingOffset
        var width = startState.width
        var height = startState.height

        if let horizontalEdge = handle.position.horizontalEdge {
            switch horizontalEdge {
            case .left:
                let rightEdge = startState.leadingOffset + startState.width
                let minimumLeadingOffset = keyboardHorizontalInset
                let maximumLeadingOffset = max(
                    minimumLeadingOffset,
                    rightEdge - keyboardMinimumWidth
                )
                leadingOffset = min(
                    max(startState.leadingOffset + translation.x, minimumLeadingOffset),
                    maximumLeadingOffset
                )
                width = rightEdge - leadingOffset
            case .right:
                let maximumWidth = max(
                    keyboardMinimumWidth,
                    startState.containerWidth - startState.leadingOffset - keyboardHorizontalInset
                )
                leadingOffset = startState.leadingOffset
                width = min(
                    max(startState.width + translation.x, keyboardMinimumWidth),
                    maximumWidth
                )
            }
            metrics.leadingOffset = Double(leadingOffset)
            metrics.width = Double(width)
        }
        if handle.position.verticalSign != 0 {
            height = startState.height + translation.y * handle.position.verticalSign
        }

        metrics.height = Double(height)
        applyKeyboardLayoutMetrics(metrics, persists: true)

        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            resizePanStartState = nil
        }
    }

    @objc private func handleKeyboardMovePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        guard translation.x != 0 else {
            return
        }

        var metrics = currentLayoutMetrics
        if metrics.width == nil {
            metrics.width = Double(currentResizableKeyboardWidth())
            metrics.leadingOffset = Double(currentResizableKeyboardLeadingOffset())
        }
        metrics.leadingOffset += Double(translation.x)
        applyKeyboardLayoutMetrics(metrics, persists: true)
        gesture.setTranslation(.zero, in: view)
    }

    @objc private func resetKeyboardSizeToDefault() {
        let orientation = currentKeyboardOrientation()
        KeyboardSettings.resetKeyboardLayoutMetrics(for: orientation)
        let metrics = KeyboardSettings.KeyboardLayoutMetrics(
            width: nil,
            leadingOffset: KeyboardSettings.defaultKeyboardLeadingOffset,
            height: KeyboardSettings.defaultKeyboardHeight,
            bottomMargin: KeyboardSettings.defaultKeyboardBottomMargin
        )
        appliedKeyboardOrientation = orientation
        applyKeyboardLayoutMetrics(metrics, persists: false)
    }

    @objc private func addKeyboardBottomMargin() {
        adjustKeyboardBottomMargin(by: keyboardBottomMarginStep)
    }

    @objc private func removeKeyboardBottomMargin() {
        adjustKeyboardBottomMargin(by: -keyboardBottomMarginStep)
    }

    private func adjustKeyboardBottomMargin(by delta: CGFloat) {
        var metrics = currentLayoutMetrics
        let nextMargin = CGFloat(metrics.bottomMargin) + delta
        metrics.bottomMargin = Double(nextMargin)
        applyKeyboardLayoutMetrics(metrics, persists: true)
    }

    @objc private func exitKeyboardResizeMode() {
        resizePanStartState = nil
        resizeOverlayView?.removeFromSuperview()
        resizeOverlayView = nil
    }

    private func applyStoredKeyboardLayoutMetricsIfNeeded(force: Bool = false) {
        let orientation = currentKeyboardOrientation()
        guard force || appliedKeyboardOrientation != orientation else {
            return
        }

        appliedKeyboardOrientation = orientation
        let metrics = KeyboardSettings.keyboardLayoutMetrics(for: orientation)
        applyKeyboardLayoutMetrics(metrics, persists: false)
    }

    private func applyKeyboardLayoutMetrics(
        _ metrics: KeyboardSettings.KeyboardLayoutMetrics,
        persists: Bool
    ) {
        let orientation = currentKeyboardOrientation()
        let sanitizedMetrics = sanitizedKeyboardLayoutMetrics(metrics)
        currentLayoutMetrics = sanitizedMetrics

        let leadingOffset = CGFloat(sanitizedMetrics.leadingOffset)
        contentLeadingConstraint?.constant = leadingOffset
        if let width = sanitizedMetrics.width {
            let trailingInset = max(
                keyboardHorizontalInset,
                currentResizableKeyboardContainerWidth() - leadingOffset - CGFloat(width)
            )
            contentTrailingConstraint?.constant = -trailingInset
        } else {
            contentTrailingConstraint?.constant = -keyboardHorizontalInset
        }

        keyboardHeightConstraint?.constant = CGFloat(sanitizedMetrics.height)
        contentBottomConstraint?.constant = -CGFloat(sanitizedMetrics.bottomMargin)

        if persists {
            KeyboardSettings.saveKeyboardLayoutMetrics(sanitizedMetrics, for: orientation)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func sanitizedKeyboardLayoutMetrics(
        _ metrics: KeyboardSettings.KeyboardLayoutMetrics
    ) -> KeyboardSettings.KeyboardLayoutMetrics {
        let maximumWidth = keyboardMaximumWidth()
        let width = metrics.width.map {
            min(max($0, Double(keyboardMinimumWidth)), Double(maximumWidth))
        }
        let leadingOffset: Double
        if let width {
            let maximumLeadingOffset = max(
                keyboardHorizontalInset,
                currentResizableKeyboardContainerWidth() - CGFloat(width) - keyboardHorizontalInset
            )
            leadingOffset = Double(
                min(
                    max(CGFloat(metrics.leadingOffset), keyboardHorizontalInset),
                    maximumLeadingOffset
                )
            )
        } else {
            leadingOffset = Double(keyboardHorizontalInset)
        }
        let height = min(max(metrics.height, Double(keyboardMinimumHeight)), Double(keyboardMaximumHeight))
        let bottomMargin = min(
            max(metrics.bottomMargin, 0),
            Double(keyboardMaximumBottomMargin)
        )

        return KeyboardSettings.KeyboardLayoutMetrics(
            width: width,
            leadingOffset: leadingOffset,
            height: height,
            bottomMargin: bottomMargin
        )
    }

    private func currentResizableKeyboardWidth() -> CGFloat {
        if let width = currentLayoutMetrics.width {
            return CGFloat(width)
        }
        if contentStack.bounds.width > 0 {
            return contentStack.bounds.width
        }
        if view.bounds.width > 0 {
            return view.bounds.width
        }
        return defaultKeyboardWidth(for: currentKeyboardOrientation())
    }

    private func currentResizableKeyboardLeadingOffset() -> CGFloat {
        let leadingOffset = contentStack.frame.minX
        if leadingOffset > 0 {
            return leadingOffset
        }
        return keyboardHorizontalInset
    }

    private func currentResizableKeyboardContainerWidth() -> CGFloat {
        if view.bounds.width > 0 {
            return view.bounds.width
        }
        if let superviewWidth = view.superview?.bounds.width, superviewWidth > 0 {
            return superviewWidth
        }
        return defaultKeyboardWidth(for: currentKeyboardOrientation())
    }

    private func currentKeyboardOrientation() -> KeyboardSettings.KeyboardOrientation {
        if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation {
            return interfaceOrientation.isLandscape ? .landscape : .portrait
        }

        let screenSize = UIScreen.main.bounds.size
        return screenSize.width > screenSize.height ? .landscape : .portrait
    }

    private func defaultKeyboardWidth(for orientation: KeyboardSettings.KeyboardOrientation) -> CGFloat {
        let screenSize = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        switch orientation {
        case .portrait:
            return min(screenSize.width, screenSize.height)
        case .landscape:
            return max(screenSize.width, screenSize.height)
        }
    }

    private func keyboardMaximumWidth() -> CGFloat {
        max(
            keyboardMinimumWidth,
            currentResizableKeyboardContainerWidth() - keyboardHorizontalInset * 2
        )
    }

    private func rebuildKeyboardLayout(resetCandidateListMode: Bool = true) {
        cursorMoveController.cancelTracking()
        keyboardVisualModeController.setMode(.normal)
        if resetCandidateListMode {
            mainKeyboardContentMode = .keyboard
            updateCandidateListToggleAppearance()
        }
        NSLayoutConstraint.deactivate(keyboardLayoutConstraints)
        keyboardLayoutConstraints.removeAll()

        for arrangedSubview in keyboardStack.arrangedSubviews {
            keyboardStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        reverseCycleButton = nil
        modeSwitchButton = nil
        spaceButton = nil
        clearActiveKanaButton()
        clearActiveQWERTYButton()
        suppressedReleaseTouchIDs.removeAll()
        suppressedReleaseButtonIDs.removeAll()
        qwertyButtons.removeAll()

        if mainKeyboardContentMode == .candidateList {
            rebuildMainKeyboardPanel()
            keyboardStack.addArrangedSubview(mainKeyboardContainer)
        } else if currentSumireKeyboard.kind == .qwerty {
            let qwertyPanel = mainKeyboardPanel == .emoji ? makeEmojiPlaceholderView() : makeQWERTYKeyboard()
            keyboardStack.addArrangedSubview(qwertyPanel)
        } else {
            let leftControlColumn = makeLeftControlColumn()
            let controlColumn = makeControlColumn()
            rebuildMainKeyboardPanel()

            keyboardStack.addArrangedSubview(leftControlColumn)
            keyboardStack.addArrangedSubview(mainKeyboardContainer)
            keyboardStack.addArrangedSubview(controlColumn)

            keyboardLayoutConstraints = [
                leftControlColumn.widthAnchor.constraint(equalTo: mainKeyboardContainer.widthAnchor, multiplier: 0.28),
                controlColumn.widthAnchor.constraint(equalTo: mainKeyboardContainer.widthAnchor, multiplier: 0.28)
            ]
            NSLayoutConstraint.activate(keyboardLayoutConstraints)
        }

        updateModeSwitchButtonTitle()
        updateReverseCycleButtonState()
        updateSpaceButtonTitle()
    }

    private func rebuildMainKeyboardPanel() {
        mainKeyboardContainer.subviews.forEach { $0.removeFromSuperview() }

        let panel: UIView
        if mainKeyboardContentMode == .candidateList {
            panel = makeCandidateListView()
        } else {
            switch mainKeyboardPanel {
            case .text:
                panel = makeKeyGrid()
            case .emoji:
                panel = makeEmojiPlaceholderView()
            }
        }

        panel.translatesAutoresizingMaskIntoConstraints = false
        mainKeyboardContainer.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: mainKeyboardContainer.topAnchor),
            panel.leadingAnchor.constraint(equalTo: mainKeyboardContainer.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: mainKeyboardContainer.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: mainKeyboardContainer.bottomAnchor)
        ])
    }

    private func makeCandidateListView() -> UIView {
        refreshCandidateListSnapshot()

        let layout = LeftAlignedCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            CandidateListCell.self,
            forCellWithReuseIdentifier: CandidateListCell.reuseIdentifier
        )
        DispatchQueue.main.async { [weak self, weak collectionView] in
            guard let self, let collectionView else {
                return
            }
            self.scrollCandidateListPastFirstRowIfPossible(collectionView)
        }

        // 候補がない場合も一覧モードのままにし、下段全体に明示的な空状態を表示する。
        collectionView.backgroundView = candidateListCandidates.isEmpty ? makeCandidateListPlaceholderView() : nil
        candidateListCollectionView = collectionView
        return collectionView
    }

    private func makeCandidateListPlaceholderView() -> UIView {
        let placeholder = UILabel()
        placeholder.text = "候補がありません"
        placeholder.textColor = .secondaryLabel
        placeholder.font = .systemFont(ofSize: 15, weight: .medium)
        placeholder.textAlignment = .center
        return placeholder
    }

    private func refreshCandidateListSnapshot() {
        candidateListCandidates = currentCandidateItems()
        candidateListSelectedCandidateIndex = currentSelectedCandidateIndex(
            candidateCount: candidateListCandidates.count
        )
    }

    private func scrollCandidateListPastFirstRowIfPossible(_ collectionView: UICollectionView) {
        guard collectionView === candidateListCollectionView else {
            return
        }

        collectionView.layoutIfNeeded()

        guard collectionView.bounds.height > 0,
              collectionView.contentSize.height > collectionView.bounds.height,
              candidateListCandidates.count > 1 else {
            return
        }

        let attributes = candidateListCandidates.indices.compactMap {
            collectionView.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
        }
        guard let firstRowMinY = attributes.map(\.frame.minY).min(),
              let secondRowMinY = attributes
                .map(\.frame.minY)
                .filter({ $0 > firstRowMinY + 1 })
                .min() else {
            return
        }

        let sectionTopInset = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset.top ?? 0
        let targetOffsetY = max(0, secondRowMinY - sectionTopInset)
        let maximumOffsetY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let offsetY = min(targetOffsetY, maximumOffsetY)

        guard offsetY > 0 else {
            return
        }

        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        candidateListCandidates.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CandidateListCell.reuseIdentifier,
            for: indexPath
        ) as? CandidateListCell else {
            return UICollectionViewCell()
        }

        let isLastItem = indexPath.item == candidateListCandidates.count - 1
        cell.configure(
            title: candidateListCandidates[indexPath.item].text,
            showsDivider: isLastItem == false,
            isSelected: indexPath.item == candidateListSelectedCandidateIndex
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard candidateListCandidates.indices.contains(indexPath.item) else {
            return
        }

        commitCandidateItem(candidateListCandidates[indexPath.item])
    }

    @objc private func handleCandidateListToggle() {
        resetMultiTapState()
        hideFlickGuide()

        guard currentSumireKeyboard.kind != .qwerty else {
            resetMainKeyboardContentModeToKeyboard()
            return
        }

        mainKeyboardContentMode = mainKeyboardContentMode == .candidateList ? .keyboard : .candidateList
        rebuildKeyboardLayout(resetCandidateListMode: false)
        updateCandidateListToggleAppearance()
    }

    private func updateCandidateListToggleAppearance() {
        let showsCandidateList = mainKeyboardContentMode == .candidateList
        let imageName = showsCandidateList ? "chevron.up" : "chevron.down"

        var configuration = candidateListToggleButton.configuration ?? UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: imageName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 16,
            weight: .semibold
        )
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        candidateListToggleButton.configuration = configuration

        let canToggle = currentSumireKeyboard.kind != .qwerty
        candidateListToggleButton.isEnabled = canToggle
        candidateListToggleButton.alpha = canToggle ? 1 : 0.35
        candidateListToggleButton.accessibilityLabel = showsCandidateList ? "通常のキーボードを表示" : "候補一覧を表示"
    }

    private func resetMainKeyboardContentModeToKeyboard(rebuildsPanel: Bool = true) {
        guard mainKeyboardContentMode != .keyboard else {
            updateCandidateListToggleAppearance()
            return
        }

        mainKeyboardContentMode = .keyboard
        if rebuildsPanel {
            rebuildKeyboardLayout(resetCandidateListMode: false)
        }
        updateCandidateListToggleAppearance()
    }

    private func makeKeyGrid() -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.alignment = .fill
        grid.distribution = .fillEqually
        grid.spacing = 6

        for row in currentKeyRows() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6

            for key in row {
                let action = action(for: key)
                let button = KeyboardButton(title: key.label, action: action, style: .kana)
                if currentPrecompositionStatus?.language == .number {
                    if let display = numberKeyDisplay(for: key) {
                        button.configureStackedTitle(primary: display.primary, secondary: display.secondary)
                    }
                } else if key.label == "゛゜小" {
                    button.configureStackedTitle(
                        primary: "゛゜",
                        secondary: "小",
                        primaryFontSize: 22,
                        secondaryFontSize: 16
                    )
                }
                configureInputTargets(for: button)
                rowStack.addArrangedSubview(button)
            }

            grid.addArrangedSubview(rowStack)
        }

        return grid
    }

    private func makeQWERTYKeyboard() -> UIStackView {
        let keyboard = UIStackView()
        keyboard.axis = .vertical
        keyboard.alignment = .fill
        keyboard.distribution = .fillEqually
        keyboard.spacing = 6

        for row in qwertyRows() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            rowStack.spacing = 6

            var rowButtons: [(button: KeyboardButton, span: CGFloat)] = []
            for key in row {
                let button = KeyboardButton(
                    title: key.title,
                    systemImageName: key.systemImageName,
                    symbolPointSize: key.symbolPointSize,
                    action: key.action,
                    style: key.style
                )
                if case .space = key.action {
                    spaceButton = button
                }
                qwertyButtons.append(button)
                if case .nextKeyboard = key.action {
                    configureKeyboardSwitchTargets(for: button)
                } else {
                    configureInputTargets(for: button)
                }
                rowStack.addArrangedSubview(button)
                rowButtons.append((button, key.span))
            }

            applyQWERTYSpans(rowButtons)
            keyboard.addArrangedSubview(rowStack)
        }

        return keyboard
    }

    private func applyQWERTYSpans(_ rowButtons: [(button: KeyboardButton, span: CGFloat)]) {
        guard let reference = rowButtons.first,
              reference.span > 0 else {
            return
        }

        for entry in rowButtons.dropFirst() where entry.span > 0 {
            entry.button.widthAnchor.constraint(
                equalTo: reference.button.widthAnchor,
                multiplier: entry.span / reference.span
            ).isActive = true
        }
    }

    private struct QWERTYKey {
        let title: String?
        let systemImageName: String?
        let symbolPointSize: CGFloat
        let action: KeyAction
        let style: ButtonStyle
        let span: CGFloat

        init(
            title: String,
            action: KeyAction,
            style: ButtonStyle = .kana,
            span: CGFloat = 1
        ) {
            self.title = title
            self.systemImageName = nil
            self.symbolPointSize = 19
            self.action = action
            self.style = style
            self.span = span
        }

        init(
            systemImageName: String,
            symbolPointSize: CGFloat = 19,
            action: KeyAction,
            style: ButtonStyle = .function,
            span: CGFloat = 1
        ) {
            self.title = nil
            self.systemImageName = systemImageName
            self.symbolPointSize = symbolPointSize
            self.action = action
            self.style = style
            self.span = span
        }
    }

    private struct RomajiKanaSegment {
        let rawLength: Int
        let output: String
    }

    private func qwertyRows() -> [[QWERTYKey]] {
        switch qwertyMode {
        case .normal:
            return qwertyNormalRows()
        case .symbols:
            return qwertySymbolRows()
        case .moreSymbols:
            return qwertyMoreSymbolRows()
        }
    }

    private func qwertyNormalRows() -> [[QWERTYKey]] {
        let firstRow = "qwertyuiop".map { qwertyLetterKey(String($0)) }
        let secondRow = "asdfghjkl".map { qwertyLetterKey(String($0)) }
        let thirdRow: [QWERTYKey] = [
            QWERTYKey(systemImageName: qwertyShiftIconName, action: .qwertyShift),
            qwertyLetterKey("z"),
            qwertyLetterKey("x"),
            qwertyLetterKey("c"),
            qwertyLetterKey("v"),
            qwertyLetterKey("b"),
            qwertyLetterKey("n"),
            qwertyLetterKey("m"),
            QWERTYKey(title: "⌫", action: .delete, style: .function)
        ]
        var fourthRow: [QWERTYKey] = [
            QWERTYKey(systemImageName: "globe", symbolPointSize: 18, action: .nextKeyboard),
            QWERTYKey(title: "123", action: .qwertySwitchSymbols, style: .function),
            QWERTYKey(systemImageName: "face.smiling", symbolPointSize: 18, action: .emojiKeyboard),
            QWERTYKey(title: "空白", action: .space, style: .kana, span: 4),
            QWERTYKey(title: "Enter", action: .enter, style: .primary, span: 2)
        ]
        if currentSumireKeyboard.qwertyLanguage == .english {
            fourthRow.insert(
                QWERTYKey(title: ".", action: .qwertyText("."), style: .kana),
                at: fourthRow.count - 1
            )
        }

        return [firstRow, secondRow, thirdRow, fourthRow]
    }

    private func qwertySymbolRows() -> [[QWERTYKey]] {
        [
            "1234567890".map { qwertyTextKey(String($0)) },
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map(qwertyTextKey),
            [
                QWERTYKey(title: "#+=", action: .qwertySwitchSymbolPage, style: .function),
                qwertyTextKey("."),
                qwertyTextKey(","),
                qwertyTextKey("?"),
                qwertyTextKey("!"),
                qwertyTextKey("'"),
                QWERTYKey(title: "⌫", action: .delete, style: .function)
            ],
            [
                QWERTYKey(systemImageName: "globe", symbolPointSize: 18, action: .nextKeyboard),
                QWERTYKey(title: qwertyNormalModeTitle, action: .qwertySwitchSymbols, style: .function, span: 1.35),
                QWERTYKey(systemImageName: "face.smiling", symbolPointSize: 18, action: .emojiKeyboard),
                QWERTYKey(title: "空白", action: .space, style: .kana, span: 5),
                QWERTYKey(title: "Enter", action: .enter, style: .primary, span: 2)
            ]
        ]
    }

    private func qwertyMoreSymbolRows() -> [[QWERTYKey]] {
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map(qwertyTextKey),
            ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "・"].map(qwertyTextKey),
            [
                QWERTYKey(title: "123", action: .qwertySwitchSymbolPage, style: .function),
                qwertyTextKey("."),
                qwertyTextKey(","),
                qwertyTextKey("?"),
                qwertyTextKey("!"),
                qwertyTextKey("'"),
                QWERTYKey(title: "⌫", action: .delete, style: .function)
            ],
            [
                QWERTYKey(systemImageName: "globe", symbolPointSize: 18, action: .nextKeyboard),
                QWERTYKey(title: qwertyNormalModeTitle, action: .qwertySwitchSymbols, style: .function, span: 1.35),
                QWERTYKey(systemImageName: "face.smiling", symbolPointSize: 18, action: .emojiKeyboard),
                QWERTYKey(title: "空白", action: .space, style: .kana, span: 5),
                QWERTYKey(title: "Enter", action: .enter, style: .primary, span: 2)
            ]
        ]
    }

    private func qwertyLetterKey(_ letter: String) -> QWERTYKey {
        let displayedLetter = qwertyShiftEnabled || qwertyCapsLockEnabled ? letter.uppercased() : letter.lowercased()
        return QWERTYKey(title: displayedLetter, action: .qwertyText(displayedLetter))
    }

    private func qwertyTextKey(_ text: String) -> QWERTYKey {
        QWERTYKey(title: qwertyDisplayText(for: text), action: .qwertyText(text))
    }

    private func qwertyDisplayText(for text: String) -> String {
        guard currentSumireKeyboard.qwertyLanguage == .japanese else {
            return text
        }

        switch text {
        case ".":
            return "。"
        case ",":
            return "、"
        default:
            return text
        }
    }

    private var qwertyNormalModeTitle: String {
        if currentSumireKeyboard.qwertyLanguage == .english {
            return "ABC"
        }
        return "あいう"
    }

    private var qwertyShiftIconName: String {
        if qwertyCapsLockEnabled {
            return "capslock.fill"
        }
        return qwertyShiftEnabled ? "shift.fill" : "shift"
    }

    private static let romajiKanaMap: [String: String] = [
        "-": "ー",
        "~": "〜",
        ".": "。",
        ",": "、",
        "z/": "・",
        "z.": "…",
        "z,": "‥",
        "zh": "←",
        "zj": "↓",
        "zk": "↑",
        "zl": "→",
        "z-": "〜",
        "z[": "『",
        "z]": "』",
        "[": "「",
        "]": "」",

        "a": "あ",
        "i": "い",
        "u": "う",
        "e": "え",
        "o": "お",

        "ka": "か",
        "ki": "き",
        "ku": "く",
        "ke": "け",
        "ko": "こ",
        "ca": "か",
        "cu": "く",
        "co": "こ",
        "kya": "きゃ",
        "kyi": "きぃ",
        "kyu": "きゅ",
        "kye": "きぇ",
        "kyo": "きょ",

        "ga": "が",
        "gi": "ぎ",
        "gu": "ぐ",
        "ge": "げ",
        "go": "ご",
        "gya": "ぎゃ",
        "gyi": "ぎぃ",
        "gyu": "ぎゅ",
        "gye": "ぎぇ",
        "gyo": "ぎょ",

        "sa": "さ",
        "si": "し",
        "su": "す",
        "se": "せ",
        "so": "そ",
        "sha": "しゃ",
        "shi": "し",
        "shu": "しゅ",
        "she": "しぇ",
        "sho": "しょ",
        "sya": "しゃ",
        "syi": "しぃ",
        "syu": "しゅ",
        "sye": "しぇ",
        "syo": "しょ",

        "za": "ざ",
        "zi": "じ",
        "zu": "ず",
        "ze": "ぜ",
        "zo": "ぞ",
        "ja": "じゃ",
        "ji": "じ",
        "ju": "じゅ",
        "je": "じぇ",
        "jo": "じょ",
        "jya": "じゃ",
        "jyi": "じぃ",
        "jyu": "じゅ",
        "jye": "じぇ",
        "jyo": "じょ",
        "zya": "じゃ",
        "zyi": "じぃ",
        "zyu": "じゅ",
        "zye": "じぇ",
        "zyo": "じょ",

        "ta": "た",
        "ti": "ち",
        "tu": "つ",
        "te": "て",
        "to": "と",
        "chi": "ち",
        "tsu": "つ",
        "cha": "ちゃ",
        "chu": "ちゅ",
        "che": "ちぇ",
        "cho": "ちょ",
        "tya": "ちゃ",
        "tyi": "ちぃ",
        "tyu": "ちゅ",
        "tye": "ちぇ",
        "tyo": "ちょ",
        "tsa": "つぁ",
        "tsi": "つぃ",
        "tse": "つぇ",
        "tso": "つぉ",

        "da": "だ",
        "di": "ぢ",
        "du": "づ",
        "de": "で",
        "do": "ど",
        "dya": "ぢゃ",
        "dyi": "ぢぃ",
        "dyu": "ぢゅ",
        "dye": "ぢぇ",
        "dyo": "ぢょ",

        "na": "な",
        "ni": "に",
        "nu": "ぬ",
        "ne": "ね",
        "no": "の",
        "nya": "にゃ",
        "nyi": "にぃ",
        "nyu": "にゅ",
        "nye": "にぇ",
        "nyo": "にょ",

        "ha": "は",
        "hi": "ひ",
        "hu": "ふ",
        "he": "へ",
        "ho": "ほ",
        "fu": "ふ",
        "hya": "ひゃ",
        "hyi": "ひぃ",
        "hyu": "ひゅ",
        "hye": "ひぇ",
        "hyo": "ひょ",
        "fa": "ふぁ",
        "fi": "ふぃ",
        "fe": "ふぇ",
        "fo": "ふぉ",
        "fya": "ふゃ",
        "fyu": "ふゅ",
        "fyo": "ふょ",

        "ba": "ば",
        "bi": "び",
        "bu": "ぶ",
        "be": "べ",
        "bo": "ぼ",
        "bya": "びゃ",
        "byi": "びぃ",
        "byu": "びゅ",
        "bye": "びぇ",
        "byo": "びょ",

        "pa": "ぱ",
        "pi": "ぴ",
        "pu": "ぷ",
        "pe": "ぺ",
        "po": "ぽ",
        "pya": "ぴゃ",
        "pyi": "ぴぃ",
        "pyu": "ぴゅ",
        "pye": "ぴぇ",
        "pyo": "ぴょ",

        "ma": "ま",
        "mi": "み",
        "mu": "む",
        "me": "め",
        "mo": "も",
        "mya": "みゃ",
        "myi": "みぃ",
        "myu": "みゅ",
        "mye": "みぇ",
        "myo": "みょ",

        "ya": "や",
        "yi": "い",
        "yu": "ゆ",
        "ye": "いぇ",
        "yo": "よ",

        "ra": "ら",
        "ri": "り",
        "ru": "る",
        "re": "れ",
        "ro": "ろ",
        "rya": "りゃ",
        "ryi": "りぃ",
        "ryu": "りゅ",
        "rye": "りぇ",
        "ryo": "りょ",

        "wa": "わ",
        "wi": "うぃ",
        "wu": "う",
        "we": "うぇ",
        "wo": "を",
        "wha": "うぁ",
        "whi": "うぃ",
        "whu": "う",
        "whe": "うぇ",
        "who": "うぉ",

        "va": "ゔぁ",
        "vi": "ゔぃ",
        "vu": "ゔ",
        "ve": "ゔぇ",
        "vo": "ゔぉ",
        "vya": "ゔゃ",
        "vyi": "ゔぃ",
        "vyu": "ゔゅ",
        "vye": "ゔぇ",
        "vyo": "ゔょ",

        "la": "ぁ",
        "li": "ぃ",
        "lu": "ぅ",
        "le": "ぇ",
        "lo": "ぉ",
        "xa": "ぁ",
        "xi": "ぃ",
        "xu": "ぅ",
        "xe": "ぇ",
        "xo": "ぉ",
        "lya": "ゃ",
        "lyu": "ゅ",
        "lyo": "ょ",
        "xya": "ゃ",
        "xyu": "ゅ",
        "xyo": "ょ",
        "ltu": "っ",
        "xtu": "っ",
        "ltsu": "っ",
        "xtsu": "っ",
        "lwa": "ゎ",
        "xwa": "ゎ",
        "nn": "ん"
    ]

    private static let romajiKanaMaxKeyLength = romajiKanaMap.keys.map(\.count).max() ?? 1

    private func currentKeyRows() -> [[KanaKey]] {
        guard let language = currentPrecompositionStatus?.language else {
            return kanaRows
        }

        switch language {
        case .japanese:
            return kanaRows
        case .english:
            return englishRows()
        case .number:
            return numberRows
        }
    }

    private func englishRows() -> [[KanaKey]] {
        return [
            [
                KanaKey(label: "@#/&_", candidates: ["@", "#", "/", "&", "_"]),
                englishKey("ABC"),
                englishKey("DEF")
            ],
            [
                englishKey("GHI"),
                englishKey("JKL"),
                englishKey("MNO")
            ],
            [
                englishKey("PQRS"),
                englishKey("TUV"),
                englishKey("WXYZ")
            ],
            [
                KanaKey(label: "a/A", candidates: []),
                KanaKey(label: "'\"()", candidates: ["'", "\"", "(", ")"]),
                KanaKey(label: ".,!?", candidates: [".", ",", "!", "?"])
            ]
        ]
    }

    private func englishKey(_ label: String) -> KanaKey {
        let lowercasedCandidates = label.map { String($0).lowercased() }
        let uppercasedCandidates = label.map { String($0).uppercased() }
        return KanaKey(label: label, candidates: lowercasedCandidates + uppercasedCandidates)
    }

    private func action(for key: KanaKey) -> KeyAction {
        if currentPrecompositionStatus?.language == .number {
            return .flickOnly(key)
        }

        if key.label == "゛゜小" {
            return .transform
        }

        if key.label == "a/A" {
            return .togglePreviousAlphabetCase
        }

        return .kana(key)
    }

    private func numberKeyDisplay(for key: KanaKey) -> (primary: String, secondary: String)? {
        guard key.label != "()[]", key.label != ".,-/" else {
            return nil
        }

        guard let first = key.candidates.first else {
            return nil
        }

        return (first, key.candidates.dropFirst().joined())
    }

    private func makeEmojiPlaceholderView() -> UIView {
        let container = UIView()
        container.backgroundColor = KeyboardTheme.keyBackground.withAlphaComponent(0.36)
        container.layer.cornerRadius = 8
        container.layer.masksToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
//
        let icon = UIImageView(image: UIImage(systemName: "face.smiling"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "絵文字"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label

        let messageLabel = UILabel()
        messageLabel.text = "絵文字辞書を準備中"
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
//            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12)
        ])

        return container
    }

    private func makeLeftControlColumn() -> UIStackView {
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .fill
        column.distribution = .fillEqually
        column.spacing = 6

        let flickModeLayout = usesFlickOnlyLayout
        let language = currentPrecompositionStatus?.language ?? .japanese
        let reverseButton = KeyboardButton(
            title: flickModeLayout ? primaryFlickModeSwitchTitle(for: language) : nil,
            systemImageName: flickModeLayout ? nil : "arrow.counterclockwise",
            symbolPointSize: 16,
            action: flickModeLayout ? primaryFlickModeSwitchAction(for: language) : .reverseCycle,
            style: .function
        )
        if flickModeLayout == false {
            reverseCycleButton = reverseButton
        }
        configureInputTargets(for: reverseButton)
        column.addArrangedSubview(reverseButton)

        let modeButton = KeyboardButton(
            title: flickModeLayout ? secondaryFlickModeSwitchTitle(for: language) : "ABC",
            action: flickModeLayout ? secondaryFlickModeSwitchAction(for: language) : .switchMode,
            style: .function
        )
        if flickModeLayout == false {
            modeSwitchButton = modeButton
        }
        configureInputTargets(for: modeButton)
        column.addArrangedSubview(modeButton)

        let emojiButton = KeyboardButton(
            systemImageName: "face.smiling",
            symbolPointSize: 16,
            action: .emojiKeyboard,
            style: .function
        )
        configureInputTargets(for: emojiButton)
        column.addArrangedSubview(emojiButton)

        let keyboardButton = KeyboardButton(
            systemImageName: "globe",
            symbolPointSize: 16,
            action: .nextKeyboard,
            style: .function
        )
        configureKeyboardSwitchTargets(for: keyboardButton)
        column.addArrangedSubview(keyboardButton)

        return column
    }

    private var usesFlickOnlyLayout: Bool {
        currentSumireKeyboard.kind == .japaneseFlick
            && KeyboardSettings.japaneseFlickInputMode == .flick
    }

    private func primaryFlickModeSwitchTitle(for language: PrecompositionLanguage) -> String {
        switch language {
        case .japanese:
            return "ABC"
        case .english, .number:
            return "あいう"
        }
    }

    private func primaryFlickModeSwitchAction(for language: PrecompositionLanguage) -> KeyAction {
        switch language {
        case .japanese:
            return .switchToEnglish
        case .english, .number:
            return .switchToJapanese
        }
    }

    private func secondaryFlickModeSwitchTitle(for language: PrecompositionLanguage) -> String {
        switch language {
        case .japanese, .english:
            return "123"
        case .number:
            return "ABC"
        }
    }

    private func secondaryFlickModeSwitchAction(for language: PrecompositionLanguage) -> KeyAction {
        switch language {
        case .japanese, .english:
            return .switchToNumber
        case .number:
            return .switchToEnglish
        }
    }

    private func configureKeyboardSwitchTargets(for button: KeyboardButton) {
        button.addTarget(
            self,
            action: #selector(handleKeyboardSwitchInputModeList(_:event:)),
            for: .allTouchEvents
        )
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
        button.usesTapOnlyHighlight = keyRequiringFlickTracking(from: button.action) != nil

        if case .kana = button.action {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleKanaLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            button.addGestureRecognizer(longPress)
        } else if case .flickOnly = button.action {
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
        } else if case .space = button.action {
            button.addGestureRecognizer(cursorMoveController.makeSpaceLongPressGestureRecognizer())
        } else if case .delete = button.action {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            button.addGestureRecognizer(longPress)
        }
    }

    @objc private func handleTouchDown(_ sender: KeyboardButton, event: UIEvent) {
        guard cursorMoveController.isCursorMoveMode == false else {
            return
        }

        if currentSumireKeyboard.kind == .qwerty, isQWERTYSelectableAction(sender.action) {
            releaseActiveQWERTYButtonIfNeeded(beforeActivating: sender)
            setActiveQWERTYButton(sender)
            activeQWERTYTouch = touch(for: sender, event: event)
            hideFlickGuide()
            return
        }

        releaseActiveKanaButtonIfNeeded(beforeActivating: sender)
        guard keyRequiringFlickTracking(from: sender.action) != nil else {
            return
        }

        activeKanaButton = sender
        activeKanaTouch = touch(for: sender, event: event)
        activeFlickDirection = .center
        hideFlickGuide()
    }

    @objc private func handleTouchDrag(_ sender: KeyboardButton, event: UIEvent) {
        guard cursorMoveController.isCursorMoveMode == false else {
            return
        }

        if currentSumireKeyboard.kind == .qwerty {
            updateActiveQWERTYButton(from: event, fallback: sender)
            return
        }

        guard let key = keyRequiringFlickTracking(from: sender.action) else {
            return
        }

        activeKanaButton = sender
        activeKanaTouch = touch(for: sender, event: event) ?? activeKanaTouch
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
        if cursorMoveController.isCursorMoveMode {
            cursorMoveController.cancelTracking()
            sender.isHighlighted = false
            return
        }

        if shouldSuppressRelease(for: sender, event: nil) {
            sender.isHighlighted = false
            return
        }

        stopDeleteRepeat()
        stopCursorRepeat()
        clearActiveKanaButton()
        clearActiveQWERTYButton()
        activeFlickDirection = .center
        hideFlickGuide()
    }

    @objc private func handleKanaLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? KeyboardButton,
              let key = keyRequiringFlickTracking(from: button.action) else {
            return
        }

        releaseActiveKanaButtonIfNeeded(beforeActivating: button)
        activeKanaButton = button
        activeFlickDirection = .center
        showFlickGuide(for: key, from: button, selectedDirection: .center, mode: .longPress)
    }

    @objc private func handleKeyRelease(_ sender: KeyboardButton, event: UIEvent) {
        let releasedButton = currentSumireKeyboard.kind == .qwerty
            ? (activeQWERTYButton ?? sender)
            : sender

        if shouldSuppressRelease(for: sender, event: event) {
            sender.isHighlighted = false
            return
        }

        if suppressNextButtonRelease {
            suppressNextButtonRelease = false
            clearActiveKanaButton()
            clearActiveQWERTYButton()
            activeFlickDirection = .center
            hideFlickGuide()
            return
        }

        if currentSumireKeyboard.kind != .qwerty,
           keyRequiringFlickTracking(from: releasedButton.action) != nil,
           activeFlickDirection == .center {
            releasedButton.flashTapHighlight()
        }

        performKeyAction(releasedButton.action)

        clearActiveKanaButton()
        clearActiveQWERTYButton()
        activeFlickDirection = .center
        hideFlickGuide()
    }

    private func performKeyAction(_ action: KeyAction) {
        switch action {
        case .kana(let key):
            insertCandidate(for: key, direction: activeFlickDirection)
        case .flickOnly(let key):
            insertFlickOnlyCandidate(for: key, direction: activeFlickDirection)
        case .transform:
            transformPreviousCharacter()
        case .reverseCycle:
            handleReverseCycleKey()
        case .switchMode:
            resetMultiTapState()
            handleSwitchModeKey()
        case .switchToJapanese:
            resetMultiTapState()
            switchFlickLanguage(to: .japanese)
        case .switchToEnglish:
            resetMultiTapState()
            switchFlickLanguage(to: .english)
        case .switchToNumber:
            resetMultiTapState()
            switchFlickLanguage(to: .number)
        case .emojiKeyboard:
            resetMultiTapState()
            handleEmojiKeyboardKey()
        case .togglePreviousAlphabetCase:
            resetMultiTapState()
            handleTogglePreviousAlphabetCaseKey()
        case .nextKeyboard:
            resetMultiTapState()
            handleNextKeyboardKey()
        case .qwertyText(let text):
            resetMultiTapState()
            handleQWERTYTextKey(text)
        case .qwertyShift:
            resetMultiTapState()
            handleQWERTYShiftKey()
        case .qwertySwitchSymbols:
            resetMultiTapState()
            handleQWERTYSymbolsKey()
        case .qwertySwitchSymbolPage:
            resetMultiTapState()
            handleQWERTYSymbolPageKey()
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
    }

    @objc private func handleKeyboardSwitchInputModeList(_ sender: KeyboardButton, event: UIEvent) {
        if event.touches(for: sender)?.contains(where: { $0.phase == .began }) == true {
            resetMultiTapState()
            hideFlickGuide()
            commitRenderedComposingTextAsTyped()
        }

        handleInputModeList(from: sender, with: event)
    }

    @objc private func commitCandidate(_ sender: CandidateButton) {
        guard let candidate = sender.committedCandidate else {
            return
        }

        commitCandidateItem(candidate)
    }

    private func commitCandidateItem(_ candidate: ConversionCandidateItem) {
        resetMultiTapState()
        commitComposingText(candidate.text, consumedReadingLength: candidate.consumedReadingLength)
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
            handleDeleteKey()
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

    private var canBeginSpaceCursorMoveMode: Bool {
        resizeOverlayView == nil && hasActivePreedit == false
    }

    private var hasActivePreedit: Bool {
        if composingText.isEmpty == false || renderedComposingText.isEmpty == false || qwertyRawInput.isEmpty == false {
            return true
        }

        guard case .precomposition(let status) = inputStatus else {
            return false
        }

        return status.phase != .empty
    }

    private func beginSpaceCursorMoveMode() {
        suppressNextButtonRelease = true
        resetMultiTapState()
        stopDeleteRepeat()
        stopCursorRepeat()
        hideFlickGuide()
        clearActiveKanaButton()
        clearActiveQWERTYButton()
        keyboardVisualModeController.setMode(.cursorMove)
    }

    private func endSpaceCursorMoveMode() {
        keyboardVisualModeController.setMode(.normal)
        hideFlickGuide()
        clearActiveKanaButton()
        clearActiveQWERTYButton()
        activeFlickDirection = .center
    }

    private func finishSpaceCursorMoveTracking() {
        DispatchQueue.main.async { [weak self] in
            self?.suppressNextButtonRelease = false
        }
    }

    private func releaseActiveKanaButtonIfNeeded(beforeActivating nextButton: KeyboardButton) {
        guard let button = activeKanaButton,
              button !== nextButton else {
            return
        }

        suppressRelease(for: activeKanaTouch, button: button)
        performKeyAction(button.action)
        clearActiveKanaButton()
        activeFlickDirection = .center
        hideFlickGuide()
    }

    private func releaseActiveQWERTYButtonIfNeeded(beforeActivating nextButton: KeyboardButton) {
        guard let button = activeQWERTYButton,
              button !== nextButton else {
            return
        }

        suppressRelease(for: activeQWERTYTouch, button: button)
        performKeyAction(button.action)
        clearActiveQWERTYButton()
    }

    private func touch(for button: KeyboardButton, event: UIEvent) -> UITouch? {
        event.touches(for: button)?.first
    }

    private func suppressRelease(for touch: UITouch?, button: KeyboardButton) {
        if let touch {
            suppressedReleaseTouchIDs.insert(ObjectIdentifier(touch))
        }
        suppressedReleaseButtonIDs.insert(ObjectIdentifier(button))
    }

    private func shouldSuppressRelease(for button: KeyboardButton, event: UIEvent?) -> Bool {
        let buttonIdentifier = ObjectIdentifier(button)
        if suppressedReleaseButtonIDs.remove(buttonIdentifier) != nil {
            if let touches = event?.touches(for: button) {
                for touch in touches {
                    suppressedReleaseTouchIDs.remove(ObjectIdentifier(touch))
                }
            }
            return true
        }

        guard let touches = event?.touches(for: button) else {
            return false
        }

        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            if suppressedReleaseTouchIDs.remove(identifier) != nil {
                return true
            }
        }

        return false
    }

    private func flickDirection(for button: KeyboardButton, event: UIEvent) -> FlickDirection {
        guard let touch = event.touches(for: button)?.first ?? activeKanaTouch ?? event.allTouches?.first else {
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
        let shouldCycle = canUseToggleInput(for: key)
            && activeKeyLabel == key.label
            && lastInsertedText.isEmpty == false
            && lastInputDate.map { now.timeIntervalSince($0) <= multiTapInterval } == true

        if shouldCycle {
            activeCandidateIndex = (activeCandidateIndex + 1) % key.candidates.count
        } else {
            activeKeyLabel = key.label
            activeCandidateIndex = 0
        }
        let text = key.candidates[activeCandidateIndex]
        activeKeyCandidates = canUseToggleInput(for: key) ? key.candidates : [text]
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
        scheduleReverseCycleStateTimer()
        updateReverseCycleButtonState()
    }

    private func canUseToggleInput(for key: KanaKey) -> Bool {
        guard currentPrecompositionStatus?.language == .japanese else {
            return true
        }

        return KeyboardSettings.japaneseFlickInputMode == .toggle
    }

    private func insertFlickOnlyCandidate(for key: KanaKey, direction: FlickDirection) {
        resetMultiTapState()
        guard let text = flickCandidate(for: key, direction: direction) else {
            return
        }

        insertText(text)
    }

    private func flickCandidate(for key: KanaKey, direction: FlickDirection) -> String? {
        if currentPrecompositionStatus?.language == .english {
            let usableCount = isEnglishAlphabetLabel(key.label) ? key.label.count : key.candidates.count
            return directionalCandidate(from: key.candidates, direction: direction, usableCount: usableCount)
        }

        if currentPrecompositionStatus?.language == .number {
            return directionalCandidate(from: key.candidates, direction: direction)
        }

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

    private func directionalCandidate(
        from candidates: [String],
        direction: FlickDirection,
        usableCount: Int? = nil
    ) -> String? {
        let count = min(candidates.count, usableCount ?? candidates.count)
        let index: Int
        switch direction {
        case .center:
            index = 0
        case .left:
            index = 1
        case .up:
            index = 2
        case .right:
            index = 3
        case .down:
            index = 4
        }

        guard index < count else {
            return nil
        }
        return candidates[index]
    }

    private func isEnglishAlphabetLabel(_ label: String) -> Bool {
        guard label.isEmpty == false else {
            return false
        }

        return label.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(Int(scalar.value))
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
        activeKanaTouch = nil
    }

    private func setActiveQWERTYButton(_ button: KeyboardButton?) {
        guard activeQWERTYButton !== button else {
            button?.isHighlighted = true
            return
        }

        activeQWERTYButton?.isHighlighted = false
        activeQWERTYButton = button
        button?.isHighlighted = true
    }

    private func clearActiveQWERTYButton() {
        activeQWERTYButton?.isHighlighted = false
        activeQWERTYButton = nil
        activeQWERTYTouch = nil
    }

    private func updateActiveQWERTYButton(from event: UIEvent, fallback: KeyboardButton) {
        guard isQWERTYSelectableAction(fallback.action) else {
            return
        }

        let locationInView: CGPoint
        if let touch = activeQWERTYTouch ?? event.allTouches?.first {
            locationInView = touch.location(in: view)
        } else {
            locationInView = fallback.convert(
                CGPoint(x: fallback.bounds.midX, y: fallback.bounds.midY),
                to: view
            )
        }

        let hoveredButton = qwertyButtons.first { button in
            guard button.isHidden == false,
                  button.alpha > 0.01,
                  button.window != nil,
                  isQWERTYSelectableAction(button.action) else {
                return false
            }

            return button.convert(button.bounds, to: view).contains(locationInView)
        }

        if let hoveredButton {
            setActiveQWERTYButton(hoveredButton)
        }
    }

    private func isQWERTYSelectableAction(_ action: KeyAction) -> Bool {
        switch action {
        case .qwertyText,
             .qwertyShift,
             .qwertySwitchSymbols,
             .qwertySwitchSymbolPage,
             .delete,
             .space,
             .enter,
             .emojiKeyboard,
             .nextKeyboard:
            return true
        default:
            return false
        }
    }

    private func keyRequiringFlickTracking(from action: KeyAction) -> KanaKey? {
        switch action {
        case .kana(let key), .flickOnly(let key):
            return key
        default:
            return nil
        }
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
        updatePreeditReadingPreview()

        if mainKeyboardContentMode == .candidateList,
           ((mainKeyboardPanel != .emoji && composingText.isEmpty) || currentSumireKeyboard.kind == .qwerty || isDirectMode) {
            resetMainKeyboardContentModeToKeyboard()
        }

        defer {
            updateCandidateListToggleAppearance()
            if mainKeyboardContentMode == .candidateList {
                rebuildMainKeyboardPanel()
            }
        }

        let candidates = currentCandidateItems()
        let selectedCandidateIndex = currentSelectedCandidateIndex(candidateCount: candidates.count)
        let showsEmptyToolbar = shouldShowEmptyPreeditToolbar

        candidateButtons.removeAll()
        for view in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        updateCandidateBarMode(showsEmptyPreeditToolbar: showsEmptyToolbar)

        if showsEmptyToolbar {
            candidateScrollView.setContentOffset(.zero, animated: false)
            return
        }

        if mainKeyboardPanel == .emoji {
            addCandidateButton(title: "絵文字辞書を準備中", committedCandidate: nil, isEnabled: false)
            return
        }

        guard isDirectMode == false else {
            return
        }

        guard candidates.isEmpty == false else {
            addCandidateButton(title: "候補", committedCandidate: nil, isEnabled: false)
            return
        }

        for (index, candidate) in candidates.enumerated() {
            addCandidateButton(
                title: candidate.text,
                committedCandidate: candidate,
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

    private var shouldShowEmptyPreeditToolbar: Bool {
        mainKeyboardPanel != .emoji && composingText.isEmpty
    }

    private func updateCandidateBarMode(showsEmptyPreeditToolbar: Bool) {
        emptyPreeditToolbar.isHidden = showsEmptyPreeditToolbar == false
        candidateRowContainer.isHidden = showsEmptyPreeditToolbar
        candidateScrollView.isHidden = showsEmptyPreeditToolbar
        if showsEmptyPreeditToolbar {
            preeditReadingView.clear()
        }
    }

    private func updatePreeditReadingPreview() {
        guard preeditReadingPreviewEnabled,
              mainKeyboardPanel != .emoji,
              isDirectMode == false,
              composingText.isEmpty == false else {
            preeditReadingView.clear()
            return
        }

        let activeRange = normalizedConversionRange()
        preeditReadingView.configure(
            text: composingText,
            conversionRange: activeRange,
            nonTargetRanges: nonConversionPreeditRanges(textCount: composingText.count, conversionRange: activeRange)
        )
    }

    private func nonConversionPreeditRanges(
        textCount: Int,
        conversionRange: Range<Int>
    ) -> [Range<Int>] {
        guard textCount > 0 else {
            return []
        }

        let lowerBound = min(max(conversionRange.lowerBound, 0), textCount)
        let upperBound = min(max(conversionRange.upperBound, lowerBound), textCount)
        guard lowerBound < upperBound else {
            return [0..<textCount]
        }

        var ranges: [Range<Int>] = []
        if lowerBound > 0 {
            ranges.append(0..<lowerBound)
        }
        if upperBound < textCount {
            ranges.append(upperBound..<textCount)
        }
        return ranges
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
        committedCandidate: ConversionCandidateItem?,
        isEnabled: Bool,
        isSelected: Bool = false
    ) {
        let button = CandidateButton()
        button.configure(
            title: title,
            committedCandidate: committedCandidate,
            isEnabled: isEnabled,
            isSelected: isSelected
        )
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
        if currentSumireKeyboard.kind == .qwerty,
           currentSumireKeyboard.qwertyLanguage == .japanese,
           qwertyRawInput.isEmpty == false {
            deleteJapaneseQWERTYSegment()
            return
        }

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
            textDocumentProxy.insertText(KeyboardSettings.spaceText)
        case .precomposition(let status):
            guard composingText.isEmpty == false else {
                textDocumentProxy.insertText(KeyboardSettings.spaceText)
                return
            }

            if status.language == .japanese {
                guard canUseSpaceAsConversionKey else {
                    insertText(KeyboardSettings.spaceText)
                    return
                }

                switch status.phase {
                case .converting:
                    moveSelectedConversionCandidate(by: 1)
                case .empty, .composing:
                    enterConversionMode()
                }
            } else {
                insertText(KeyboardSettings.spaceText)
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

    private func handleNextKeyboardKey() {
        commitRenderedComposingTextAsTyped()
        if advanceToNextSumireKeyboardIfAvailable() == false {
            advanceToNextInputMode()
        }
    }

    private func handleQWERTYTextKey(_ text: String) {
        guard text.isEmpty == false else {
            return
        }

        let inputText = qwertyInputText(from: text)
        if currentSumireKeyboard.qwertyLanguage == .english {
            textDocumentProxy.insertText(inputText)
        } else {
            ensureJapanesePrecompositionStatus()
            qwertyRawInput.append(contentsOf: normalizedQWERTYRawInput(from: inputText))
            setComposingText(romajiKanaText(from: qwertyRawInput))
            composingCursorPosition = composingText.count
        }

        if qwertyMode == .normal, qwertyShiftEnabled {
            if qwertyCapsLockEnabled == false {
                qwertyShiftEnabled = false
                lastQWERTYShiftTapDate = nil
                rebuildKeyboardLayout()
            }
        }
    }

    private func qwertyInputText(from text: String) -> String {
        guard qwertyMode == .normal,
              text.count == 1,
              let scalar = text.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) else {
            return text
        }

        return qwertyShiftEnabled || qwertyCapsLockEnabled ? text.uppercased() : text.lowercased()
    }

    private func handleQWERTYShiftKey() {
        guard currentSumireKeyboard.kind == .qwerty,
              qwertyMode == .normal else {
            return
        }

        let now = Date()
        if qwertyCapsLockEnabled {
            qwertyCapsLockEnabled = false
            qwertyShiftEnabled = false
            lastQWERTYShiftTapDate = nil
        } else if let lastQWERTYShiftTapDate,
                  now.timeIntervalSince(lastQWERTYShiftTapDate) <= 0.35 {
            qwertyCapsLockEnabled = true
            qwertyShiftEnabled = true
            self.lastQWERTYShiftTapDate = nil
        } else {
            qwertyShiftEnabled.toggle()
            lastQWERTYShiftTapDate = now
        }
        rebuildKeyboardLayout()
    }

    private func handleQWERTYSymbolsKey() {
        guard currentSumireKeyboard.kind == .qwerty else {
            return
        }

        qwertyMode = qwertyMode == .normal ? .symbols : .normal
        qwertyShiftEnabled = false
        qwertyCapsLockEnabled = false
        lastQWERTYShiftTapDate = nil
        mainKeyboardPanel = .text
        rebuildKeyboardLayout()
        updatePreedit()
    }

    private func handleQWERTYSymbolPageKey() {
        guard currentSumireKeyboard.kind == .qwerty else {
            return
        }

        qwertyMode = qwertyMode == .moreSymbols ? .symbols : .moreSymbols
        qwertyShiftEnabled = false
        qwertyCapsLockEnabled = false
        lastQWERTYShiftTapDate = nil
        mainKeyboardPanel = .text
        rebuildKeyboardLayout()
    }

    private func fullWidthText(from text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x20:
                output.append("　")
            case 0x21...0x7E:
                if let fullWidthScalar = UnicodeScalar(scalar.value + 0xFEE0) {
                    output.append(String(fullWidthScalar))
                } else {
                    output.append(String(scalar))
                }
            case 0x00A5:
                output.append("￥")
            default:
                output.append(String(scalar))
            }
        }
        return output
    }

    private func normalizedQWERTYRawInput(from text: String) -> String {
        let halfWidthText = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidthText
    }

    private func romajiKanaText(from rawInput: String) -> String {
        romajiKanaSegments(from: rawInput).map(\.output).joined()
    }

    private func romajiKanaSegments(from rawInput: String) -> [RomajiKanaSegment] {
        let input = normalizedQWERTYRawInput(from: rawInput)
        let originalCharacters = Array(input)
        var segments: [RomajiKanaSegment] = []
        var index = 0

        while index < originalCharacters.count {
            let character = originalCharacters[index]

            if character == "n" {
                let nextIndex = index + 1
                if nextIndex < originalCharacters.count {
                    let nextCharacter = originalCharacters[nextIndex]
                    if nextCharacter == "n" {
                        segments.append(RomajiKanaSegment(rawLength: 2, output: "ん"))
                        index = nextIndex + 1
                        continue
                    }

                    if isRomajiConsonant(nextCharacter), nextCharacter != "y" {
                        segments.append(RomajiKanaSegment(rawLength: 1, output: "ん"))
                        index = nextIndex
                        continue
                    }
                }
            }

            if shouldInsertSmallTsu(at: index, in: originalCharacters) {
                segments.append(RomajiKanaSegment(rawLength: 1, output: "っ"))
                index += 1
                continue
            }

            if let match = longestRomajiKanaMatch(in: originalCharacters, from: index) {
                segments.append(RomajiKanaSegment(rawLength: match.upperBound - index, output: match.kana))
                index = match.upperBound
                continue
            }

            segments.append(RomajiKanaSegment(rawLength: 1, output: fallbackJapaneseQWERTYText(for: originalCharacters[index])))
            index += 1
        }

        return segments
    }

    private func longestRomajiKanaMatch(
        in input: [Character],
        from index: Int
    ) -> (kana: String, upperBound: Int)? {
        let maxLength = min(Self.romajiKanaMaxKeyLength, input.count - index)
        guard maxLength > 0 else {
            return nil
        }

        for length in stride(from: maxLength, through: 1, by: -1) {
            let upperBound = index + length
            let slice = Array(input[index..<upperBound])
            guard slice.allSatisfy(isConvertibleRomajiCharacter) else {
                continue
            }

            let key = String(slice).lowercased()
            if let kana = Self.romajiKanaMap[key] {
                return (kana, upperBound)
            }
        }

        return nil
    }

    private func shouldInsertSmallTsu(at index: Int, in input: [Character]) -> Bool {
        let nextIndex = index + 1
        guard nextIndex < input.count else {
            return false
        }

        let character = input[index]
        let nextCharacter = input[nextIndex]
        return character == nextCharacter
            && character != "n"
            && isRomajiConsonant(character)
    }

    private func isConvertibleRomajiCharacter(_ character: Character) -> Bool {
        if character.isASCII == false {
            return false
        }

        if isASCIIUppercaseLetter(character) {
            return false
        }

        return true
    }

    private func isASCIIUppercaseLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }

        return (65...90).contains(Int(scalar.value))
    }

    private func deleteJapaneseQWERTYSegment() {
        let segments = romajiKanaSegments(from: qwertyRawInput)
        guard segments.isEmpty == false else {
            qwertyRawInput = ""
            composingCursorPosition = 0
            setComposingText("")
            return
        }

        var nextRawInput = qwertyRawInput
        nextRawInput.removeLast(segments.last?.rawLength ?? 0)
        qwertyRawInput = nextRawInput

        let nextText = segments.dropLast().map(\.output).joined()
        composingCursorPosition = nextText.count
        setComposingText(nextText)
    }

    private func isRomajiConsonant(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }

        return (97...122).contains(Int(scalar.value)) && "aiueo".contains(character) == false
    }

    private func fallbackJapaneseQWERTYText(for character: Character) -> String {
        switch character {
        case "-":
            return "ー"
        case "~":
            return "〜"
        case ".":
            return "。"
        case ",":
            return "、"
        case "[":
            return "「"
        case "]":
            return "」"
        default:
            return fullWidthText(from: String(character))
        }
    }

    private func handleReverseCycleKey() {
        guard canReverseCycle,
              activeKeyCandidates.isEmpty == false else {
            updateReverseCycleButtonState()
            return
        }

        let nextIndex = (activeCandidateIndex - 1 + activeKeyCandidates.count) % activeKeyCandidates.count
        activeCandidateIndex = nextIndex
        let text = activeKeyCandidates[nextIndex]

        if isDirectMode {
            for _ in lastInsertedText {
                textDocumentProxy.deleteBackward()
            }
            textDocumentProxy.insertText(text)
        } else {
            replacePreviousComposingCharacter(with: text)
        }

        lastInsertedText = text
        lastInputDate = Date()
        scheduleReverseCycleStateTimer()
        updateReverseCycleButtonState()
    }

    private func handleSwitchModeKey() {
        commitRenderedComposingTextAsTyped()
        mainKeyboardPanel = .text

        guard case .precomposition(var status) = inputStatus else {
            inputStatus = .precomposition(PrecompositionStatus(
                language: .japanese,
                phase: .empty,
                liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
                displayMode: .liveCandidate
            ))
            rebuildKeyboardLayout()
            updateModeSwitchButtonTitle()
            updatePreedit()
            return
        }

        switch status.language {
        case .japanese:
            status.language = .english
            primaryLanguage = "en-US"
        case .english:
            status.language = .number
            primaryLanguage = "en-US"
        case .number:
            status.language = .japanese
            primaryLanguage = "ja-JP"
        }

        status.phase = .empty
        status.displayMode = .liveCandidate
        inputStatus = .precomposition(status)
        rebuildKeyboardLayout()
        updateModeSwitchButtonTitle()
        updatePreedit()
    }

    private func switchFlickLanguage(to language: PrecompositionLanguage) {
        commitRenderedComposingTextAsTyped()
        mainKeyboardPanel = .text
        inputStatus = .precomposition(PrecompositionStatus(
            language: language,
            phase: .empty,
            liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
            displayMode: .liveCandidate
        ))
        primaryLanguage = language == .japanese ? "ja-JP" : "en-US"
        rebuildKeyboardLayout()
        updatePreedit()
    }

    private func handleEmojiKeyboardKey() {
        commitRenderedComposingTextAsTyped()
        // 絵文字パネルでは候補一覧を優先表示しないため、切替前に表示モードを戻す。
        resetMainKeyboardContentModeToKeyboard(rebuildsPanel: false)
        mainKeyboardPanel = mainKeyboardPanel == .emoji ? .text : .emoji
        if currentSumireKeyboard.kind == .qwerty {
            rebuildKeyboardLayout()
        } else {
            rebuildMainKeyboardPanel()
        }
        updatePreedit()
    }

    private func handleTogglePreviousAlphabetCaseKey() {
        if let previousCharacter = previousComposingCharacterBeforeCursor(),
           let toggledCharacter = toggledAlphabetCase(for: previousCharacter) {
            replacePreviousComposingCharacter(with: String(toggledCharacter))
            return
        }

        if let previousCharacter = textDocumentProxy.documentContextBeforeInput?.last,
           let toggledCharacter = toggledAlphabetCase(for: previousCharacter) {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(String(toggledCharacter))
        }
    }

    private func previousComposingCharacterBeforeCursor() -> Character? {
        guard composingText.isEmpty == false, composingCursorPosition > 0 else {
            return nil
        }

        let index = stringIndex(in: composingText, offset: composingCursorPosition - 1)
        return composingText[index]
    }

    private func toggledAlphabetCase(for character: Character) -> Character? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return nil
        }

        let value = scalar.value
        if (65...90).contains(Int(value)),
           let toggledScalar = UnicodeScalar(value + 32) {
            return Character(toggledScalar)
        }

        if (97...122).contains(Int(value)),
           let toggledScalar = UnicodeScalar(value - 32) {
            return Character(toggledScalar)
        }

        return nil
    }

    private func updateModeSwitchButtonTitle() {
        let title: String
        switch currentPrecompositionStatus?.language {
        case .japanese, .none:
            title = "ABC"
        case .english:
            title = "★123"
        case .number:
            title = "あいう"
        }
        modeSwitchButton?.updateTitle(title)
    }

    private var canReverseCycle: Bool {
        guard activeKeyLabel != nil,
              activeKeyCandidates.count > 1,
              lastInsertedText.isEmpty == false,
              let lastInputDate else {
            return false
        }

        return Date().timeIntervalSince(lastInputDate) <= multiTapInterval
    }

    private func updateReverseCycleButtonState() {
        reverseCycleButton?.setFunctionEnabled(canReverseCycle)
    }

    private func scheduleReverseCycleStateTimer() {
        stopReverseCycleStateTimer()
        guard canReverseCycle, let lastInputDate else {
            updateReverseCycleButtonState()
            return
        }

        let remainingInterval = max(0.01, multiTapInterval - Date().timeIntervalSince(lastInputDate))
        let timer = Timer(timeInterval: remainingInterval, repeats: false) { [weak self] _ in
            self?.updateReverseCycleButtonState()
        }
        reverseCycleStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func commitDefaultCandidate() {
        guard composingText.isEmpty == false else {
            return
        }

        if let candidate = currentCandidateItems().first {
            commitCandidateItem(candidate)
        } else {
            commitComposingText(conversionTargetText())
        }
    }

    private func commitSelectedOrDefaultCandidate() {
        let candidates = currentCandidateItems()
        if let selectedIndex = currentSelectedCandidateIndex(candidateCount: candidates.count),
           candidates.indices.contains(selectedIndex) {
            commitCandidateItem(candidates[selectedIndex])
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

    private func ensureJapanesePrecompositionStatus() {
        guard case .precomposition(let status) = inputStatus,
              status.language == .japanese else {
            inputStatus = .precomposition(PrecompositionStatus(
                language: .japanese,
                phase: composingText.isEmpty ? .empty : .composing,
                liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
                displayMode: .liveCandidate
            ))
            primaryLanguage = "ja-JP"
            return
        }
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
        KeyboardSettings.liveConversionEnabled = isEnabled
        renderCurrentComposingText()
        updatePreedit()
    }

    private func syncSharedSettings() {
        let shouldApplyKeyboard = syncSumireKeyboardSettings()
        applyStoredKeyboardLayoutMetricsIfNeeded(force: true)

        let nextLiveConversionEnabled = KeyboardSettings.liveConversionEnabled
        var shouldRenderComposition = false
        var shouldUpdatePreedit = false
        if case .precomposition(var status) = inputStatus,
           status.liveConversionEnabled != nextLiveConversionEnabled {
            status.liveConversionEnabled = nextLiveConversionEnabled
            status.displayMode = nextLiveConversionEnabled ? .liveCandidate : .reading
            inputStatus = .precomposition(status)
            shouldRenderComposition = true
        }

        let nextPreeditReadingPreviewEnabled = KeyboardSettings.preeditReadingPreviewEnabled
        if preeditReadingPreviewEnabled != nextPreeditReadingPreviewEnabled {
            preeditReadingPreviewEnabled = nextPreeditReadingPreviewEnabled
            shouldUpdatePreedit = true
        }

        let nextOmissionSearchEnabled = KeyboardSettings.omissionSearchEnabled
        if omissionSearchEnabled != nextOmissionSearchEnabled {
            omissionSearchEnabled = nextOmissionSearchEnabled
            shouldRenderComposition = true
            shouldUpdatePreedit = true
        }

        if shouldApplyKeyboard {
            applyCurrentSumireKeyboard()
            return
        }

        if shouldRenderComposition {
            renderCurrentComposingText()
        }
        if shouldRenderComposition || shouldUpdatePreedit {
            updatePreedit()
        }
    }

    private func syncSumireKeyboardSettings() -> Bool {
        let nextKeyboards = KeyboardSettings.keyboards
        let nextKeyboardID = KeyboardSettings.currentKeyboardID
        let nextKeyboard = nextKeyboards.first(where: { $0.id == nextKeyboardID }) ?? nextKeyboards[0]
        let shouldApplyKeyboard = currentSumireKeyboard.id != nextKeyboard.id
            || currentSumireKeyboard.kind != nextKeyboard.kind
            || currentSumireKeyboard.qwertyLanguage != nextKeyboard.qwertyLanguage

        sumireKeyboards = nextKeyboards
        currentSumireKeyboard = nextKeyboard
        return shouldApplyKeyboard
    }

    private func advanceToNextSumireKeyboardIfAvailable() -> Bool {
        sumireKeyboards = KeyboardSettings.keyboards
        guard sumireKeyboards.count > 1 else {
            return false
        }

        let currentID = KeyboardSettings.currentKeyboardID
        let currentIndex = sumireKeyboards.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIndex = (currentIndex + 1) % sumireKeyboards.count
        currentSumireKeyboard = sumireKeyboards[nextIndex]
        KeyboardSettings.currentKeyboardID = currentSumireKeyboard.id
        applyCurrentSumireKeyboard()
        return true
    }

    private func applyCurrentSumireKeyboard() {
        commitRenderedComposingTextAsTyped()
        resetMultiTapState()
        exitKeyboardResizeMode()
        mainKeyboardPanel = .text
        qwertyMode = .normal
        qwertyShiftEnabled = false
        qwertyCapsLockEnabled = false
        lastQWERTYShiftTapDate = nil
        qwertyRawInput = ""

        configureInputStatusForCurrentSumireKeyboard()
        rebuildKeyboardLayout()
        updatePreedit()
    }

    private func configureInputStatusForCurrentSumireKeyboard() {
        switch currentSumireKeyboard.kind {
        case .japaneseFlick:
            inputStatus = .precomposition(PrecompositionStatus(
                language: .japanese,
                phase: .empty,
                liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
                displayMode: .liveCandidate
            ))
            primaryLanguage = "ja-JP"
        case .qwerty:
            if currentSumireKeyboard.qwertyLanguage == .english {
                inputStatus = .direct
                primaryLanguage = "en-US"
            } else {
                inputStatus = .precomposition(PrecompositionStatus(
                    language: .japanese,
                    phase: .empty,
                    liveConversionEnabled: KeyboardSettings.liveConversionEnabled,
                    displayMode: .liveCandidate
                ))
                primaryLanguage = "ja-JP"
            }
        }
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
        let candidates = currentCandidateItems()
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

    private func commitComposingText(_ text: String, consumedReadingLength: Int? = nil) {
        guard composingText.isEmpty == false else {
            return
        }

        qwertyRawInput = ""
        // 候補確定後は通常キーボードへ戻し、一覧モードの状態を残さない。
        resetMainKeyboardContentModeToKeyboard()

        let activeRange = normalizedConversionRange()
        guard activeRange.isEmpty == false else {
            return
        }

        let activeLength = activeRange.upperBound - activeRange.lowerBound
        let consumedLength = min(max(consumedReadingLength ?? activeLength, 0), activeLength)
        guard consumedLength > 0 else {
            return
        }

        let consumedRange = activeRange.lowerBound..<(activeRange.lowerBound + consumedLength)
        let remainingText = self.text(in: consumedRange.upperBound..<composingText.count, from: composingText)
        let updatedText = replacingText(in: consumedRange, with: text)

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
            qwertyRawInput = ""
            resetMainKeyboardContentModeToKeyboard()
            return
        }

        qwertyRawInput = ""
        resetMainKeyboardContentModeToKeyboard()
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

        let candidates = currentCandidateItems()
        let candidate: ConversionCandidateItem?
        if let selectedIndex = currentSelectedCandidateIndex(candidateCount: candidates.count),
           candidates.indices.contains(selectedIndex) {
            candidate = candidates[selectedIndex]
        } else {
            candidate = candidates.first
        }

        let activeRange = normalizedConversionRange()
        guard let candidate else {
            return replacingText(in: activeRange, with: conversionTargetText())
        }

        let activeLength = activeRange.upperBound - activeRange.lowerBound
        let consumedLength = min(max(candidate.consumedReadingLength, 0), activeLength)
        guard consumedLength > 0 else {
            return composingText
        }

        let consumedRange = activeRange.lowerBound..<(activeRange.lowerBound + consumedLength)
        return replacingText(in: consumedRange, with: candidate.text)
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
            self?.handleDeleteKey()
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

    private func stopReverseCycleStateTimer() {
        reverseCycleStateTimer?.invalidate()
        reverseCycleStateTimer = nil
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

    private func currentCandidateItems() -> [ConversionCandidateItem] {
        guard isDirectMode == false, composingText.isEmpty == false else {
            return []
        }

        let targetText = conversionTargetText()
        guard targetText.isEmpty == false else {
            return []
        }

        var seen = Set<String>()
        var candidates: [ConversionCandidateItem] = []

        func appendUnique(_ text: String, consumedReadingLength: Int = targetText.count) {
            guard text.isEmpty == false, seen.insert(text).inserted else {
                return
            }
            let consumedLength = min(max(consumedReadingLength, 0), targetText.count)
            candidates.append(ConversionCandidateItem(text: text, consumedReadingLength: consumedLength))
        }

        guard currentPrecompositionStatus?.language == .japanese else {
            appendUnique(targetText)
            return candidates
        }

        if let kanaKanjiConverter {
            let options = ConversionOptions(
                limit: conversionCandidateLimit,
                beamWidth: conversionBeamWidth,
                yomiSearchMode: omissionSearchEnabled ? .all : .commonPrefixPlusPredictive,
                predictivePrefixLength: 1,
                omissionPenaltyWeight: 1500
            )
            for candidate in kanaKanjiConverter.convert(targetText, options: options) {
                appendUnique(candidate.text)
            }
            for candidate in kanaKanjiConverter.commonPrefixCandidates(
                targetText,
                options: options,
                limit: conversionCandidateLimit
            ) {
                appendUnique(
                    candidate.text,
                    consumedReadingLength: candidate.consumedLength ?? candidate.reading.count
                )
            }
            for candidate in kanaKanjiConverter.predict(
                targetText,
                options: options,
                limit: conversionCandidateLimit
            ) {
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
        activeKeyCandidates = []
        lastInsertedText = ""
        lastInputDate = nil
        stopReverseCycleStateTimer()
        updateReverseCycleButtonState()
    }
}
