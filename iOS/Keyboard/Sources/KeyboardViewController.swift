import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    static let padHeight: CGFloat = 268

    private let pad = PadController()

    override func viewDidLoad() {
        super.viewDidLoad()
        pad.onInsert = { [weak self] text in self?.insert(text) }
        pad.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        pad.onOpenApp = { [weak self] url in self?.openContainingApp(url) }

        let host = UIHostingController(rootView: PadView(pad: pad))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let height = view.heightAnchor.constraint(equalToConstant: Self.padHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pad.appear(fullAccess: hasFullAccess)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pad.disappear()
    }

    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !(before.last?.isWhitespace ?? true)
        textDocumentProxy.insertText(needsSpace ? " " + text : text)
    }

    private func openContainingApp(_ url: URL) {
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        pad.couldNotOpenApp()
    }
}
