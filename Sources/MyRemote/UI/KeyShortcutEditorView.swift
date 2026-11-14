import SwiftUI
import AppKit
import CoreGraphics

/// 录制任意 macOS 键盘 keycode + 修饰键，保存为「发送键盘按键」动作。
struct KeyShortcutEditorView: View {

    let initial: KeyboardShortcut?
    let onClose: () -> Void
    let onSave: (KeyboardShortcut) -> Void

    @State private var keyCode: UInt16?
    @State private var modifiers: UInt64

    init(initial: KeyboardShortcut?,
         onClose: @escaping () -> Void,
         onSave: @escaping (KeyboardShortcut) -> Void) {
        self.initial = initial
        self.onClose = onClose
        self.onSave = onSave
        _keyCode = State(initialValue: initial?.keyCode)
        _modifiers = State(initialValue: initial?.modifiers ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(initial == nil ? localized("发送键盘按键") : localized("编辑键盘按键"))
                .font(.duo(20, .heavy))
                .foregroundStyle(Duo.eel)

            Text("在下面的框里按下任意键；支持所有 macOS keycode 和 ⌃⌥⇧⌘ 组合。")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.wolf)

            captureBox

            HStack(spacing: 8) {
                Text("修饰键")
                    .font(.duo(11, .bold))
                    .foregroundStyle(Duo.wolf)
                modifierChip("⌃", mask: .maskControl)
                modifierChip("⌥", mask: .maskAlternate)
                modifierChip("⇧", mask: .maskShift)
                modifierChip("⌘", mask: .maskCommand)
                modifierChip("fn", mask: .maskSecondaryFn)
                Spacer()
                Text(keyCode.map { "KeyCode \($0)" } ?? "KeyCode —")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Duo.hare)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("常用键")
                    .font(.duo(11, .bold))
                    .foregroundStyle(Duo.wolf)
                FlowLayout(spacing: 6) {
                    quickKey("Return", 36)
                    quickKey("Tab", 48)
                    quickKey("Space", 49)
                    quickKey("Esc", 53)
                    quickKey("←", 123)
                    quickKey("↑", 126)
                    quickKey("↓", 125)
                    quickKey("→", 124)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onClose)
                    .buttonStyle(DuoSecondaryButtonStyle())
                Button("保存") {
                    guard let keyCode else { return }
                    onSave(KeyboardShortcut(keyCode: keyCode, modifiers: modifiers))
                    onClose()
                }
                .buttonStyle(DuoPrimaryButtonStyle())
                .disabled(keyCode == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Duo.white)
    }

    private var captureBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Duo.polar)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Duo.swan,
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))

            if let keyCode {
                Text(KeyboardShortcut(keyCode: keyCode, modifiers: modifiers).displayName)
                    .font(.duo(24, .heavy))
                    .foregroundStyle(Duo.eel)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .bold))
                    Text("点击后按下任意键")
                        .font(.duo(13, .bold))
                }
                .foregroundStyle(Duo.wolf)
            }

            KeyCaptureView { code, flags in
                keyCode = code
                modifiers = flags
            }
        }
        .frame(height: 96)
        .contentShape(Rectangle())
    }

    private func modifierChip(_ title: String, mask: CGEventFlags) -> some View {
        let selected = (modifiers & mask.rawValue) != 0
        return Button {
            modifiers ^= mask.rawValue
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? Duo.white : Duo.eel)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Duo.eel : Duo.polar)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Duo.eel : Duo.swan, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func quickKey(_ title: String, _ code: UInt16) -> some View {
        Button {
            keyCode = code
        } label: {
            Text(title)
                .font(.duo(10, .bold))
                .foregroundStyle(Duo.eel)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Duo.polar))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Duo.swan, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 按键捕获

struct KeyCaptureView: NSViewRepresentable {
    var onCapture: (UInt16, UInt64) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: KeyCaptureNSView, context: Context) {
        view.onCapture = onCapture
    }
}

final class KeyCaptureNSView: NSView {

    var onCapture: ((UInt16, UInt64) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var cg: CGEventFlags = []
        if flags.contains(.control) { cg.insert(.maskControl) }
        if flags.contains(.option) { cg.insert(.maskAlternate) }
        if flags.contains(.shift) { cg.insert(.maskShift) }
        if flags.contains(.command) { cg.insert(.maskCommand) }
        if flags.contains(.function) { cg.insert(.maskSecondaryFn) }
        onCapture?(event.keyCode, cg.rawValue)
    }
}
