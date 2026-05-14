import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum VoiceCommand {
        case stopListening
        case undo
        case redo
        case toggleTypeAnywhere
        case disableTypeAnywhere
        case enableTypeAnywhere
        case toggleStickyTarget
        case disableStickyTarget
        case enableStickyTarget
        case toggleSubmit
        case disableSubmit
        case enableSubmit
    }

    private var statusItem: NSStatusItem!
    private let focus = FocusChecker()
    private let typer = Typer()
    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private var isDictating = false
    private var armTimer: Timer?
    private var lastTarget: NSRunningApplication?

    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "enabled")
            refreshMenu()
        }
    }

    private var submitAfterTyping: Bool {
        get { UserDefaults.standard.object(forKey: "submitAfterTyping") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "submitAfterTyping")
            refreshMenu()
        }
    }

    private var stickyTargetEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "stickyTargetEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "stickyTargetEnabled")
            refreshMenu()
        }
    }

    private var typeAnywhereEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "typeAnywhereEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "typeAnywhereEnabled")
            refreshMenu()
        }
    }

    private var sensitivity: Double {
        get { UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 55 }
        set {
            UserDefaults.standard.set(newValue, forKey: "sensitivity")
            applyRecorderSettings()
        }
    }

    private var startDelay: Double {
        get { UserDefaults.standard.object(forKey: "startDelay") as? Double ?? 0.7 }
        set {
            UserDefaults.standard.set(newValue, forKey: "startDelay")
            applyRecorderSettings()
        }
    }

    private var stopDelay: Double {
        get { UserDefaults.standard.object(forKey: "stopDelay") as? Double ?? 0.8 }
        set {
            UserDefaults.standard.set(newValue, forKey: "stopDelay")
            applyRecorderSettings()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        applyRecorderSettings()
        checkAccessibility()
        recorder.requestPermission { granted in
            if !granted {
                self.showAlert(
                    title: "Microphone access required",
                    message: "CarelessWhisper needs microphone access to record dictation snippets."
                )
            } else {
                self.startAutomaticIfNeeded()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        refreshMenu()
    }

    private func refreshMenu() {
        updateIcon()
        statusItem.menu = buildMenu()
    }

    private func updateIcon() {
        statusItem.button?.image = statusIcon()
        statusItem.button?.image?.isTemplate = false
    }

    private func statusIcon() -> NSImage {
        let resourceName = isEnabled ? "active" : "inactive"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 24, height: 17)
            image.accessibilityDescription = "CarelessWhisper"
            image.isTemplate = false
            return image
        }
        return fallbackStatusIcon()
    }

    private func fallbackStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let strokeColor = NSColor.labelColor
        strokeColor.setStroke()

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = isDictating ? 2.7 : 2.3

        let midY: CGFloat = 9
        let points: [NSPoint] = [
            NSPoint(x: 2.0, y: midY),
            NSPoint(x: 4.2, y: isEnabled ? 5.0 : 7.0),
            NSPoint(x: 6.5, y: isEnabled ? 13.0 : 11.0),
            NSPoint(x: 9.0, y: isDictating ? 3.0 : 5.0),
            NSPoint(x: 11.5, y: isDictating ? 15.0 : 13.0),
            NSPoint(x: 13.8, y: isEnabled ? 5.0 : 7.0),
            NSPoint(x: 16.0, y: midY)
        ]

        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.stroke()

        if !isEnabled {
            let slash = NSBezierPath()
            slash.lineCapStyle = .round
            slash.lineWidth = 2.0
            slash.move(to: NSPoint(x: 4.0, y: 4.0))
            slash.line(to: NSPoint(x: 14.0, y: 14.0))
            slash.stroke()
        }

        image.unlockFocus()
        image.accessibilityDescription = "CarelessWhisper"
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = isEnabled ? .on : .off
        menu.addItem(enabled)

        let typeAnywhere = NSMenuItem(title: "Type Anywhere", action: #selector(toggleTypeAnywhere), keyEquivalent: "")
        typeAnywhere.target = self
        typeAnywhere.state = typeAnywhereEnabled ? .on : .off
        menu.addItem(typeAnywhere)

        let submit = NSMenuItem(title: "Auto-Return", action: #selector(toggleSubmit), keyEquivalent: "")
        submit.target = self
        submit.state = submitAfterTyping ? .on : .off
        menu.addItem(submit)

        let sticky = NSMenuItem(title: "Sticky Target", action: #selector(toggleStickyTarget), keyEquivalent: "")
        sticky.target = self
        sticky.state = stickyTargetEnabled ? .on : .off
        sticky.isEnabled = !typeAnywhereEnabled
        menu.addItem(sticky)

        menu.addItem(.separator())
        menu.addItem(sliderMenuItem(
            title: "Sensitivity",
            valueText: "\(Int(sensitivity))%",
            minValue: 0,
            maxValue: 100,
            value: sensitivity,
            action: #selector(sensitivityChanged(_:))
        ))
        menu.addItem(sliderMenuItem(
            title: "Start",
            valueText: String(format: "%.1fs", startDelay),
            minValue: 0.1,
            maxValue: 2.0,
            value: startDelay,
            action: #selector(startDelayChanged(_:))
        ))
        menu.addItem(sliderMenuItem(
            title: "Stop",
            valueText: String(format: "%.1fs", stopDelay),
            minValue: 0.2,
            maxValue: 2.5,
            value: stopDelay,
            action: #selector(stopDelayChanged(_:))
        ))

        menu.addItem(.separator())

        let permissions = NSMenuItem(title: "Accessibility", action: #selector(requestAccessibility), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let logItem = NSMenuItem(title: "Debug Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let commandsItem = NSMenuItem(title: "Voice Commands", action: #selector(showVoiceCommands), keyEquivalent: "")
        commandsItem.target = self
        menu.addItem(commandsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            checkAccessibility()
            startAutomaticIfNeeded()
        } else {
            disarm()
        }
    }

    @objc private func toggleSubmit() {
        submitAfterTyping.toggle()
    }

    @objc private func toggleTypeAnywhere() {
        typeAnywhereEnabled.toggle()
        if isEnabled {
            startAutomaticIfNeeded()
        }
    }

    @objc private func toggleStickyTarget() {
        stickyTargetEnabled.toggle()
        if !stickyTargetEnabled {
            lastTarget = nil
        } else {
            refreshLastTarget()
        }
        startAutomaticIfNeeded()
    }

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        sensitivity = sender.doubleValue
        updateSliderValue(sender, text: "\(Int(sender.doubleValue.rounded()))%")
    }

    @objc private func startDelayChanged(_ sender: NSSlider) {
        startDelay = sender.doubleValue
        updateSliderValue(sender, text: String(format: "%.1fs", sender.doubleValue))
    }

    @objc private func stopDelayChanged(_ sender: NSSlider) {
        stopDelay = sender.doubleValue
        updateSliderValue(sender, text: String(format: "%.1fs", sender.doubleValue))
    }

    @objc private func requestAccessibility() {
        typer.requestAccessibilityPermission()
    }

    @objc private func openLog() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/carelesswhisper/debug.log")
        NSWorkspace.shared.open(path)
    }

    @objc private func showVoiceCommands() {
        showAlert(
            title: "Voice Commands",
            message: """
            Stop dictation:
            stop listening
            stop dictation
            disable dictation
            turn off listening

            Sticky target:
            enable sticky target
            disable sticky target
            toggle sticky target

            Type anywhere:
            type anywhere
            targeted mode
            toggle type anywhere

            Submit:
            press return
            do not press return
            toggle submit

            Edit:
            undo
            redo
            """
        )
    }

    private func startAutomaticIfNeeded() {
        guard isEnabled else { return }
        guard !isDictating else { return }
        if !typeAnywhereEnabled {
            refreshLastTarget()
        }

        guard typer.hasAccessibilityPermission else {
            scheduleArmCheck()
            return
        }

        guard typingTarget() != nil else {
            scheduleArmCheck()
            return
        }

        recorder.requestPermission { granted in
            guard granted else {
                self.scheduleArmCheck()
                return
            }
            self.startRecording()
        }
    }

    private func scheduleArmCheck(after delay: TimeInterval = 1.0) {
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startAutomaticIfNeeded()
        }
        refreshMenu()
    }

    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        recorder.stop()
        isDictating = false
        refreshMenu()
        log("disabled")
    }

    private func startRecording() {
        do {
            applyRecorderSettings()
            isDictating = true
            refreshMenu()
            log("recording started")
            try recorder.recordUntilSilence { [weak self] url in
                DispatchQueue.main.async {
                    self?.handleRecording(url)
                }
            }
        } catch {
            isDictating = false
            refreshMenu()
            log("recording failed: \(error.localizedDescription)")
            scheduleArmCheck()
        }
    }

    private func handleRecording(_ url: URL?) {
        guard let url else {
            isDictating = false
            refreshMenu()
            log("recording ended without speech")
            scheduleArmCheck(after: 0.2)
            return
        }

        log("recording saved: \(url.path)")
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<TranscriptionResult, Error>
            do {
                result = .success(try self.transcriber.transcribe(audioURL: url))
            } catch {
                result = .failure(error)
            }
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                self.handleTranscription(result)
            }
        }
    }

    private func handleTranscription(_ result: Result<TranscriptionResult, Error>) {
        isDictating = false
        refreshMenu()
        defer {
            if isEnabled {
                scheduleArmCheck(after: 0.3)
            }
        }

        switch result {
        case .failure(let error):
            log("transcription failed: \(error.localizedDescription)")
        case .success(let transcription):
            guard transcription.success else {
                let message = transcription.error ?? "Unknown Whisper error"
                log("transcription failed: \(message)")
                return
            }

            let rawText = transcription.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = sanitizeTranscription(rawText)
            if text != rawText {
                log("sanitized transcription: \(rawText) -> \(text)")
            }
            guard !text.isEmpty else {
                log("transcription empty")
                return
            }

            if let command = voiceCommand(from: text) {
                handleVoiceCommand(command, originalText: text)
                return
            }

            if !typeAnywhereEnabled {
                refreshLastTarget()
            }
            guard let target = typingTarget() else {
                log("blocked after transcription: no typing target")
                return
            }

            if !typeAnywhereEnabled && stickyTargetEnabled && !target.isActive {
                log("activating remembered target: \(target.localizedName ?? "unknown") [\(target.bundleIdentifier ?? "unknown")]")
                target.activate(options: [])
                Thread.sleep(forTimeInterval: 0.15)
            }

            log("typing transcription into \(target.localizedName ?? "target"): \(text)")
            typer.type(text, submit: submitAfterTyping)
        }
    }

    private func statusText() -> String {
        if !isEnabled {
            return "Disabled"
        }
        if isDictating {
            return "Listening"
        }
        if typeAnywhereEnabled {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "current app"
            return "Anywhere: \(appName)"
        }
        if let current = focus.currentSupportedApplication() {
            lastTarget = current
            return "Armed: \(current.localizedName ?? "target")"
        }
        if stickyTargetEnabled, let target = usableLastTarget() {
            return "Sticky: \(target.localizedName ?? "target")"
        }
        return "Waiting"
    }

    private func refreshLastTarget() {
        guard !typeAnywhereEnabled else { return }
        if let current = focus.currentSupportedApplication() {
            lastTarget = current
        }
    }

    private func typingTarget() -> NSRunningApplication? {
        if typeAnywhereEnabled {
            return NSWorkspace.shared.frontmostApplication
        }
        if let current = focus.currentSupportedApplication() {
            return current
        }
        if stickyTargetEnabled {
            return usableLastTarget()
        }
        return nil
    }

    private func usableLastTarget() -> NSRunningApplication? {
        guard let target = lastTarget, !target.isTerminated else { return nil }
        return target
    }

    private func targetHelpText() -> String {
        if stickyTargetEnabled {
            return "Focus Claude, Codex, OpenCode, or a supported terminal once so CarelessWhisper knows where to type."
        }
        return "Focus Claude, Codex, OpenCode, or a supported terminal before dictating, or enable sticky target mode."
    }

    private func sanitizeTranscription(_ text: String) -> String {
        let artifactPattern = #"(?i)\s*[\[\(]\s*(music|sound|sounds|blank(?:[_ -]?audio)?|silence|noise|no[_ -]?speech|inaudible|applause|laughter)\s*[\]\)]\s*"#
        return text
            .replacingOccurrences(of: artifactPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func voiceCommand(from text: String) -> VoiceCommand? {
        let normalized = normalizeCommandText(text)
        guard !normalized.isEmpty else { return nil }

        let stopCommands: Set<String> = [
            "stop listening",
            "stop dictation",
            "disable dictation",
            "turn off dictation",
            "turn off listening",
            "local whisper stop",
            "careless whisper stop",
            "carelesswhisper stop",
            "local whisper stop listening",
            "careless whisper stop listening",
            "carelesswhisper stop listening"
        ]
        if stopCommands.contains(normalized) {
            return .stopListening
        }

        if normalized == "undo" {
            return .undo
        }

        if normalized == "redo" {
            return .redo
        }

        let typeAnywhereOnCommands: Set<String> = [
            "type anywhere",
            "enable type anywhere",
            "turn on type anywhere",
            "dictate anywhere"
        ]
        if typeAnywhereOnCommands.contains(normalized) {
            return .enableTypeAnywhere
        }

        let typeAnywhereOffCommands: Set<String> = [
            "targeted mode",
            "disable type anywhere",
            "turn off type anywhere",
            "do not type anywhere",
            "dont type anywhere"
        ]
        if typeAnywhereOffCommands.contains(normalized) {
            return .disableTypeAnywhere
        }

        if normalized == "toggle type anywhere" {
            return .toggleTypeAnywhere
        }

        let stickyOnCommands: Set<String> = [
            "enable sticky target",
            "turn on sticky target",
            "use last target",
            "remember target"
        ]
        if stickyOnCommands.contains(normalized) {
            return .enableStickyTarget
        }

        let stickyOffCommands: Set<String> = [
            "disable sticky target",
            "turn off sticky target",
            "do not use last target",
            "dont use last target",
            "forget target"
        ]
        if stickyOffCommands.contains(normalized) {
            return .disableStickyTarget
        }

        if normalized == "toggle sticky target" {
            return .toggleStickyTarget
        }

        let submitOnCommands: Set<String> = [
            "enable submit",
            "press return",
            "press enter",
            "turn on submit",
            "submit after typing"
        ]
        if submitOnCommands.contains(normalized) {
            return .enableSubmit
        }

        let submitOffCommands: Set<String> = [
            "disable submit",
            "do not press return",
            "dont press return",
            "do not press enter",
            "dont press enter",
            "turn off submit"
        ]
        if submitOffCommands.contains(normalized) {
            return .disableSubmit
        }

        if normalized == "toggle submit" {
            return .toggleSubmit
        }

        return nil
    }

    private func handleVoiceCommand(_ command: VoiceCommand, originalText: String) {
        log("voice command: \(originalText)")

        switch command {
        case .stopListening:
            isEnabled = false
            disarm()
        case .undo:
            typer.undo()
        case .redo:
            typer.redo()
        case .toggleTypeAnywhere:
            typeAnywhereEnabled.toggle()
        case .disableTypeAnywhere:
            typeAnywhereEnabled = false
        case .enableTypeAnywhere:
            typeAnywhereEnabled = true
        case .toggleStickyTarget:
            stickyTargetEnabled.toggle()
            if !stickyTargetEnabled {
                lastTarget = nil
            }
        case .disableStickyTarget:
            stickyTargetEnabled = false
            lastTarget = nil
        case .enableStickyTarget:
            stickyTargetEnabled = true
            refreshLastTarget()
        case .toggleSubmit:
            submitAfterTyping.toggle()
        case .disableSubmit:
            submitAfterTyping = false
        case .enableSubmit:
            submitAfterTyping = true
        }

        refreshMenu()
    }

    private func normalizeCommandText(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
                ? Character(scalar)
                : " "
        }
        return String(allowed)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func applyRecorderSettings() {
        recorder.silenceThresholdDb = Float(-25.0 - (sensitivity * 0.24))
        recorder.minRecordingDuration = startDelay
        recorder.silenceDuration = stopDelay
    }

    private func sliderMenuItem(
        title: String,
        valueText: String,
        minValue: Double,
        maxValue: Double,
        value: Double,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 42))

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 12, y: 22, width: 90, height: 17)
        label.font = .systemFont(ofSize: 12)
        view.addSubview(label)

        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.identifier = NSUserInterfaceItemIdentifier("sliderValue")
        valueLabel.frame = NSRect(x: 154, y: 22, width: 54, height: 17)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        view.addSubview(valueLabel)

        let slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue, target: self, action: action)
        slider.frame = NSRect(x: 10, y: 3, width: 198, height: 20)
        slider.isContinuous = true
        view.addSubview(slider)

        item.view = view
        return item
    }

    private func updateSliderValue(_ slider: NSSlider, text: String) {
        guard let view = slider.superview else { return }
        let label = view.subviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "sliderValue"
        }
        label?.stringValue = text
    }

    private func checkAccessibility() {
        if !typer.hasAccessibilityPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.typer.requestAccessibilityPermission()
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
