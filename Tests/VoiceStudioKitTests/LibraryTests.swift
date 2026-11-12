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
    try testImports(); try testSnapshotsAndRecovery(); try testCorruptLibrary(); try testCachedVoiceCompatibility(); try testTimeline(); try testScriptNamesAndDates()
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

static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
static func testTimeline() throws {
    let a = UUID(), b = UUID()
    var t = Timeline()
    let first = t.add(takeID: a, duration: 4, track: 0)
    let second = t.add(takeID: b, duration: 2, track: 0)
    try expect(near(second.start, 4))                        // appends after the track's last clip
    try expect(near(t.duration, 6))
    t.add(takeID: b, duration: 2, track: 9, at: 1)            // track clamps to the last track
    try expect(t.clips.last?.track == Timeline.trackCount - 1)
    // Split at 1.5 s: left keeps 0–1.5, right plays from 1.5 in the source.
    let right = t.split(first.id, at: 1.5)!
    let r = t.clips.first { $0.id == right }!
    try expect(near(r.start, 1.5) && near(r.inPoint, 1.5) && near(r.outPoint, 4))
    try expect(near(t.clips.first { $0.id == first.id }!.outPoint, 1.5))
    try expect(t.split(first.id, at: 0.01) == nil)            // too close to the edge
    // Trim the right half's start to 2 s: audio stays aligned.
    t.trimStart(right, to: 2)
    let trimmed = t.clips.first { $0.id == right }!
    try expect(near(trimmed.start, 2) && near(trimmed.inPoint, 2))
    t.trimStart(right, to: -5)                                // cannot reach before the source start
    try expect(near(t.clips.first { $0.id == right }!.inPoint, 0))
    t.trimEnd(right, to: 100, sourceDuration: 4)              // cannot pass the source end
    try expect(near(t.clips.first { $0.id == right }!.outPoint, 4))
    // Ripple delete closes the gap on that track only.
    var ripple = Timeline()
    let x = ripple.add(takeID: a, duration: 3, track: 1)
    let y = ripple.add(takeID: b, duration: 2, track: 1)
    let other = ripple.add(takeID: b, duration: 2, track: 2, at: 5)
    ripple.rippleRemove([x.id])
    try expect(near(ripple.clips.first { $0.id == y.id }!.start, 0))
    try expect(near(ripple.clips.first { $0.id == other.id }!.start, 5))
    // Snapping meets the end of the neighbouring clip.
    try expect(near(ripple.snap(start: 2.07, length: 1, excluding: nil, tolerance: 0.1), 2))
    try expect(near(ripple.snap(start: 2.5, length: 1, excluding: nil, tolerance: 0.1), 2.5))
    // Mixing: two tracks sum with gain; muted tracks are silent; peaks are limited.
    var mixT = Timeline()
    mixT.add(takeID: a, duration: 1, track: 0, at: 0)
    mixT.add(takeID: b, duration: 1, track: 1, at: 0)
    mixT.tracks[1].volume = 0.5
    let src: [UUID: [Float]] = [a: Array(repeating: 0.4, count: 100), b: Array(repeating: 0.4, count: 100)]
    let mixed = TimelineMixer.mix(mixT, sampleRate: 100, fade: 0) { src[$0] }
    try expect(mixed.count == 100 && abs(mixed[50] - 0.6) < 1e-6)
    mixT.tracks[1].muted = true
    try expect(abs(TimelineMixer.mix(mixT, sampleRate: 100, fade: 0) { src[$0] }[50] - 0.4) < 1e-6)
    mixT.tracks[1].muted = false; mixT.tracks[1].volume = 2
    try expect(TimelineMixer.mix(mixT, sampleRate: 100, fade: 0) { src[$0] }.allSatisfy { abs($0) <= 0.99 + 1e-6 })
    // Older libraries without a timeline still load.
    var lib = StudioLibrary(); lib.timeline = t
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lib)) as! [String: Any]
    try expect(try JSONDecoder().decode(StudioLibrary.self, from: JSONEncoder().encode(lib)).timeline == t)
    json.removeValue(forKey: "timeline")
    try expect(try JSONDecoder().decode(StudioLibrary.self, from: JSONSerialization.data(withJSONObject: json)).timeline.isEmpty)
}

static func testScriptNamesAndDates() throws {
    var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 2; parts.hour = 23
    let date = Calendar(identifier: .gregorian).date(from: parts)!
    try expect(ScriptDocument.defaultTitle(at: date, number: 4524) == "20261102_4524")
    try expect(ScriptDocument.defaultTitle(at: date, number: 7) == "20261102_0007")
    let random = ScriptDocument.defaultTitle()
    try expect(random.count == 13 && random.dropFirst(8).first == "_" && Int(random.suffix(4)).map { (1000...9999).contains($0) } == true)
    let script = ScriptDocument(title: "Chapter", text: "Words.", createdAt: date)
    try expect(script.modifiedAt == script.createdAt)
    let copy = script.duplicate()
    try expect(copy.id != script.id && copy.title == "Chapter copy" && copy.text == "Words." && copy.createdAt > date && copy.modifiedAt == copy.createdAt)
    // Scripts saved before the edited time existed load with their creation time.
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(script)) as! [String: Any]
    json.removeValue(forKey: "modifiedAt")
    let old = try JSONDecoder().decode(ScriptDocument.self, from: JSONSerialization.data(withJSONObject: json))
    try expect(old.modifiedAt == old.createdAt && old.id == script.id)
    try expect(try JSONDecoder().decode(ScriptDocument.self, from: JSONEncoder().encode(script)) == script)
}

}
