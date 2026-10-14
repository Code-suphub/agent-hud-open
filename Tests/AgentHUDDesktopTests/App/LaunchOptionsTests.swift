import XCTest
@testable import AgentHUDDesktop

/// The launch switches that decide whether this copy answers the MCP tools.
final class LaunchOptionsTests: XCTestCase {
    func testTheDemoToolsSwitchIsParsed() {
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--demo", "--demo-tools"]).demoTools)
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--demo-tools", "--demo"]).demoTools, "in either order")
        XCTAssertFalse(DesktopLaunchOptions.parse(["app", "--demo"]).demoTools)
        XCTAssertFalse(DesktopLaunchOptions.parse(["app", "--demo-tools"]).demo, "it does not turn the demo on by itself")
    }

    /// One process serves the socket. Every launch but a demo serves it, and a demo only when asked.
    func testWhoServesTheToolChannel() {
        XCTAssertTrue(DesktopLaunchOptions.parse(["app"]).servesTools)
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--show-settings"]).servesTools)
        XCTAssertFalse(DesktopLaunchOptions.parse(["app", "--demo"]).servesTools, "a demo leaves the socket to the real copy")
        XCTAssertFalse(DesktopLaunchOptions.parse(["app", "--demo-script", "showcase"]).servesTools)
        XCTAssertFalse(DesktopLaunchOptions.parse(["app", "--demo-clock", "2026-10-12T09:41"]).servesTools)
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--demo", "--demo-tools"]).servesTools)
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--demo-script", "showcase", "--demo-tools"]).servesTools)
        XCTAssertTrue(DesktopLaunchOptions.parse(["app", "--demo-tools"]).servesTools, "without a demo the switch changes nothing")
    }
}
