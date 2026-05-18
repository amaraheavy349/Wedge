import Foundation
import IOKit

/// Subscribes to lid open/closed transitions via IOKit's IOPMrootDomain.
/// Reports state as a Bool: true = lid open, false = lid closed.
///
/// `AppleClamshellState` historically returns a Bool whose semantics differ
/// across machines and macOS versions (true sometimes means open, sometimes
/// closed). To stay robust without testing on every model, we *calibrate* at
/// instantiation: whatever raw value is read while the monitor is being
/// created is the user's "lid open" reference, since the user has just
/// interacted with the menubar to enable the feature. All later raw values
/// are interpreted relative to that.
@MainActor
final class ClamshellMonitor {
    var onStateChange: ((Bool) -> Void)?

    nonisolated(unsafe) private var notificationPort: IONotificationPortRef?
    nonisolated(unsafe) private var notification: io_object_t = 0
    nonisolated(unsafe) private var rootDomain: io_service_t = 0

    private var openReferenceValue: Bool?
    private(set) var isLidOpen: Bool = true

    init() {
        start()
    }

    deinit {
        if notification != 0 { IOObjectRelease(notification) }
        if rootDomain != 0   { IOObjectRelease(rootDomain) }
        if let port = notificationPort { IONotificationPortDestroy(port) }
    }

    /// Current interpreted state (true = open).
    func currentState() -> Bool {
        interpret(readRaw())
    }

    // MARK: - Setup

    private func start() {
        rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != 0 else { return }

        // Calibrate against the value we see right now. The user just enabled
        // the feature, so the lid is definitively open at this point.
        let raw = readRaw()
        openReferenceValue = raw
        isLidOpen = true

        let port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        notificationPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            Task { @MainActor in
                let monitor = Unmanaged<ClamshellMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let newState = monitor.interpret(monitor.readRaw())
                if newState != monitor.isLidOpen {
                    monitor.isLidOpen = newState
                    monitor.onStateChange?(newState)
                }
            }
        }

        IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            callback,
            selfPtr,
            &notification
        )
    }

    // MARK: - State

    private func interpret(_ raw: Bool) -> Bool {
        guard let reference = openReferenceValue else { return true }
        return raw == reference
    }

    private func readRaw() -> Bool {
        guard rootDomain != 0 else { return true }
        let prop = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let value = prop?.takeRetainedValue() as? NSNumber else { return true }
        return value.boolValue
    }
}
