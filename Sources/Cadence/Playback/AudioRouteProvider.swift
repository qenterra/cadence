import CoreAudio
import Foundation

typealias AudioRouteChangeHandler =
    @MainActor @Sendable (AudioRouteSnapshot) -> Void

@MainActor
protocol AudioRouteProviding: AnyObject {
    func currentRoute() -> AudioRouteSnapshot
    func startMonitoring(_ handler: @escaping AudioRouteChangeHandler)
    func stopMonitoring()
}

@MainActor
final class StaticAudioRouteProvider: AudioRouteProviding {
    private var route: AudioRouteSnapshot
    private var changeHandler: AudioRouteChangeHandler?
    private(set) var monitoringStartCount = 0
    private(set) var monitoringStopCount = 0

    init(route: AudioRouteSnapshot = .unknown) {
        self.route = route
    }

    func currentRoute() -> AudioRouteSnapshot {
        route
    }

    func startMonitoring(
        _ handler: @escaping AudioRouteChangeHandler
    ) {
        if changeHandler == nil {
            monitoringStartCount += 1
        }
        changeHandler = handler
    }

    func stopMonitoring() {
        if changeHandler != nil {
            monitoringStopCount += 1
        }
        changeHandler = nil
    }

    func emit(_ route: AudioRouteSnapshot) {
        self.route = route
        changeHandler?(route)
    }
}

@MainActor
final class SystemAudioRouteProvider: AudioRouteProviding {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue.main
    private var changeHandler: AudioRouteChangeHandler?
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func currentRoute() -> AudioRouteSnapshot {
        guard let deviceID = defaultOutputDeviceID() else {
            return .unknown
        }
        return AudioRouteSnapshot(
            name: deviceName(deviceID) ?? "System Output",
            transport: transportKind(deviceID)
        )
    }

    func startMonitoring(
        _ handler: @escaping AudioRouteChangeHandler
    ) {
        changeHandler = handler
        guard listenerBlock == nil else {
            return
        }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                changeHandler?(currentRoute())
            }
        }
        var address = defaultOutputPropertyAddress
        let status = AudioObjectAddPropertyListenerBlock(
            systemObjectID,
            &address,
            listenerQueue,
            listener
        )
        guard status == noErr else {
            changeHandler = nil
            return
        }
        listenerBlock = listener
    }

    func stopMonitoring() {
        defer {
            listenerBlock = nil
            changeHandler = nil
        }
        guard let listenerBlock else {
            return
        }
        var address = defaultOutputPropertyAddress
        AudioObjectRemovePropertyListenerBlock(
            systemObjectID,
            &address,
            listenerQueue,
            listenerBlock
        )
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = defaultOutputPropertyAddress
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private func deviceName(
        _ deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        return status == noErr ? name as String : nil
    }

    private func transportKind(
        _ deviceID: AudioDeviceID
    ) -> AudioTransportKind {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &transport
        )
        guard status == noErr else {
            return .unknown
        }

        return switch transport {
        case kAudioDeviceTransportTypeAirPlay:
            .airPlay
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            .bluetooth
        case kAudioDeviceTransportTypeBuiltIn:
            .builtIn
        case kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeUSB:
            .wired
        default:
            .unknown
        }
    }

    private var defaultOutputPropertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
