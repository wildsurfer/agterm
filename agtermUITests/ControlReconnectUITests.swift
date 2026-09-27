import XCTest

@MainActor
final class ControlReconnectUITests: ControlAPITestCase {
    // a ui-test pane is local, so the refusals and the omitted field are what is reachable here.
    func testSessionReconnectRefusesALocalPane() throws {
        let sessionID = try activeSessionID()
        let refusal = "pane is not attached from another Mac"
        for pane in ["", #","args":{"pane":"split"}"#, #","args":{"pane":"scratch"}"#] {
            let reply = try sendCommand(#"{"cmd":"session.reconnect","target":"\#(sessionID)"\#(pane)}"#)
            XCTAssertEqual(reply["ok"] as? Bool, false)
            XCTAssertEqual(reply["error"] as? String, refusal, "\(reply)")
        }
        let invalid = try sendCommand(#"{"cmd":"session.reconnect","target":"\#(sessionID)","args":{"pane":"middle"}}"#)
        XCTAssertEqual(invalid["error"] as? String, "invalid pane: middle", "\(invalid)")

        let surfaces = try XCTUnwrap(try sessionNode(id: sessionID)["surfaces"] as? [[String: Any]])
        XCTAssertTrue(surfaces.allSatisfy { $0["connection"] == nil }, "omitted, not null, for a local pane")
    }
}
