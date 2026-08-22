import Foundation
import Network
@testable import BongoKit

/// These bind real sockets rather than mocking `NWListener`.
///
/// The bug they guard against lived entirely in the gap between what the API
/// looks like it does and what it does — `start` returning before the bind lands.
/// A mock would have been written against the same wrong belief and passed.

/// Takes a port and holds it, so the fallback has something to fall back from.
@MainActor
private func occupy(_ port: UInt16) async -> NWListener? {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
    parameters.allowLocalEndpointReuse = false
    guard let listener = try? NWListener(using: parameters) else { return nil }
    listener.newConnectionHandler = { $0.cancel() }

    return await withCheckedContinuation { continuation in
        let settle: @Sendable (NWListener?) -> Void = { result in
            listener.stateUpdateHandler = { _ in }
            continuation.resume(returning: result)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: settle(listener)
            case .failed, .waiting: settle(nil)
            default: break
            }
        }
        listener.start(queue: .global())
    }
}

/// Waits for the socket to actually close. `cancel` alone is a request, and the
/// next test in line rebinds the same port — returning early makes that a race.
@MainActor
private func close(_ listener: NWListener) async {
    await withCheckedContinuation { continuation in
        listener.stateUpdateHandler = { state in
            if case .cancelled = state { continuation.resume() }
        }
        listener.cancel()
    }
}

/// A range of this suite's own. Reusing HookTransport.ports would make the result
/// depend on whether a real BongoTokenCat happens to be running on this machine —
/// which it was, the first time these ran.
private let testPorts: [UInt16] = [41730, 41731, 41732, 41733, 41734]

@MainActor
func runHookServerTests() async {
    await asyncSuite("Hook server") {

        await asyncTest("takes the first port when nothing holds it") {
            let server = HookServer { _ in }
            guard let bound = await server.bindFirstFreePort(in: testPorts) else {
                expect(false, "no port in the range could be bound")
                return
            }
            expectEqual(bound.port, testPorts[0])
            await close(bound.listener)
        }

        await asyncTest("steps past a port another process is holding") {
            guard let holder = await occupy(testPorts[0]) else {
                expect(false, "could not take \(testPorts[0]) to set the test up")
                return
            }
            let server = HookServer { _ in }
            guard let bound = await server.bindFirstFreePort(in: testPorts) else {
                expect(false, "fell through every port in the range")
                await close(holder)
                return
            }
            expectEqual(bound.port, testPorts[1],
                        "the fallback loop was dead code until the bind was awaited")
            await close(bound.listener)
            await close(holder)
        }

        await asyncTest("gives up rather than reporting a port it never bound") {
            var holders: [NWListener] = []
            for port in testPorts {
                guard let holder = await occupy(port) else { break }
                holders.append(holder)
            }
            guard holders.count == testPorts.count else {
                expect(false, "could not take the whole range to set the test up")
                for holder in holders { await close(holder) }
                return
            }
            let server = HookServer { _ in }
            let bound = await server.bindFirstFreePort(in: testPorts)
            expect(bound == nil, "every port was taken, so there was nothing to return")
            if let bound { await close(bound.listener) }
            for holder in holders { await close(holder) }
        }
    }
}
