import Foundation
import WhisperBridge

struct TranscriptionResult: Decodable {
    let success: Bool
    let text: String?
    let language: String?
    let error: String?
}

final class WhisperTranscriber {
    private enum Backend {
        case bridge
        case whisperCpp
        case python
    }

    private let fileManager = FileManager.default

    func transcribe(audioURL: URL) throws -> TranscriptionResult {
        let backend = resolveBackend()
        switch backend {
        case .bridge:
            return try transcribeWithBridge(audioURL: audioURL)
        case .whisperCpp:
            return try transcribeWithWhisperCpp(audioURL: audioURL)
        case .python:
            return try transcribeWithPython(audioURL: audioURL)
        }
    }

    private func transcribeWithBridge(audioURL: URL) throws -> TranscriptionResult {
        let model = try resolveWhisperCppModel()
        let language = ProcessInfo.processInfo.environment["LOCALWHISPER_LANGUAGE"] ?? "en"

        guard let ptr = lw_transcribe_wav_file(model.path, audioURL.path, language) else {
            return TranscriptionResult(success: false, text: nil, language: nil, error: "native Whisper bridge returned no result")
        }
        defer { lw_free_string(ptr) }

        let raw = String(cString: ptr)
        if raw.hasPrefix("ERROR: ") {
            return TranscriptionResult(success: false, text: nil, language: nil, error: raw)
        }

        return TranscriptionResult(success: true, text: raw.trimmingCharacters(in: .whitespacesAndNewlines), language: language, error: nil)
    }

    private func transcribeWithWhisperCpp(audioURL: URL) throws -> TranscriptionResult {
        let cli = try resolveWhisperCli()
        let model = try resolveWhisperCppModel()
        let language = ProcessInfo.processInfo.environment["LOCALWHISPER_LANGUAGE"] ?? "en"

        let task = Process()
        task.executableURL = cli
        task.arguments = [
            "-ng",
            "-m", model.path,
            "-f", audioURL.path,
            "-l", language,
            "-nt",
            "-np"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        task.environment = subprocessEnvironment()

        try task.run()
        task.waitUntilExit()

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("whisper.cpp stderr: \(err)")
        }

        guard task.terminationStatus == 0 else {
            let detail = err.isEmpty ? out : err
            return TranscriptionResult(success: false, text: nil, language: nil, error: "whisper.cpp failed: \(detail)")
        }

        return TranscriptionResult(success: true, text: parseWhisperCppOutput(out), language: language, error: nil)
    }

    private func transcribeWithPython(audioURL: URL) throws -> TranscriptionResult {
        let script = try resolveScript()
        let python = resolvePython(scriptURL: script)
        let model = ProcessInfo.processInfo.environment["LOCALWHISPER_MODEL"] ?? "base"
        let language = ProcessInfo.processInfo.environment["LOCALWHISPER_LANGUAGE"] ?? "auto"

        let task = Process()
        if python.path == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["python3", script.path, audioURL.path, "--model", model, "--language", language]
        } else {
            task.executableURL = python
            task.arguments = [script.path, audioURL.path, "--model", model, "--language", language]
        }

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        task.environment = subprocessEnvironment()

        try task.run()
        task.waitUntilExit()

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("whisper stderr: \(err)")
        }

        if let decoded = try? JSONDecoder().decode(TranscriptionResult.self, from: out) {
            return decoded
        }

        let raw = String(data: out, encoding: .utf8) ?? ""
        return TranscriptionResult(success: false, text: nil, language: nil, error: "Could not parse Whisper output: \(raw)")
    }

    private func resolveBackend() -> Backend {
        let configured = ProcessInfo.processInfo.environment["LOCALWHISPER_BACKEND"]?.lowercased()
        if configured == "bridge" || configured == "native" {
            return .bridge
        }
        if configured == "python" {
            return .python
        }
        if configured == "whisper.cpp" || configured == "whisper-cpp" {
            return .whisperCpp
        }
        if (try? resolveWhisperCppModel()) != nil {
            return .bridge
        }
        if (try? resolveWhisperCli()) != nil && (try? resolveWhisperCppModel()) != nil {
            return .whisperCpp
        }
        return .python
    }

    private func resolveWhisperCli() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["LOCALWHISPER_WHISPER_CLI"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        let candidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("bin/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw NSError(domain: "LocalWhisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not find whisper-cli"])
    }

    private func resolveWhisperCppModel() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["LOCALWHISPER_CPP_MODEL"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        let modelName = ProcessInfo.processInfo.environment["LOCALWHISPER_CPP_MODEL_NAME"] ?? "ggml-base.en.bin"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(".models/whisper.cpp/\(modelName)"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".models/whisper.cpp/\(modelName)"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".models/whisper.cpp/\(modelName)")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw NSError(domain: "LocalWhisper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find whisper.cpp model"])
    }

    private func parseWhisperCppOutput(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*\[[^\]]+\]\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty
                    && !trimmed.hasPrefix("whisper_")
                    && !trimmed.hasPrefix("main:")
                    && !trimmed.hasPrefix("system_info:")
                    && !trimmed.hasPrefix("load_backend:")
                    && !trimmed.hasPrefix("ggml_")
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveScript() throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("transcribe_file.py"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Scripts/transcribe_file.py"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/transcribe_file.py")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw NSError(domain: "LocalWhisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find transcribe_file.py"])
    }

    private func resolvePython(scriptURL: URL) -> URL {
        if let configured = ProcessInfo.processInfo.environment["LOCALWHISPER_PYTHON"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(".venv/bin/python3"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".venv/bin/python3"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".venv/bin/python3"),
            scriptURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".venv/bin/python3")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func subprocessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let appPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ].joined(separator: ":")
        env["PATH"] = existingPath.isEmpty ? appPath : "\(appPath):\(existingPath)"
        return env
    }
}
