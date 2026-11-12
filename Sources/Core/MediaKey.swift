import Foundation

/// Special-function keys delivered as `NX_SYSDEFINED` events (type 14, subtype 8).
/// Raw values are the key codes from `IOKit/hidsystem/ev_keymap.h`.
enum MediaKey: Int, Equatable, Hashable, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
    case fast = 19
    case rewind = 20
    case illuminationUp = 21
    case illuminationDown = 22
    case illuminationToggle = 23
}

/// The modifier keys that take part in routing. Caps lock and fn are
/// deliberately left out: they must never change what a media key does.
struct KeyModifiers: OptionSet, Equatable, Hashable, Sendable {
    let rawValue: Int

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let control = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// One decoded media key event.
struct MediaKeyEvent: Equatable, Sendable {
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: the only subtype that carries media keys.
    static let auxControlButtonsSubtype = 8

    private static let keyStateDown = 0x0A
    private static let keyStateUp = 0x0B

    var key: MediaKey
    var isDown: Bool
    var isRepeat: Bool
    var modifiers: KeyModifiers

    init(key: MediaKey, isDown: Bool, isRepeat: Bool = false, modifiers: KeyModifiers = []) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.modifiers = modifiers
    }

    /// Decodes the `subtype` and `data1` of a system-defined event.
    ///
    ///     keyCode  = (data1 & 0xFFFF0000) >> 16
    ///     keyFlags =  data1 & 0x0000FFFF
    ///     state    = (keyFlags & 0xFF00) >> 8      0x0A down, 0x0B up
    ///     repeat   =  keyFlags & 0x1
    ///
    /// Returns nil for anything that is not a known key going down or up, so
    /// the caller passes the event through untouched.
    init?(subtype: Int, data1: Int, modifiers: KeyModifiers) {
        guard subtype == Self.auxControlButtonsSubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: keyCode),
              keyState == Self.keyStateDown || keyState == Self.keyStateUp
        else { return nil }
        self.key = key
        self.isDown = keyState == Self.keyStateDown
        self.isRepeat = (keyFlags & 0x1) == 1
        self.modifiers = modifiers
    }
}
