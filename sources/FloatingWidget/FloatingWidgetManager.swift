import UIKit

// @objc + NSObject so FloatingWidgetBootstrap.m can reach this class at runtime
// via NSClassFromString / objc_msgSend — no generated header needed.
// The explicit @objc(...) names guarantee stable ObjC identifiers regardless
// of the PRODUCT_MODULE_NAME (which changes after app renaming).
@objc(FloatingWidgetManager)
final class FloatingWidgetManager: NSObject {

    private static let defaultsKey = "FloatingWidgetEnabled"

    @objc static let shared = FloatingWidgetManager()

    private var overlayWindow: PassthroughWindow?
    private var widgetView: FloatingWidgetView?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// Called from FloatingWidgetBootstrap.m via ObjC runtime.
    /// @objc(bootWithScene:) pins the selector so NSSelectorFromString is reliable.
    @objc(bootWithScene:) func boot(scene: UIWindowScene) {
        guard overlayWindow == nil else { return }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 0.5
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true

        let rootVC = UIViewController()
        rootVC.view = PassthroughView()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        let widget = FloatingWidgetView()
        widget.translatesAutoresizingMaskIntoConstraints = true
        rootVC.view.addSubview(widget)

        let screenBounds = scene.coordinateSpace.bounds
        widget.center = CGPoint(
            x: screenBounds.width - 46,
            y: screenBounds.height * 0.65
        )

        overlayWindow = window
        widgetView = widget
        updateVisibility()

        // Return focus to the main app window so the browser is key.
        scene.windows.first { $0 !== window }?.makeKeyAndVisible()
    }

    @objc func updateVisibility() {
        let enabled = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
        overlayWindow?.isHidden = !enabled
    }

    func presentSettings() {
        let vc = WidgetSettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        overlayWindow?.rootViewController?.present(nav, animated: true)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibility()
        }
    }
}

// MARK: - Passthrough helpers

/// A UIWindow that only claims touches that land on the FloatingWidgetView.
/// All other touches fall through to the main app window underneath.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// A transparent full-screen container that passes through any touch not
/// claimed by one of its subviews (i.e. touches outside the widget circle).
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // If the only thing hit is this background view, return nil so the
        // touch falls through to the next window.
        return hit === self ? nil : hit
    }
}
