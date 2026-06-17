//
//  QueuePopupBar.swift
//  Cyanide
//
//  Sileo-style persistent popup bar sitting above the tab bar. Visible when
//  the package queue is non-empty.
//

import UIKit

@objc class QueuePopupBar: UIView {

    @objc var onTap: (() -> Void)?

    private var blurView: UIVisualEffectView!
    private var iconView: UIImageView!
    private var titleLabel: UILabel!
    private var subtitleLabel: UILabel!
    private var chevronView: UIImageView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildSubviews()
        alpha = 0.0
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func buildSubviews() {
        backgroundColor = .clear
        layer.cornerRadius = 16.0
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.5).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12.0
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let blur = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = 16.0
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        addSubview(blurView)
        self.blurView = blurView

        let iconCfg = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "shippingbox.fill", withConfiguration: iconCfg)
        iconView.tintColor = tintColor
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        self.iconView = iconView

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 15.0, weight: .semibold)
        title.textColor = .label
        addSubview(title)
        self.titleLabel = title

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 12.0, weight: .regular)
        subtitle.textColor = .secondaryLabel
        addSubview(subtitle)
        self.subtitleLabel = subtitle

        let chevCfg = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        let chev = UIImageView()
        chev.translatesAutoresizingMaskIntoConstraints = false
        chev.image = UIImage(systemName: "chevron.right", withConfiguration: chevCfg)
        chev.tintColor = .tertiaryLabel
        chev.contentMode = .scaleAspectFit
        addSubview(chev)
        self.chevronView = chev

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16.0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.0),
            iconView.heightAnchor.constraint(equalToConstant: 24.0),

            title.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.0),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9.0),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1.0),

            chev.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.0),
            chev.centerYAnchor.constraint(equalTo: centerYAnchor),
            chev.widthAnchor.constraint(equalToConstant: 14.0),
            chev.heightAnchor.constraint(equalToConstant: 18.0),

            title.trailingAnchor.constraint(lessThanOrEqualTo: chev.leadingAnchor, constant: -12.0),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: chev.leadingAnchor, constant: -12.0),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queueChanged(_:)),
                                               name: .PackageQueueDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        iconView.tintColor = tintColor
    }

    @objc private func didTap() {
        onTap?()
    }

    @objc private func queueChanged(_ note: Notification) {
        refreshFromQueue(animated: true)
    }

    @objc(refreshFromQueueAnimated:)
    func refreshFromQueue(animated: Bool) {
        let q = PackageQueue.shared()
        let count = q.pendingCount

        if count == 0 {
            setVisible(false, animated: animated)
            return
        }

        let installs   = Int(q.queuedInstalls.count)
        let uninstalls = Int(q.queuedUninstalls.count)

        titleLabel.text = count == 1 ? "1 pending change" : "\(count) pending changes"

        var parts: [String] = []
        if installs > 0   { parts.append("\(installs) activate") }
        if uninstalls > 0 { parts.append("\(uninstalls) deactivate") }
        subtitleLabel.text = parts.joined(separator: " · ")

        setVisible(true, animated: animated)
    }

    private func setVisible(_ visible: Bool, animated: Bool) {
        if !visible && isHidden { return }
        if visible && !isHidden && alpha == 1.0 { return }

        let update = {
            self.alpha = visible ? 1.0 : 0.0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 16.0)
        }
        let done = { (_: Bool) in
            self.isHidden = !visible
        }

        isHidden = false
        if !visible {
            transform = .identity
        } else if alpha < 0.01 {
            transform = CGAffineTransform(translationX: 0, y: 16.0)
        }

        if animated {
            UIView.animate(withDuration: 0.28,
                           delay: 0,
                           usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0.3,
                           options: .beginFromCurrentState,
                           animations: update,
                           completion: done)
        } else {
            update()
            done(true)
        }
    }
}
