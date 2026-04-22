import UIKit

final class CursorMoveController: NSObject {
    enum Constants {
        static let longPressDuration: TimeInterval = 0.35
        static let characterStepDistance: CGFloat = 18
        static let maxCharacterStepsPerUpdate = 4
    }

    private weak var trackingView: UIView?
    private let canBegin: () -> Bool
    private let adjustTextPosition: (Int) -> Void
    private let onModeBegan: () -> Void
    private let onModeEnded: () -> Void
    private let onTrackingFinished: () -> Void

    private var previousTrackingLocation: CGPoint?
    private var accumulatedHorizontalMovement: CGFloat = 0
    private var didBeginTrackingCurrentGesture = false
    private(set) var isCursorMoveMode = false

    init(
        trackingView: UIView,
        canBegin: @escaping () -> Bool,
        adjustTextPosition: @escaping (Int) -> Void,
        onModeBegan: @escaping () -> Void,
        onModeEnded: @escaping () -> Void,
        onTrackingFinished: @escaping () -> Void
    ) {
        self.trackingView = trackingView
        self.canBegin = canBegin
        self.adjustTextPosition = adjustTextPosition
        self.onModeBegan = onModeBegan
        self.onModeEnded = onModeEnded
        self.onTrackingFinished = onTrackingFinished
        super.init()
    }

    func makeSpaceLongPressGestureRecognizer() -> UILongPressGestureRecognizer {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
        gesture.minimumPressDuration = Constants.longPressDuration
        gesture.cancelsTouchesInView = false
        return gesture
    }

    func cancelTracking() {
        guard didBeginTrackingCurrentGesture else {
            return
        }

        exitCursorMoveModeIfNeeded()
        didBeginTrackingCurrentGesture = false
        onTrackingFinished()
    }

    @objc private func handleSpaceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginTracking(with: gesture)
        case .changed:
            updateTracking(with: gesture)
        case .ended, .cancelled, .failed:
            finishTracking()
        default:
            break
        }
    }

    private func beginTracking(with gesture: UILongPressGestureRecognizer) {
        guard canBegin(), let trackingView else {
            return
        }

        didBeginTrackingCurrentGesture = true
        isCursorMoveMode = true
        previousTrackingLocation = gesture.location(in: trackingView)
        accumulatedHorizontalMovement = 0
        onModeBegan()
    }

    private func updateTracking(with gesture: UILongPressGestureRecognizer) {
        guard didBeginTrackingCurrentGesture, isCursorMoveMode, let trackingView else {
            return
        }

        guard canBegin() else {
            exitCursorMoveModeIfNeeded()
            return
        }

        let location = gesture.location(in: trackingView)
        let previousLocation = previousTrackingLocation ?? location
        previousTrackingLocation = location
        accumulatedHorizontalMovement += location.x - previousLocation.x
        moveCursorIfNeeded()
    }

    private func finishTracking() {
        guard didBeginTrackingCurrentGesture else {
            return
        }

        exitCursorMoveModeIfNeeded()
        didBeginTrackingCurrentGesture = false
        onTrackingFinished()
    }

    private func exitCursorMoveModeIfNeeded() {
        guard isCursorMoveMode else {
            previousTrackingLocation = nil
            accumulatedHorizontalMovement = 0
            return
        }

        isCursorMoveMode = false
        previousTrackingLocation = nil
        accumulatedHorizontalMovement = 0
        onModeEnded()
    }

    private func moveCursorIfNeeded() {
        let threshold = Constants.characterStepDistance
        guard abs(accumulatedHorizontalMovement) >= threshold else {
            return
        }

        let direction = accumulatedHorizontalMovement > 0 ? 1 : -1
        let availableSteps = Int(abs(accumulatedHorizontalMovement) / threshold)
        let steps = min(availableSteps, Constants.maxCharacterStepsPerUpdate)
        guard steps > 0 else {
            return
        }

        adjustTextPosition(direction * steps)
        accumulatedHorizontalMovement -= CGFloat(direction * steps) * threshold

        let maximumRemainder = threshold * CGFloat(Constants.maxCharacterStepsPerUpdate)
        accumulatedHorizontalMovement = min(
            max(accumulatedHorizontalMovement, -maximumRemainder),
            maximumRemainder
        )
    }
}
