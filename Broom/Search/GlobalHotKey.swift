import AppKit
import Carbon.HIToolbox
import os

/// A keyboard shortcut that works while another app is in front. Carbon's hot-key API is used because it needs no
/// Accessibility permission, which watching all key presses would.
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Registers ⌥⌘B. `action` runs on the main actor each time it is pressed.
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handler)

        let id = EventHotKeyID(signature: OSType(0x4252_4F4D), id: 1) // 'BROM'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            Logger(subsystem: "app.broom", category: "search").error("Could not register the search shortcut: \(status)")
        }
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
