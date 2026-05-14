import Foundation
import WhisperBridge

struct TranscriptionResult {
    let success: Bool
    let text: String?
    let error: String?
}

final class WhisperTranscriber {
    private let fileManager = FileManager.default

    func transcribe(audioURL: URL) throws -> TranscriptionResult {
        let model = try resolveModel()
        let language = env("LANGUAGE") ?? "en"

        guard let ptr = lw_transcribe_wav_file(model.path, audioURL.path, language) else {
            return TranscriptionResult(success: false, text: nil, error: "native Whisper bridge returned no result")
        }
        defer { lw_free_string(ptr) }

        let raw = String(cString: ptr)
        if raw.hasPrefix("ERROR: ") {
            return TranscriptionResult(success: false, text: nil, error: raw)
        }

        return TranscriptionResult(
            success: true,
            text: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            error: nil
        )
    }

    private func resolveModel() throws -> URL {
        if let configured = env("CPP_MODEL"), !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        let modelName = env("CPP_MODEL_NAME") ?? "ggml-base.en.bin"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(".models/whisper.cpp/\(modelName)"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".models/whisper.cpp/\(modelName)")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw NSError(domain: "CarelessWhisper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find whisper.cpp model"])
    }

    private func env(_ suffix: String) -> String? {
        ProcessInfo.processInfo.environment["CARELESSWHISPER_\(suffix)"]
    }
}
