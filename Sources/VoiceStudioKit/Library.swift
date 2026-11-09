import Foundation

public struct ScriptDocument: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var text: String
    public var createdAt = Date()
    public init(title: String = "Untitled Script", text: String = "") { self.title = title; self.text = text }
}
public struct VoiceReference: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var files: [String]
    public var cachedFile: String?
    public var createdAt = Date()
    public init(name: String, files: [String], cachedFile: String? = nil) { self.name = name; self.files = files; self.cachedFile = cachedFile }
}
public enum TakeStatus: String, Codable, Sendable, CaseIterable {
    case queued, running, completed, failed, canceled
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .queued: "clock"
        case .running: "waveform"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .canceled: "stop.circle"
        }
    }
}
public struct SpeechTake: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var scriptID: UUID
    public var title: String
    public var text: String
    public var voiceName: String
    public var speaker: String
    public var references: [String]
    public var cachedVoice: String?
    public var language: String
    public var speed: Double
    public var seed: Int
    public var modelFolder: String
    public var modelName: String
    public var device: String
    public var number: Int
    public var createdAt: Date
    public var status: TakeStatus
    public var duration: Double = 0
    public var generationSeconds: Double = 0
    public var audioFile: String
    public var error = ""
    public init(script: ScriptDocument, voiceName: String, speaker: String, references: [String], language: String,
                speed: Double, seed: Int, modelFolder: String, device: String, number: Int, cachedVoice: String? = nil) {
        self.id = UUID(); self.scriptID = script.id; self.title = script.title; self.text = script.text
        self.voiceName = voiceName; self.speaker = speaker; self.references = references; self.cachedVoice = cachedVoice
        self.language = language; self.speed = speed; self.seed = seed; self.modelFolder = modelFolder
        self.modelName = modelFolder.isEmpty ? "XTTS-v2" : URL(fileURLWithPath: modelFolder).lastPathComponent
        self.device = device; self.number = number; self.createdAt = Date(); self.status = .queued
        self.audioFile = "Audio/\(id.uuidString).wav"
    }
    public func audioURL(relativeTo libraryRoot: URL) -> URL {
        audioFile.hasPrefix("/") ? URL(fileURLWithPath: audioFile) : libraryRoot.appending(path: audioFile)
    }
    public var displayTitle: String { "\(title) · Take \(number)" }
}
public struct StudioLibrary: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var scripts: [ScriptDocument] = []
    public var voices: [VoiceReference] = []
    public var takes: [SpeechTake] = []
    /// The editor arrangement. Libraries saved before the editor existed have none.
    public var timeline = Timeline()
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        scripts = try c.decodeIfPresent([ScriptDocument].self, forKey: .scripts) ?? []
        voices = try c.decodeIfPresent([VoiceReference].self, forKey: .voices) ?? []
        takes = try c.decodeIfPresent([SpeechTake].self, forKey: .takes) ?? []
        timeline = try c.decodeIfPresent(Timeline.self, forKey: .timeline) ?? Timeline()
    }
    public mutating func recoverInterrupted() {
        for i in takes.indices where takes[i].status == .running {
            takes[i].status = .failed
            takes[i].error = "Generation was interrupted. Retry this take."
        }
    }
}
public enum LibraryFile {
    public static func load(from url: URL) throws -> StudioLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return StudioLibrary() }
        var result = try JSONDecoder().decode(StudioLibrary.self, from: Data(contentsOf: url))
        guard [1, 2, 3].contains(result.schemaVersion) else {
            throw NSError(domain: "VoiceStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "This library was created by a newer VoiceStudio version."])
        }
        result.schemaVersion = 3
        return result
    }
    public static func save(_ library: StudioLibrary, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
    public static func readScript(at url: URL) throws -> ScriptDocument {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 2_000_000 else { throw failure("\(url.lastPathComponent) is larger than 2 MB. Split it into smaller text files.") }
        let value: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            value = String(data: data, encoding: .utf16)
        } else {
            value = String(data: data, encoding: .utf8)
        }
        guard let value, !value.contains("\0") else { throw failure("\(url.lastPathComponent) is not a UTF-8 or UTF-16 text file.") }
        let text = value.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("\(url.lastPathComponent) is empty.") }
        return ScriptDocument(title: url.deletingPathExtension().lastPathComponent, text: text)
    }
    public static func failure(_ message: String) -> NSError {
        NSError(domain: "VoiceStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
public enum Languages {
    public static let all: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("pl", "Polish"), ("tr", "Turkish"),
        ("ru", "Russian"), ("nl", "Dutch"), ("cs", "Czech"), ("ar", "Arabic"),
        ("zh-cn", "Chinese"), ("ja", "Japanese"), ("hu", "Hungarian"), ("ko", "Korean"), ("hi", "Hindi")
    ]
    public static func name(_ code: String) -> String { all.first { $0.0 == code }?.1 ?? code }
}
