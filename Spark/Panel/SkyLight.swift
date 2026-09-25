import AppKit

/// Window-server background blur through the private SkyLight (CoreGraphics Services) API, as iTerm2 uses.
///
/// The window server blurs what's behind every non-transparent pixel of the window, so the blur follows the
/// panel's rounded shape as long as the panel has some fill and nothing else paints the transparent margin.
/// The functions are looked up at runtime: if a macOS release drops them, the panel is just left unblurred.
@MainActor
enum SkyLight {
    static let radiusRange: ClosedRange<Double> = 0...64

    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias BlurFunction = @convention(c) (_ connection: Int32, _ window: Int32, _ radius: Int32) -> Int32

    private static let functions: (connection: ConnectionFunction, blur: BlurFunction)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(handle, "CGSDefaultConnectionForThread"),
              let blur = dlsym(handle, "CGSSetWindowBackgroundBlurRadius")
        else { return nil }
        return (unsafeBitCast(connection, to: ConnectionFunction.self), unsafeBitCast(blur, to: BlurFunction.self))
    }()

    static var isAvailable: Bool { functions != nil }

    /// Blurs what's behind `window` by `radius` points (0 turns it off). Returns whether the call succeeded.
    @discardableResult
    static func setBackgroundBlur(radius: Int, for window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }
        let clamped = Int32(min(max(radius, Int(radiusRange.lowerBound)), Int(radiusRange.upperBound)))
        return functions.blur(functions.connection(), Int32(window.windowNumber), clamped) == 0
    }
}
