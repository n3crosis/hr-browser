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
        
        // Swizzle UIViewController to detect SettingsViewController
        UIViewController.fw_swizzleLifecycle()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsAppeared),
            name: NSNotification.Name("FWSettingsAppeared"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDisappeared),
            name: NSNotification.Name("FWSettingsDisappeared"),
            object: nil
        )
    }

    /// Called from FloatingWidgetBootstrap.m via ObjC runtime.
    /// @objc(bootWithScene:) pins the selector so NSSelectorFromString is reliable.
    @objc(bootWithScene:) func boot(scene: UIWindowScene) {
        guard overlayWindow == nil else { return }

        let window = PassthroughWindow(windowScene: scene)
        // High enough to be over AVPlayerViewController (full screen video usually uses normal or alert)
        window.windowLevel = UIWindow.Level(rawValue: 10000)
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

    private var isSettingsVisible = false

    @objc func updateVisibility() {
        let enabled = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
        widgetView?.isHidden = !enabled || isSettingsVisible
        overlayWindow?.isHidden = !enabled && !isSettingsVisible
    }

    @objc private func settingsAppeared() {
        isSettingsVisible = true
        updateVisibility()
    }

    @objc private func settingsDisappeared() {
        isSettingsVisible = false
        updateVisibility()
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

    override func layoutSubviews() {
        super.layoutSubviews()
        // Auto re-calculate position when bounds change (e.g. horizontal rotation)
        for view in subviews {
            if let widget = view as? FloatingWidgetView {
                widget.setNeedsLayout()
            }
        }
    }
}

extension UIViewController {
    static func fw_swizzleLifecycle() {
        let originalAppear = class_getInstanceMethod(UIViewController.self, #selector(viewDidAppear(_:)))
        let swizzledAppear = class_getInstanceMethod(UIViewController.self, #selector(fw_viewDidAppear(_:)))
        method_exchangeImplementations(originalAppear!, swizzledAppear!)
        
        let originalDisappear = class_getInstanceMethod(UIViewController.self, #selector(viewDidDisappear(_:)))
        let swizzledDisappear = class_getInstanceMethod(UIViewController.self, #selector(fw_viewDidDisappear(_:)))
        method_exchangeImplementations(originalDisappear!, swizzledDisappear!)
    }

    @objc func fw_viewDidAppear(_ animated: Bool) {
        self.fw_viewDidAppear(animated) // calls original
        let name = String(describing: type(of: self))
        if name.contains("SettingsViewController") {
            NotificationCenter.default.post(name: NSNotification.Name("FWSettingsAppeared"), object: nil)
        }
    }

    @objc func fw_viewDidDisappear(_ animated: Bool) {
        self.fw_viewDidDisappear(animated) // calls original
        let name = String(describing: type(of: self))
        if name.contains("SettingsViewController") {
            NotificationCenter.default.post(name: NSNotification.Name("FWSettingsDisappeared"), object: nil)
        }
    }
}
