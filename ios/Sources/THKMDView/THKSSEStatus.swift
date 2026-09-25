import UIKit

public enum THKSSEState { case idle, waiting, streaming, completed, stopped, failed }
public struct THKSSEIndicatorStyle {
    public var color: UIColor?
    public var diameter: CGFloat
    public var gap: CGFloat
    public var cycleDuration: TimeInterval
    public init(color: UIColor? = nil, diameter: CGFloat = 6, gap: CGFloat = 5, cycleDuration: TimeInterval = 0.9) {
        self.color = color; self.diameter = diameter; self.gap = gap; self.cycleDuration = cycleDuration
    }
}
public enum THKRenderFailureStage { case incremental, full }
public struct THKRenderFailure {
    public let stage: THKRenderFailureStage
    public let error: Error
}

private final class SSEDots: UIView {
    let dots = (0..<3).map { _ in CALayer() }
    var style = THKSSEIndicatorStyle()
    override init(frame: CGRect) {
        super.init(frame: frame)
        dots.forEach { layer.addSublayer($0) }
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 24) }
    override func layoutSubviews() {
        super.layoutSubviews()
        let size = max(2, min(20, style.diameter))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: CGFloat(i) * (size + max(0, min(20, style.gap))), y: (bounds.height - size) / 2, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.backgroundColor = (style.color ?? .secondaryLabel).cgColor
        }
        CATransaction.commit()
    }
    func animateDots(_ active: Bool) {
        for (i, dot) in dots.enumerated() {
            if !active { dot.removeAnimation(forKey: "pulse"); continue }
            guard dot.animation(forKey: "pulse") == nil else { continue }
            dot.opacity = 0.25
            guard !UIAccessibility.isReduceMotionEnabled else { dot.opacity = 0.65; continue }
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [1, 0.25, 0.25, 1]
            animation.keyTimes = [0, 0.333, 0.667, 1]
            animation.duration = max(0.3, style.cycleDuration)
            animation.beginTime = CACurrentMediaTime() + Double(i) * animation.duration / 3
            animation.repeatCount = .infinity
            dot.add(animation, forKey: "pulse")
        }
    }
}

internal final class SSEFooter: UIStackView {
    private let dots = SSEDots()
    private var indicator: UIView?
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private var busy = false
    private var running = false
    var onActivity: ((UIView, Bool) -> Void)?
    private var onRetry: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical; alignment = .fill; spacing = 8; isHidden = true
        indicator = dots
        message.numberOfLines = 0
        retry.setTitle("重试", for: .normal)
        retry.contentHorizontalAlignment = .left
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stop), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func retryTapped() { onRetry?() }
    func configure(state: THKSSEState, enabled: Bool, custom: UIView?, style: THKSSEIndicatorStyle,
                   theme: THKMDTheme, error: String?, onRetry: (() -> Void)?) {
        let next = custom ?? dots
        if next !== indicator {
            stop()
            precondition(next.superview == nil || next.superview === self, "SSE indicator already belongs to another parent")
            clear(); indicator = next
        }
        if dots.style.cycleDuration != style.cycleDuration { dots.animateDots(false) }
        dots.style = style; dots.style.color = style.color ?? theme.bodyTextColor; dots.setNeedsLayout()
        if running && indicator === dots { dots.animateDots(true) }
        self.onRetry = onRetry
        busy = enabled && (state == .waiting || state == .streaming)
        let failed = enabled && state == .failed
        if busy {
            if next.superview == nil { clear(); addArrangedSubview(next) }
            next.accessibilityLabel = state == .waiting ? "思考中" : "正在输出"
        } else if failed {
            stop(); clear()
            message.text = error?.isEmpty == false ? error : "回复失败，请重试"
            message.textColor = theme.bodyTextColor; message.font = .systemFont(ofSize: theme.bodyFontSize)
            retry.tintColor = theme.linkColor; retry.titleLabel?.font = .systemFont(ofSize: theme.bodyFontSize)
            addArrangedSubview(message)
            if onRetry != nil { addArrangedSubview(retry) }
        } else {
            // A hidden arranged stack must not keep a child's required height
            // (including a business-supplied indicator) fighting its zero height.
            stop(); clear()
        }
        isHidden = !(busy || failed)
        refresh()
    }
    private func clear() { arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() } }
    @objc private func stop() {
        dots.animateDots(false)
        if running, let indicator { running = false; onActivity?(indicator, false) }
    }
    @objc func refresh() {
        var ancestor: UIView? = self
        var visible = true
        while let view = ancestor { if view.isHidden || view.alpha == 0 { visible = false }; ancestor = view.superview }
        guard busy, window != nil, visible, UIApplication.shared.applicationState == .active else { stop(); return }
        if !running, let indicator {
            running = true
            if indicator === dots { dots.animateDots(true) }
            onActivity?(indicator, true)
        }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    override func layoutSubviews() { super.layoutSubviews(); refresh() }
}
