import UIKit

final class FloatingWidgetView: UIView {

    private let diameter: CGFloat = 56

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .accent
        layer.cornerRadius = diameter / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        let icon = UIImageView(image: UIImage(systemName: "circle.fill"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended || gesture.state == .cancelled {
            snapToEdge(in: superview)
        }
    }

    private func snapToEdge(in container: UIView) {
        let safeArea = container.safeAreaInsets
        let margin: CGFloat = 8
        let minY = safeArea.top + margin + diameter / 2
        let maxY = container.bounds.height - safeArea.bottom - margin - diameter / 2
        let leftX = safeArea.left + margin + diameter / 2
        let rightX = container.bounds.width - safeArea.right - margin - diameter / 2

        var target = center
        target.x = center.x < container.bounds.midX ? leftX : rightX
        target.y = min(max(target.y, minY), maxY)

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut],
            animations: { self.center = target }
        )
    }

    @objc private func handleTap() {
        FloatingWidgetManager.shared.presentSettings()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: diameter, height: diameter)
    }
}
