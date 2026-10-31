import UIKit
import SaycribeCore

/// 第九版键盘扩展：备忘录宿主风格 + 全橙 88pt 按钮 + 音量弹簧缩放。
final class KeyboardViewController: UIInputViewController {
    private let mailbox = SharedMailbox()
    private var observer: UUID?
    private var lastRevision = 0
    private var recording = false
    private var sessionId = UUID().uuidString
    private var recordingStartedAt: Date?
    private var levelTimer: Timer?
    private var clockLink: CADisplayLink?

    private let bg = UIColor(red: 0x0C/255, green: 0x0C/255, blue: 0x0B/255, alpha: 1)
    private let card = UIColor(red: 0x1A/255, green: 0x19/255, blue: 0x17/255, alpha: 1)
    private let keyCap = UIColor(red: 0x22/255, green: 0x21/255, blue: 0x1F/255, alpha: 1)
    private let orange = UIColor(red: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1)
    private let tipBg = UIColor(red: 0x2A/255, green: 0x28/255, blue: 0x26/255, alpha: 1)
    private let textPrimary = UIColor(red: 0xF5/255, green: 0xF3/255, blue: 0xEE/255, alpha: 1)
    private let textSecondary = UIColor(red: 0x9A/255, green: 0x96/255, blue: 0x8C/255, alpha: 1)

