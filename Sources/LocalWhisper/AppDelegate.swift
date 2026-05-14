import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum TriggerMode {
        case automatic
        case manual
    }

    private enum VoiceCommand {
        case stopListening
        case startListening
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
    private var currentMode: TriggerMode = .automatic
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

    private var sensitivity: Double {
        get { UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 55 }
        set {
            UserDefaults.standard.set(newValue, forKey: "sensitivity")
            applyRecorderSettings()
            refreshMenu()
        }
    }

    private var startDelay: Double {
        get { UserDefaults.standard.object(forKey: "startDelay") as? Double ?? 0.7 }
        set {
            UserDefaults.standard.set(newValue, forKey: "startDelay")
            applyRecorderSettings()
            refreshMenu()
        }
    }

    private var stopDelay: Double {
        get { UserDefaults.standard.object(forKey: "stopDelay") as? Double ?? 0.8 }
        set {
            UserDefaults.standard.set(newValue, forKey: "stopDelay")
            applyRecorderSettings()
            refreshMenu()
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
                    message: "LocalWhisper needs microphone access to record dictation snippets."
                )
            } else {
                self.startAutomaticIfNeeded()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshMenu()
    }

    private func refreshMenu() {
        updateIcon()
        statusItem.menu = buildMenu()
    }

    private func updateIcon() {
        let symbol = isDictating ? "waveform.circle.fill" : (isEnabled ? "mic.circle.fill" : "mic.circle")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LocalWhisper")
        statusItem.button?.image?.isTemplate = true
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let dictate = NSMenuItem(title: isDictating ? "Listening..." : "Dictate Now", action: #selector(dictateNow), keyEquivalent: "")
        dictate.target = self
        dictate.isEnabled = isEnabled && !isDictating
        menu.addItem(dictate)

        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = isEnabled ? .on : .off
        menu.addItem(enabled)

        let submit = NSMenuItem(title: "Press Return After Typing", action: #selector(toggleSubmit), keyEquivalent: "")
        submit.target = self
        submit.state = submitAfterTyping ? .on : .off
        menu.addItem(submit)

        let sticky = NSMenuItem(title: "Use Last Target When Focus Changes", action: #selector(toggleStickyTarget), keyEquivalent: "")
        sticky.target = self
        sticky.state = stickyTargetEnabled ? .on : .off
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
            title: "Start Delay",
            valueText: String(format: "%.1fs", startDelay),
            minValue: 0.1,
            maxValue: 2.0,
            value: startDelay,
            action: #selector(startDelayChanged(_:))
        ))
        menu.addItem(sliderMenuItem(
            title: "Stop Delay",
            valueText: String(format: "%.1fs", stopDelay),
            minValue: 0.2,
            maxValue: 2.5,
            value: stopDelay,
            action: #selector(stopDelayChanged(_:))
        ))

        menu.addItem(.separator())

        let permissions = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let logItem = NSMenuItem(title: "Open Debug Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LocalWhisper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
    }

    @objc private func startDelayChanged(_ sender: NSSlider) {
        startDelay = sender.doubleValue
    }

    @objc private func stopDelayChanged(_ sender: NSSlider) {
        stopDelay = sender.doubleValue
    }

    @objc private func requestAccessibility() {
        typer.requestAccessibilityPermission()
    }

    @objc private func openLog() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/localwhisper/debug.log")
        NSWorkspace.shared.open(path)
    }

    @objc private func dictateNow() {
        guard isEnabled else { return }
        guard !isDictating else { return }
        armTimer?.invalidate()
        armTimer = nil

        log("dictate requested - frontmost: \(focus.activeDescription())")
        refreshLastTarget()
        guard typingTarget() != nil else {
            log("blocked: no supported typing target")
            showAlert(title: "No target selected", message: targetHelpText())
            return
        }

        guard typer.hasAccessibilityPermission else {
            log("blocked: no accessibility permission")
            typer.requestAccessibilityPermission()
            return
        }

        recorder.requestPermission { granted in
            guard granted else {
                self.showAlert(title: "Microphone access required", message: "Grant LocalWhisper microphone access in System Settings.")
                return
            }
            self.startRecording(mode: .manual)
        }
    }

    private func startAutomaticIfNeeded() {
        guard isEnabled else { return }
        guard !isDictating else { return }
        refreshLastTarget()

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
            self.startRecording(mode: .automatic)
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

    private func startRecording(mode: TriggerMode) {
        do {
            applyRecorderSettings()
            currentMode = mode
            isDictating = true
            refreshMenu()
            log("recording started (\(mode == .automatic ? "automatic" : "manual"))")
            try recorder.recordUntilSilence { [weak self] url in
                DispatchQueue.main.async {
                    self?.handleRecording(url)
                }
            }
        } catch {
            isDictating = false
            refreshMenu()
            log("recording failed: \(error.localizedDescription)")
            if currentMode == .manual {
                showAlert(title: "Recording failed", message: error.localizedDescription)
            }
            scheduleArmCheck()
        }
    }

    private func handleRecording(_ url: URL?) {
        guard let url else {
            isDictating = false
            refreshMenu()
            log("recording ended without speech")
            if currentMode == .automatic {
                scheduleArmCheck(after: 0.2)
            }
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
        let mode = currentMode
        isDictating = false
        refreshMenu()
        defer {
            if isEnabled {
                scheduleArmCheck(after: mode == .automatic ? 0.3 : 1.0)
            }
        }

        switch result {
        case .failure(let error):
            log("transcription failed: \(error.localizedDescription)")
            if mode == .manual {
                showAlert(title: "Transcription failed", message: error.localizedDescription)
            }
        case .success(let transcription):
            guard transcription.success else {
                let message = transcription.error ?? "Unknown Whisper error"
                log("transcription failed: \(message)")
                if mode == .manual {
                    showAlert(title: "Transcription failed", message: message)
                }
                return
            }

            let text = transcription.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                log("transcription empty")
                return
            }

            if let command = voiceCommand(from: text) {
                handleVoiceCommand(command, originalText: text)
                return
            }

            refreshLastTarget()
            guard let target = typingTarget() else {
                log("blocked after transcription: no typing target")
                if mode == .manual {
                    showAlert(title: "No target selected", message: targetHelpText())
                }
                return
            }

            if stickyTargetEnabled && !target.isActive {
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
            return "Status: Disabled"
        }
        if isDictating {
            return currentMode == .automatic ? "Status: Listening" : "Status: Dictating"
        }
        if let current = focus.currentSupportedApplication() {
            lastTarget = current
            return "Status: Armed for \(current.localizedName ?? "target")"
        }
        if stickyTargetEnabled, let target = usableLastTarget() {
            return "Status: Armed for last \(target.localizedName ?? "target")"
        }
        return "Status: Waiting for Claude/Codex/OpenCode"
    }

    private func refreshLastTarget() {
        if let current = focus.currentSupportedApplication() {
            lastTarget = current
        }
    }

    private func typingTarget() -> NSRunningApplication? {
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
            return "Focus Claude, Codex, OpenCode, or a supported terminal once so LocalWhisper knows where to type."
        }
        return "Focus Claude, Codex, OpenCode, or a supported terminal before dictating, or enable sticky target mode."
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
            "localwhisper stop",
            "local whisper stop listening",
            "localwhisper stop listening"
        ]
        if stopCommands.contains(normalized) {
            return .stopListening
        }

        let startCommands: Set<String> = [
            "start listening",
            "start dictation",
            "enable dictation",
            "turn on dictation",
            "turn on listening",
            "local whisper start",
            "localwhisper start",
            "local whisper start listening",
            "localwhisper start listening"
        ]
        if startCommands.contains(normalized) {
            return .startListening
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
        case .startListening:
            isEnabled = true
            startAutomaticIfNeeded()
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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 48))

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 12, y: 25, width: 120, height: 18)
        label.font = .systemFont(ofSize: 12)
        view.addSubview(label)

        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.frame = NSRect(x: 178, y: 25, width: 70, height: 18)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        view.addSubview(valueLabel)

        let slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue, target: self, action: action)
        slider.frame = NSRect(x: 10, y: 4, width: 238, height: 22)
        slider.isContinuous = false
        view.addSubview(slider)

        item.view = view
        return item
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
