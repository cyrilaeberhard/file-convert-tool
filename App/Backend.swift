import Foundation

enum Backend {
    #if arch(arm64)
    private static let bundledDir = "python-arm64"
    #else
    private static let bundledDir = "python-x86_64"
    #endif

    /// Eingebettetes Python zuerst, damit weder Homebrew noch die Developer Tools nötig sind.
    static let python: String = {
        let bundled = Bundle.main.resourcePath.map { "\($0)/\(bundledDir)/bin/python3" }
        return ([bundled].compactMap { $0 }
            + ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"])
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
        env["PYTHONDONTWRITEBYTECODE"] = "1"
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
