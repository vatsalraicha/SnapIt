import Cocoa

/// Text annotation inline editor
class TextToolEditor {
    /// Create an inline text editing field at the given position in the canvas
    static func beginEditing(in view: NSView, at point: NSPoint, color: NSColor,
                             fontSize: CGFloat = 16,
                             completion: @escaping (String?) -> Void) {
        let textField = NSTextField(frame: NSRect(x: point.x, y: point.y - fontSize, width: 300, height: fontSize + 8))
        textField.font = .systemFont(ofSize: fontSize)
        textField.textColor = color
        textField.backgroundColor = NSColor.white.withAlphaComponent(0.8)
        textField.isBezeled = false
        textField.focusRingType = .none
        textField.wantsLayer = true
        textField.layer?.cornerRadius = 2

        view.addSubview(textField)
        view.window?.makeFirstResponder(textField)

        // Use a delegate to handle completion
        let delegate = TextFieldDelegate(completion: { text in
            textField.removeFromSuperview()
            completion(text)
        })
        textField.delegate = delegate
        // Keep delegate alive
        objc_setAssociatedObject(textField, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

private class TextFieldDelegate: NSObject, NSTextFieldDelegate {
    let completion: (String?) -> Void

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            completion(control.stringValue.isEmpty ? nil : control.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            completion(nil)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // TAB inserts hex color under cursor
            // This would need access to the canvas to get pixel color
            return false
        }
        return false
    }
}