    private let hostLabel = UILabel()
    private let timerRow = UIStackView()
    private let timerLabel = UILabel()
    private let tipBubble = UILabel()
    private let micButton = UIButton(type: .custom)
    private let micIcon = UIImageView()
    private let statusHint = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        buildUI()
        lastRevision = mailbox.read(AppStatus.self, from: .appStatus)?.revision ?? 0
        observer = DarwinNotifier.shared.observe(.appStatus) { [weak self] in
            DispatchQueue.main.async { self?.statusChanged() }
        }
        if !hasFullAccess {
            statusHint.text = "请在设置中为 Saycribe 打开「允许完全访问」"
            statusHint.isHidden = false
        }
    }

    deinit {
        if let observer { DarwinNotifier.shared.remove(.appStatus, token: observer) }
        levelTimer?.invalidate()
        clockLink?.invalidate()
    }

    private func buildUI() {
        hostLabel.text = "备忘录"
        hostLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hostLabel.textColor = textSecondary
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostLabel)

        let panel = UIView()
        panel.backgroundColor = card
        panel.layer.cornerRadius = 28
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let logo = UIView()
        logo.backgroundColor = orange
        logo.layer.cornerRadius = 6
        logo.translatesAutoresizingMaskIntoConstraints = false
        let logoIcon = UIImageView(image: UIImage(systemName: "waveform"))
        logoIcon.tintColor = bg
        logoIcon.contentMode = .scaleAspectFit
        logoIcon.translatesAutoresizingMaskIntoConstraints = false
        logo.addSubview(logoIcon)

        let brand = UILabel()
        brand.text = "Saycribe"
        brand.font = .systemFont(ofSize: 15, weight: .medium)
        brand.textColor = textPrimary

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        close.tintColor = textSecondary
        close.backgroundColor = keyCap
        close.layer.cornerRadius = 14
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let top = UIStackView(arrangedSubviews: [logo, brand, UIView(), close])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(top)

        let dot = UIView()
        dot.backgroundColor = orange
        dot.layer.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6)
        ])
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timerLabel.textColor = textSecondary
        timerLabel.text = "0:00"
        timerRow.axis = .horizontal
        timerRow.spacing = 6
        timerRow.alignment = .center
        timerRow.addArrangedSubview(dot)
        timerRow.addArrangedSubview(timerLabel)
        timerRow.isHidden = true
        timerRow.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(timerRow)

        tipBubble.text = "再次点击以完成"
        tipBubble.font = .systemFont(ofSize: 13)
        tipBubble.textColor = textPrimary
        tipBubble.textAlignment = .center
        tipBubble.backgroundColor = tipBg
        tipBubble.layer.cornerRadius = 14
        tipBubble.clipsToBounds = true
        tipBubble.layer.borderWidth = 1
        tipBubble.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        tipBubble.isHidden = true
        tipBubble.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(tipBubble)

        statusHint.font = .systemFont(ofSize: 12)
        statusHint.textColor = textSecondary
        statusHint.textAlignment = .center
        statusHint.numberOfLines = 2
        statusHint.isHidden = true
        statusHint.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(statusHint)

        micButton.backgroundColor = orange
        micButton.layer.cornerRadius = 44
        micButton.layer.shadowColor = orange.cgColor
        micButton.layer.shadowOpacity = 0.35
        micButton.layer.shadowRadius = 16
        micButton.layer.shadowOffset = CGSize(width: 0, height: 6)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.accessibilityLabel = "麦克风"
        micButton.addTarget(self, action: #selector(micDown), for: .touchDown)
        micButton.addTarget(self, action: #selector(micCancel), for: [.touchUpOutside, .touchCancel])
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        panel.addSubview(micButton)

        micIcon.image = UIImage(systemName: "mic.fill")
        micIcon.tintColor = textPrimary
        micIcon.contentMode = .scaleAspectFit
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        micButton.addSubview(micIcon)

        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        globe.tintColor = textSecondary
        globe.translatesAutoresizingMaskIntoConstraints = false
        globe.accessibilityLabel = "切换键盘"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.isHidden = !needsInputModeSwitchKey
        panel.addSubview(globe)

        let del = UIButton(type: .system)
        del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.tintColor = textSecondary
        del.translatesAutoresizingMaskIntoConstraints = false
        del.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        panel.addSubview(del)

        NSLayoutConstraint.activate([
            hostLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            hostLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),

            panel.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 6),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 280),

            top.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            top.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            logo.widthAnchor.constraint(equalToConstant: 22),
            logo.heightAnchor.constraint(equalToConstant: 22),
            logoIcon.centerXAnchor.constraint(equalTo: logo.centerXAnchor),
            logoIcon.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            logoIcon.widthAnchor.constraint(equalToConstant: 12),
            logoIcon.heightAnchor.constraint(equalToConstant: 12),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            timerRow.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
            timerRow.centerXAnchor.constraint(equalTo: panel.centerXAnchor),

            tipBubble.topAnchor.constraint(equalTo: timerRow.bottomAnchor, constant: 8),
            tipBubble.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            tipBubble.heightAnchor.constraint(equalToConstant: 30),
            tipBubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),

            statusHint.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            statusHint.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            statusHint.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            micButton.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            micButton.topAnchor.constraint(equalTo: tipBubble.bottomAnchor, constant: 10),
            micButton.widthAnchor.constraint(equalToConstant: 88),
            micButton.heightAnchor.constraint(equalToConstant: 88),
            micIcon.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            micIcon.widthAnchor.constraint(equalToConstant: 30),
            micIcon.heightAnchor.constraint(equalToConstant: 30),

            globe.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 22),
            globe.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            globe.widthAnchor.constraint(equalToConstant: 36),
            globe.heightAnchor.constraint(equalToConstant: 36),

            del.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -22),
            del.centerYAnchor.constraint(equalTo: globe.centerYAnchor),
            del.widthAnchor.constraint(equalToConstant: 36),
            del.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func micDown() {
        UIView.animate(withDuration: 0.12) {
            self.micButton.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    @objc private func micCancel() {
        if !recording {
            UIView.animate(withDuration: 0.15) { self.micButton.transform = .identity }
        }
    }

    @objc private func micTapped() {
        guard hasFullAccess else {
            statusHint.text = "请先打开「允许完全访问」"
            statusHint.isHidden = false
            return
        }
        if recording {
            send(.stop)
            recording = false
            setRecordingUI(false)
            statusHint.text = "识别中…"
            statusHint.isHidden = false
        } else {
            sessionId = UUID().uuidString
            send(.start)
            recording = true
            recordingStartedAt = Date()
            setRecordingUI(true)
            statusHint.isHidden = true
            openContainingApp()
            startLevelSim()
        }
    }

    @objc private func closeTapped() {
        if recording {
            send(.cancel)
            recording = false
            setRecordingUI(false)
        }
        resignFirstResponder()
    }

    @objc private func deleteTapped() { textDocumentProxy.deleteBackward() }

    private func setRecordingUI(_ on: Bool) {
        timerRow.isHidden = !on
        tipBubble.isHidden = !on
        tipBubble.text = "再次点击以完成"
        tipBubble.textColor = textPrimary
        micIcon.image = UIImage(systemName: on ? "waveform" : "mic.fill")
        if on {
            clockLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(tickClock))
            link.add(to: .main, forMode: .common)
            clockLink = link
        } else {
            clockLink?.invalidate()
            clockLink = nil
            stopLevelSim()
            UIView.animate(withDuration: 0.2) { self.micButton.transform = .identity }
        }
    }

    @objc private func tickClock() {
        guard let start = recordingStartedAt else { return }
        let t = Int(Date().timeIntervalSince(start))
        timerLabel.text = String(format: "%d:%02d", t / 60, t % 60)
    }

    /// 扩展进程拿不到主 App 实时音量；用轻量假电平驱动弹簧，真音量由主 App RecordingView 负责。
    private func startLevelSim() {
        stopLevelSim()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.recording else { return }
            let t = CACurrentMediaTime()
            let level = 0.35 + 0.45 * abs(sin(t * 2.4)) + 0.15 * abs(sin(t * 5.1))
            let scale = 1 + 0.30 * level
            UIView.animate(withDuration: 0.42, delay: 0,
                           usingSpringWithDamping: 0.58, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.micButton.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    private func stopLevelSim() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func send(_ action: KeyboardCommand.Action) {
        let cmd = KeyboardCommand(action: action, sessionId: sessionId)
        try? mailbox.write(cmd, to: .keyboardCommand)
        DarwinNotifier.shared.post(.keyboardCommand)
    }

    private func openContainingApp() {
        guard let url = URL(string: "\(SharedConstants.urlScheme)://record") else { return }
        var responder: UIResponder? = self
        let sel = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: sel) {
                r.perform(sel, with: url)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }

    private func statusChanged() {
        guard let status = mailbox.read(AppStatus.self, from: .appStatus) else { return }
        guard status.revision != lastRevision else { return }
        lastRevision = status.revision
        switch status.state {
        case .done:
            if let text = status.text, !text.isEmpty {
                textDocumentProxy.insertText(text)
            }
            recording = false
            setRecordingUI(false)
            statusHint.text = "已插入"
            statusHint.isHidden = false
        case .error:
            recording = false
            setRecordingUI(false)
            tipBubble.isHidden = false
            tipBubble.text = status.message ?? "出错了"
            tipBubble.textColor = orange
            statusHint.isHidden = true
        case .recognizing:
            statusHint.text = "识别中…"
            statusHint.isHidden = false
        case .cleaning:
            statusHint.text = "整理中…"
            statusHint.isHidden = false
        case .idle:
            recording = false
            setRecordingUI(false)
        case .recording:
            break
        }
    }
}
