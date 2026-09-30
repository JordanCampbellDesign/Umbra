import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Private system calls, loaded at runtime with dlsym so the app builds with the public SDK.
enum Private {
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    private static let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private static func sym<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as _: T.Type) -> T? {
        guard let p = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    // MARK: DisplayServices (built-in and Apple displays)

    typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool

    static let dsGetBrightness = sym(displayServices, "DisplayServicesGetBrightness", as: GetBrightnessFn.self)
    static let dsSetBrightness = sym(displayServices, "DisplayServicesSetBrightness", as: SetBrightnessFn.self)
    static let dsCanChange = sym(displayServices, "DisplayServicesCanChangeBrightness", as: CanChangeFn.self)

    static func getBrightness(_ id: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        guard let f = dsGetBrightness, f(id, &v) == 0 else { return nil }
        return v
    }

    @discardableResult
    static func setBrightness(_ id: CGDirectDisplayID, _ v: Float) -> Bool {
        guard let f = dsSetBrightness else { return false }
        return f(id, max(0, min(1, v))) == 0
    }

    typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    static let dsRegisterBrightness = sym(displayServices, "DisplayServicesRegisterForBrightnessChangeNotifications", as: RegisterFn.self)
    private static var brightnessWatched = Set<CGDirectDisplayID>()

    /// Ask macOS to tell us when a display's brightness changes. Returns false when the call is missing or fails.
    @discardableResult
    static func watchBrightness(_ id: CGDirectDisplayID) -> Bool {
        if brightnessWatched.contains(id) { return true }
        guard let f = dsRegisterBrightness else { return false }
        let ok = f(id, nil, { _, _, _, _, _ in
            DispatchQueue.main.async { Engine.shared.brightnessChanged() }
        }) == 0
        if ok { brightnessWatched.insert(id) }
        return ok
    }

    static func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool {
        dsCanChange?(id) ?? false
    }

    // MARK: CoreBrightness (macOS auto-brightness)

    private static let brightnessClient: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("BrightnessSystemClient") as? NSObject.Type)?.init()
    }()

    /// True when macOS "Automatically adjust brightness" is on for the built-in display. Nil when macOS doesn't say.
    static func autoBrightnessEnabled() -> Bool? {
        let sel = NSSelectorFromString("copyPropertyForKey:")
        guard let c = brightnessClient, c.responds(to: sel),
              let v = c.perform(sel, with: "CBAutoBrightnessEnabled")?.takeRetainedValue() as? NSNumber else { return nil }
        return v.boolValue
    }

    static func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: SkyLight (display enable / disable for BlackOut)

    typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    static let configureEnabled = sym(skyLight, "SLSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
        ?? sym(nil, "CGSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)

    // MARK: IOAVService (DDC on Apple Silicon)

    typealias AVCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias AVReadFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias AVWriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> IOReturn

    static let avCreate = sym(ioKit, "IOAVServiceCreateWithService", as: AVCreateFn.self)
    static let avRead = sym(ioKit, "IOAVServiceReadI2C", as: AVReadFn.self)
    static let avWrite = sym(ioKit, "IOAVServiceWriteI2C", as: AVWriteFn.self)
}
