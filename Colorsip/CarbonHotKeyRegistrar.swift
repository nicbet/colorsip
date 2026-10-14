import Carbon.HIToolbox
import ColorsipCore

/// "CSIP": tags Colorsip's hot keys in Carbon events.
private let hotKeySignature: OSType = 0x4353_4950

/// Global hot keys through Carbon's `RegisterEventHotKey`. Unlike a CGEvent tap, it needs no
/// Accessibility permission, and with `kEventHotKeyExclusive` it fails when another app already
/// holds the shortcut.
@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    var onPress: ((ShortcutAction) -> Void)?
    private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == hotKeySignature, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { registrar.pressed(hotKeyID.id) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> Bool {
        unregister(action)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.modifiers.carbonFlags,
            EventHotKeyID(signature: hotKeySignature, id: Self.id(of: action)),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { return false }
        hotKeys[action] = ref
        return true
    }

    func unregister(_ action: ShortcutAction) {
        if let ref = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    /// Whether an enabled macOS shortcut (System Settings ▸ Keyboard ▸ Keyboard Shortcuts) uses
    /// `shortcut`. Other apps' menu shortcuts can't be detected.
    func isReservedBySystem(_ shortcut: KeyboardShortcut) -> Bool {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
            let entries = hotKeys?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return entries.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                let code = entry[kHISymbolicHotKeyCode as String] as? Int, code < Int(UInt16.max),
                let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { return false }
            return KeyboardShortcut(keyCode: UInt16(code), modifiers: .init(carbonFlags: UInt32(modifiers))) == shortcut
        }
    }

    private func pressed(_ id: UInt32) {
        guard let action = ShortcutAction.allCases.first(where: { Self.id(of: $0) == id }) else { return }
        onPress?(action)
    }

    private static func id(of action: ShortcutAction) -> UInt32 {
        UInt32(ShortcutAction.allCases.firstIndex(of: action)!)
    }
}

/// The character `keyCode` types in the current keyboard layout, for displaying shortcuts.
func keyName(for keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = data.withUnsafeBytes { bytes in
        UCKeyTranslate(
            bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), keyCode,
            UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, characters.count, &length, &characters)
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
}
