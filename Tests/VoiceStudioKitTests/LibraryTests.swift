import Foundation

import VoiceStudioKit

@main
@MainActor
struct LibraryChecks {
static var checks = 0
static func expect(_ value: @autoclosure () throws -> Bool) throws {
    checks += 1
    guard try value() else { throw LibraryFile.failure("Check \(checks) failed") }
}
static func expectThrows<T>(_ operation: @autoclosure () throws -> T) throws {
    checks += 1
    do { _ = try operation() } catch { return }
    throw LibraryFile.failure("Check \(checks) expected an error")
}
static func main() throws {
    try testImports(); try testSnapshotsAndRecovery(); try testCorruptLibrary(); try testCachedVoiceCompatibility()
    print("PASS \(checks) library checks")
}
static func testImports() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let utf8 = root.appendingPathComponent("Chapter.txt")
    try "Hello, 世界.\nA second line.".write(to: utf8, atomically: true, encoding: .utf8)
    try expect(try LibraryFile.readScript(at: utf8).text == "Hello, 世界.\nA second line.")
    let utf16 = root.appendingPathComponent("French.txt")
    try "Une histoire différente.".write(to: utf16, atomically: true, encoding: .utf16)
    try expect(try LibraryFile.readScript(at: utf16).title == "French")
    try expect(try LibraryFile.readScript(at: utf16).text == "Une histoire différente.")
    try Data([0, 1, 0, 3]).write(to: utf8)
    try expectThrows(try LibraryFile.readScript(at: utf8))
    try " \n ".write(to: utf8, atomically: true, encoding: .utf8)
    try expectThrows(try LibraryFile.readScript(at: utf8))
}
static func testSnapshotsAndRecovery() throws {
    var script = ScriptDocument(title: "Chapter", text: "Original words.")
    let take = SpeechTake(script: script, voiceName: "Narrator", speaker: "", references: ["reference.wav"], language: "fr", speed: 0.8, seed: 42, modelFolder: "", device: "mps", number: 1)
    script.text = "Changed."
    try expect(take.text == "Original words.")
    var library = StudioLibrary(); library.scripts = [script]; library.takes = [take, take]
    library.takes[0].status = .running
    library.recoverInterrupted()
    try expect(library.takes[0].status == .failed)
    try expect(library.takes[1].status == .queued)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceStudio-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try LibraryFile.save(library, to: url)
    try expect(try LibraryFile.load(from: url) == library)
}
static func testCorruptLibrary() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceStudio-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = Data("{invalid".utf8)
    try bytes.write(to: url)
    try expectThrows(try LibraryFile.load(from: url))
    try expect(try Data(contentsOf: url) == bytes)
    var library = StudioLibrary(); library.schemaVersion = 100
    try LibraryFile.save(library, to: url)
    try expectThrows(try LibraryFile.load(from: url))
}
static func testCachedVoiceCompatibility() throws {
    let voice = VoiceReference(name: "Imported narrator", files: [], cachedFile: "Voices/test/cache.pth")
    var library = StudioLibrary(); library.voices = [voice]
    let script = ScriptDocument(title: "Test", text: "Hello.")
    library.takes = [SpeechTake(script: script, voiceName: voice.name, speaker: "", references: [], language: "en", speed: 1, seed: 42, modelFolder: "", device: "mps", number: 1, cachedVoice: voice.cachedFile)]
    let encoded = try JSONEncoder().encode(library)
    let decoded = try JSONDecoder().decode(StudioLibrary.self, from: encoded)
    try expect(decoded.voices.first?.cachedFile == voice.cachedFile)
    try expect(decoded.takes.first?.cachedVoice == voice.cachedFile)
    var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    var oldVoices = old["voices"] as! [[String: Any]]
    oldVoices[0].removeValue(forKey: "cachedFile"); oldVoices[0]["files"] = ["Voices/old/reference.wav"]; old["voices"] = oldVoices
    var oldTakes = old["takes"] as! [[String: Any]]
    oldTakes[0].removeValue(forKey: "cachedVoice"); oldTakes[0]["references"] = ["Voices/old/reference.wav"]; old["takes"] = oldTakes
    old["schemaVersion"] = 1
    let oldURL = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceStudio-old-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: oldURL) }
    try JSONSerialization.data(withJSONObject: old).write(to: oldURL)
    let migrated = try LibraryFile.load(from: oldURL)
    try expect(migrated.schemaVersion == 3)
    try expect(migrated.voices.first?.cachedFile == nil)
    try expect(migrated.takes.first?.cachedVoice == nil)
    try expect(migrated.voices.first?.name == voice.name)
    try expect(migrated.voices.first?.files == ["Voices/old/reference.wav"])
    try expect(migrated.takes.first?.references == ["Voices/old/reference.wav"])
    try expect(migrated.takes.first?.id == library.takes.first?.id)
}

}
