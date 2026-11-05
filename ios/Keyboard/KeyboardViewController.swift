import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private let model = PickerModel(historyHost: .nativeKeyboard)
    private lazy var keyboardHeight = view.heightAnchor.constraint(equalToConstant: 264)
    override func viewDidLoad() {
        super.viewDidLoad()
        let content = KeyboardRoot(model: model, insert: { [weak self] in self?.textDocumentProxy.insertText($0) }, delete: { [weak self] in self?.textDocumentProxy.deleteBackward() }, globe: { [weak self] button, event in self?.handleInputModeList(from: button, with: event) }, showGlobe: needsInputModeSwitchKey)
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        keyboardHeight.priority = .init(999)
        keyboardHeight.identifier = "Unimagic.keyboardHeight"
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeight
        ])
        host.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshConfiguration()
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Keep the containing app visible; width and size class also cover rotation.
        let height: CGFloat = traitCollection.verticalSizeClass == .compact ? 216 : min(300, max(264, view.bounds.width * 0.68))
        if keyboardHeight.constant != height { keyboardHeight.constant = height }
    }
}
