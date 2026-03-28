import UIKit
import HealthKit

final class FloatingWidgetView: UIView {

    private let diameter: CGFloat = 56
    private let hrLabel = UILabel()
    private var anchoredQuery: HKQuery?
    private let healthStore = HKHealthStore()
    private var isDragging = false

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    deinit {
        if let query = anchoredQuery {
            healthStore.stop(query)
        }
    }

    private func setup() {
        backgroundColor = .accent
        layer.cornerRadius = diameter / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        hrLabel.text = "--"
        hrLabel.textColor = .white
        hrLabel.font = .systemFont(ofSize: 18, weight: .bold)
        hrLabel.textAlignment = .center
        hrLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hrLabel)
        NSLayoutConstraint.activate([
            hrLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hrLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        startLiveHeartRate()
    }

    private func startLiveHeartRate() {
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        // We want all heart rate samples, including those generated during workouts.
        // By passing nil for predicate, we get all samples.
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        healthStore.execute(query)
        anchoredQuery = query
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample],
              let lastSample = samples.max(by: { $0.endDate < $1.endDate }) else { return }
        
        let hr = lastSample.quantity.doubleValue(for: HKUnit(from: "count/min"))
        DispatchQueue.main.async {
            self.hrLabel.text = String(format: "%.0f", hr)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        
        if gesture.state == .began {
            isDragging = true
        }

        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            isDragging = false
            snapToNearestEdge(in: superview)
        }
    }

    private func snapToNearestEdge(in container: UIView) {
        let safeArea = container.safeAreaInsets
        let margin: CGFloat = 8
        let minY = safeArea.top + margin + diameter / 2
        let maxY = container.bounds.height - safeArea.bottom - margin - diameter / 2
        let minX = safeArea.left + margin + diameter / 2
        let maxX = container.bounds.width - safeArea.right - margin - diameter / 2

        var target = center
        target.y = min(max(target.y, minY), maxY)
        
        // Snap to the nearest horizontal edge
        if center.x < container.bounds.midX {
            target.x = minX
        } else {
            target.x = maxX
        }

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

    override func layoutSubviews() {
        super.layoutSubviews()
        if let superview = superview, !isDragging {
            snapToNearestEdge(in: superview)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: diameter, height: diameter)
    }
}
