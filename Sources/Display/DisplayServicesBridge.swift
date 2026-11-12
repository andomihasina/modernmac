import CoreGraphics
import Darwin

/// The only place ModernMac touches private API.
///
/// DisplayServices is loaded at runtime with `dlopen`/`dlsym`; the framework is
/// never linked. Every symbol is optional, so a macOS release that drops one
/// degrades to "brightness unavailable" instead of failing to launch.
enum DisplayServicesBridge {
    static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private typealias GetBrightnessFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightnessFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias BrightnessChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(frameworkPath, RTLD_LAZY)

    private static let getBrightnessFn =
        symbol("DisplayServicesGetBrightness", as: GetBrightnessFn.self)
    private static let setBrightnessFn =
        symbol("DisplayServicesSetBrightness", as: SetBrightnessFn.self)
    private static let canChangeBrightnessFn =
        symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightnessFn.self)
    private static let brightnessChangedFn =
        symbol("DisplayServicesBrightnessChanged", as: BrightnessChangedFn.self)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static var isFrameworkLoaded: Bool { handle != nil }

    /// Which symbols resolved on this system, for diagnostics.
    static var symbolReport: [(name: String, isResolved: Bool)] {
        [
            ("DisplayServicesGetBrightness", getBrightnessFn != nil),
            ("DisplayServicesSetBrightness", setBrightnessFn != nil),
            ("DisplayServicesCanChangeBrightness", canChangeBrightnessFn != nil),
            ("DisplayServicesBrightnessChanged", brightnessChangedFn != nil),
        ]
    }

    /// `nil` when the symbol is missing.
    static func canChangeBrightness(_ display: CGDirectDisplayID) -> Bool? {
        canChangeBrightnessFn.map { $0(display) }
    }

    /// Returns the raw status (0 = success), or `nil` when the symbol is missing.
    static func getBrightness(_ display: CGDirectDisplayID, into value: inout Float) -> Int32? {
        getBrightnessFn.map { $0(display, &value) }
    }

    /// `value` is 0…1. Returns the raw status (0 = success), or `nil` when the symbol is missing.
    static func setBrightness(_ display: CGDirectDisplayID, to value: Float) -> Int32? {
        setBrightnessFn.map { $0(display, value) }
    }

    /// Tells the system the brightness changed so System Settings stays in sync.
    /// Returns false when the symbol is missing.
    @discardableResult
    static func notifyBrightnessChanged(_ display: CGDirectDisplayID, to value: Float) -> Bool {
        guard let brightnessChangedFn else { return false }
        brightnessChangedFn(display, Double(value))
        return true
    }
}
