import AppKit

/// Writes text at the cursor of the frontmost app: put it on the pasteboard, synthesize ⌘V, then restore the old pasteboard.
enum Inserter {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func insert(_ text: String, restoreClipboard: Bool = true) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type] = data } }
            return dict
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        // Ask clipboard managers not to record our temporary write.
        if restoreClipboard { pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) }
        let ourChange = pb.changeCount

        pressCommandV()
        guard restoreClipboard else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // The user copied something new in the meantime — leave it alone.
            guard pb.changeCount == ourChange else { return }
            pb.clearContents()
            guard !saved.isEmpty else { return }
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            pb.writeObjects(items)
        }
    }

    private static func pressCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticMarker)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
