import Foundation
import VoiceStudioKit

nonisolated struct CachedVoiceEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}
private nonisolated struct CachedVoiceReply: Decodable, Sendable {
    let event: String
    let entries: [CachedVoiceEntry]?
    let message: String?
}
enum CachedVoiceImport {
    static func inspect(_ source: URL, python: String) async throws -> [CachedVoiceEntry] {
        let result = try await run(python: python, arguments: ["--inspect-cache", source.path])
        guard let entries = result.entries, !entries.isEmpty else { throw LibraryFile.failure("No XTTS voices were found in this file.") }
        return entries
    }
    static func convert(_ source: URL, entry: String, destination: URL, python: String) async throws {
        _ = try await run(python: python, arguments: ["--convert-cache", source.path, entry, destination.path])
    }
    @concurrent
    private static func run(python: String, arguments: [String]) async throws -> CachedVoiceReply {
        guard FileManager.default.isExecutableFile(atPath: python) else { throw LibraryFile.failure("Choose the XTTS Python interpreter in Settings > Engine before importing cached voices.") }
        guard let script = Bundle.main.resourceURL?.appending(path: "worker.py") else { throw LibraryFile.failure("The cached-voice importer is missing. Rebuild VoiceStudio.") }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-B", "-u", script.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard let result = try? JSONDecoder().decode(CachedVoiceReply.self, from: data) else {
            throw LibraryFile.failure("Unable to inspect the voice file. Check the XTTS Python environment in Settings > Engine.")
        }
        guard process.terminationStatus == 0 else { throw LibraryFile.failure(result.message ?? "Unable to read this XTTS voice file.") }
        return result
    }
}
