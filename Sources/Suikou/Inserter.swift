import AppKit

/// Writes text at the cursor of the frontmost app: put it on the pasteboard, synthesize ⌘V, then restore the old pasteboard.
enum Inserter {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static let restoreDelayRange: ClosedRange<Double> = 0.3...3.0
    static func clampDelay(_ v: Double) -> Double { min(max(v, restoreDelayRange.lowerBound), restoreDelayRange.upperBound) }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func snapshot(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type] = data } }
            return dict
        }
    }

    static func restore(_ saved: Snapshot, to pb: NSPasteboard) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.writeObjects(saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        })
    }

    static func insert(_ text: String, restoreClipboard: Bool = true, delay: Double = Settings.shared.clipboardRestoreDelay) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        // Ask clipboard managers not to record our temporary write.
        if restoreClipboard { pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) }
        let ourChange = pb.changeCount

        press(9) // V
        guard restoreClipboard else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + clampDelay(delay)) {
            // The user copied something new in the meantime — leave it alone.
            guard pb.changeCount == ourChange else { return }
            restore(saved, to: pb)
        }
    }

    /// Fallback for apps whose Accessibility tree hides the selection (Electron, some web views):
    /// synthesize ⌘C, read what landed on the pasteboard, then put the old pasteboard back. Blocks ≤ `timeout`.
    static func copySelectionViaCommandC(timeout: TimeInterval = 0.25) -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        press(8) // C
        let deadline = Date().addingTimeInterval(timeout)
        while pb.changeCount == before && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard pb.changeCount != before else { return nil } // nothing selected (or app ignored ⌘C)
        let text = pb.string(forType: .string)
        restore(saved, to: pb)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count < 8000 else { return nil }
        return text
    }

    private static func press(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
