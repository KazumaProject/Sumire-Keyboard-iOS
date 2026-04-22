import UIKit

protocol KeyboardContentHidable: AnyObject {
    func setKeyboardContentHidden(_ isHidden: Bool)
}

final class KeyboardVisualModeController {
    enum Mode: Equatable {
        case normal
        case cursorMove
    }

    private weak var contentRootView: UIView?
    private(set) var mode: Mode = .normal

    init(contentRootView: UIView) {
        self.contentRootView = contentRootView
    }

    func setMode(_ nextMode: Mode) {
        guard mode != nextMode else {
            return
        }

        mode = nextMode
        applyMode()
    }

    func reapplyMode() {
        applyMode()
    }

    private func applyMode() {
        guard let contentRootView else {
            return
        }

        setContentHidden(mode == .cursorMove, in: contentRootView)
    }

    private func setContentHidden(_ isHidden: Bool, in view: UIView) {
        if let contentHidable = view as? KeyboardContentHidable {
            contentHidable.setKeyboardContentHidden(isHidden)
            return
        }

        for subview in view.subviews {
            setContentHidden(isHidden, in: subview)
        }
    }
}
