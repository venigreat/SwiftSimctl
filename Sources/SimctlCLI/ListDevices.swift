import ArgumentParser
import Foundation
import SimctlServerCore
import SimctlShared

struct ListDevices: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "List the simulator devices")

    mutating func run() throws {
        let output = try CommandRunner().execute(.simctlList())
        let listing = try JSONDecoder().decode(SimulatorDeviceListing.self, from: Data(output.utf8))
        print(listing.devices.map { $0.description }.sorted().joined(separator: "\n"))
    }
}
