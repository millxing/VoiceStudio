import AppKit
import SwiftUI

/// Gives the timeline a native responder for editing commands after a mouse interaction.
/// Text fields take first responder normally, so their editing shortcuts stay local to them.
struct TimelineKeyboard: NSViewRepresentable {
    let model: AppModel
    let focusRequest: UUID?

    func makeNSView(context: Context) -> TimelineKeyView { TimelineKeyView() }
    func updateNSView(_ view: TimelineKeyView, context: Context) {
        view.model = model
        guard let focusRequest, view.focusRequest != focusRequest else { return }
        view.focusRequest = focusRequest
        DispatchQueue.main.async { [weak view] in
            guard let view, view.focusRequest == focusRequest else { return }
            view.window?.makeFirstResponder(view)
        }
    }
}

final class TimelineKeyView: NSView, NSUserInterfaceValidations {
    weak var model: AppModel?
    var focusRequest: UUID?
    var pasteboard = NSPasteboard.general
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 51 || event.keyCode == 117 {
                model.deleteClip(ripple: event.modifierFlags.contains(.shift), undo: undoManager)
                return
            }
            if event.keyCode == 49 { model.toggleTimelinePlayback(); return }
        }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": copy(nil); return true
        case "x": cut(nil); return true
        case "v": paste(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    @objc func copy(_ sender: Any?) {
        guard let clip = model?.clip, let data = try? JSONEncoder().encode(clip) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .init(AppModel.clipPasteboardType))
    }
    @objc func cut(_ sender: Any?) {
        guard model?.clip != nil else { return }
        copy(sender)
        model?.deleteClip(ripple: false, undo: undoManager)
    }
    @objc func paste(_ sender: Any?) {
        guard let data = pasteboard.data(forType: .init(AppModel.clipPasteboardType)) else { return }
        model?.pasteClip(data, undo: undoManager)
    }
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)): model?.clip != nil
        case #selector(paste(_:)): pasteboard.availableType(from: [.init(AppModel.clipPasteboardType)]) != nil
        default: true
        }
    }
}
