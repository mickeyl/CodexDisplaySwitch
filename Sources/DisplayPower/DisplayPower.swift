@preconcurrency import AppleSiliconDDC
import Foundation

public enum DisplayPower {
    public enum State: String, Sendable {
        case on
        case off
        case unknown
    }

    public struct Status: Sendable {
        public let name: String
        public let state: State
    }

    public struct Result: Sendable {
        public let attempted: Int
        public let failures: [String]

        public var succeeded: Bool { attempted > 0 && failures.isEmpty }
    }

    private static let powerVCP: UInt8 = 0xD6
    private static let onValue: UInt16 = 0x01
    private static let offValue: UInt16 = 0x04

    public static func statuses() -> [Status] {
        connectedDisplays().map { display in
            let value = AppleSiliconDDC.read(service: display.service, command: powerVCP)?.current
            let state: State = switch value {
                case onValue: .on
                case offValue: .off
                default: .unknown
            }
            return Status(name: name(of: display), state: state)
        }
    }

    public static func turnOff() -> Result {
        let displays = connectedDisplays()
        guard !displays.isEmpty else {
            return Result(attempted: 0, failures: ["No external DDC displays found."])
        }

        // Probe every display before changing any of them. An unknown DDC route stays lit.
        var supported: [AppleSiliconDDC.IOregService] = []
        var failures: [String] = []
        for display in displays {
            guard AppleSiliconDDC.read(service: display.service, command: powerVCP)?.current == onValue else {
                failures.append("\(name(of: display)): power control unavailable")
                continue
            }
            supported.append(display)
        }

        for display in supported {
            guard AppleSiliconDDC.write(service: display.service, command: powerVCP, value: offValue) else {
                failures.append("\(name(of: display)): power-off command failed")
                continue
            }
        }
        return Result(attempted: supported.count, failures: failures)
    }

    public static func turnOn() -> Result {
        let displays = connectedDisplays()
        guard !displays.isEmpty else {
            return Result(attempted: 0, failures: ["No external DDC displays found."])
        }

        // Send all wake commands first, so one slow monitor cannot delay the others.
        for display in displays {
            _ = AppleSiliconDDC.write(service: display.service, command: powerVCP, value: onValue)
        }

        var pending = Set(displays.indices)
        for second in 1...12 {
            Thread.sleep(forTimeInterval: 1)
            for index in pending {
                guard AppleSiliconDDC.read(service: displays[index].service, command: powerVCP)?.current == onValue else {
                    continue
                }
                pending.remove(index)
            }
            guard !pending.isEmpty else { break }
            if second == 3 || second == 7 {
                for index in pending {
                    _ = AppleSiliconDDC.write(service: displays[index].service, command: powerVCP, value: onValue)
                }
            }
        }
        let failures = pending.sorted().map { "\(name(of: displays[$0])): wake could not be verified" }
        return Result(attempted: displays.count, failures: failures)
    }

    private static func connectedDisplays() -> [AppleSiliconDDC.IOregService] {
        var seenLocations = Set<String>()
        return AppleSiliconDDC.getIoregServicesForMatching().filter { display in
            guard display.location == "External", display.service != nil,
                  !display.ioDisplayLocation.isEmpty else { return false }
            guard !display.edidUUID.isEmpty || !display.manufacturerID.isEmpty ||
                    !display.transportUpstream.isEmpty || !display.transportDownstream.isEmpty else {
                return false
            }
            return seenLocations.insert(display.ioDisplayLocation).inserted
        }
    }

    private static func name(of display: AppleSiliconDDC.IOregService) -> String {
        let product = display.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return product.isEmpty ? "External display" : product
    }
}
