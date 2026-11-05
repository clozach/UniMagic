import SwiftUI
import UIKit

/// A two-finger shortcut on the picker; the category menu exposes the same actions.
struct CategorySwipe: UIViewRepresentable {
    let cycle: (Bool) -> Void
    func makeUIView(context: Context) -> SwipeAnchor { SwipeAnchor(cycle: cycle) }
    func updateUIView(_ uiView: SwipeAnchor, context: Context) { uiView.cycle = cycle }
    static func dismantleUIView(_ uiView: SwipeAnchor, coordinator: ()) { uiView.detach() }

    final class SwipeAnchor: UIView, UIGestureRecognizerDelegate {
        var cycle: (Bool) -> Void
        private var recognizers: [UISwipeGestureRecognizer] = []
        init(cycle: @escaping (Bool) -> Void) {
            self.cycle = cycle
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            detach()
            guard let parent = superview else { return }
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                recognizer.direction = direction
                recognizer.numberOfTouchesRequired = 2
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                parent.addGestureRecognizer(recognizer)
                recognizers.append(recognizer)
            }
        }
        func detach() {
            for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizers.removeAll()
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !UIAccessibility.isVoiceOverRunning
        }
        @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
            guard !UIAccessibility.isVoiceOverRunning else { return }
            cycle(recognizer.direction == .left)
        }
    }
}
