import AVFoundation
import Foundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var completion: ((URL?) -> Void)?
    private var recordingURL: URL?
    private var startedAt = Date()
    private var lastSpeechAt = Date()
    private var speechDetected = false

    var silenceThresholdDb: Float = -38
    var silenceDuration: TimeInterval = 0.8
    var minRecordingDuration: TimeInterval = 0.7
    private let noSpeechTimeout: TimeInterval = 5
    private let maxRecordingDuration: TimeInterval = 45

    func requestPermission(_ callback: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                callback(granted)
            }
        }
    }

    func recordUntilSilence(completion: @escaping (URL?) -> Void) throws {
        stop()

        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("carelesswhisper-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        self.recorder = recorder
        self.recordingURL = url
        self.completion = completion
        self.startedAt = Date()
        self.lastSpeechAt = Date()
        self.speechDetected = false

        recorder.record()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollMeter()
        }
    }

    func stop() {
        meterTimer?.invalidate()
        meterTimer = nil
        if recorder?.isRecording == true {
            recorder?.stop()
        }
        recorder = nil
    }

    private func pollMeter() {
        guard let recorder else { return }
        recorder.updateMeters()

        let level = recorder.averagePower(forChannel: 0)
        let elapsed = Date().timeIntervalSince(startedAt)

        if level > silenceThresholdDb {
            speechDetected = true
            lastSpeechAt = Date()
        }

        let silentFor = Date().timeIntervalSince(lastSpeechAt)
        if elapsed >= maxRecordingDuration {
            finish(success: speechDetected)
        } else if elapsed >= minRecordingDuration && speechDetected && silentFor >= silenceDuration {
            finish(success: true)
        } else if !speechDetected && elapsed >= noSpeechTimeout {
            finish(success: false)
        }
    }

    private func finish(success: Bool) {
        let url = recordingURL
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        recordingURL = nil

        let callback = completion
        completion = nil
        callback?(success ? url : nil)
    }
}
