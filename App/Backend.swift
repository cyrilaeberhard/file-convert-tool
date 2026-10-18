import Foundation

enum Backend {
    static let python: String = {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
    }()

    static var script: String {
        Bundle.main.path(forResource: "fileconvert", ofType: "py") ?? ""
    }

    /// Startet das Python-CLI und gibt (Erfolg, Ausgabe) zurück.
    static func run(_ args: [String]) -> (Bool, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [script] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (task.terminationStatus == 0, text)
    }
}
