import AppKit
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

@MainActor
final class CustomAvatarTests: XCTestCase {
    func testCustomArtworkUsesExistingMotionAndKeepsArtworkIntact() throws {
        var profile = CustomBalanceProfile(name: "Sample avatar", currency: "CREDITS", balancePath: "/left")
        profile.avatar = try CustomBalanceAvatar(emoji: "🐦")
        CustomAvatarRegistry.shared.sync([profile])
        defer { CustomAvatarRegistry.shared.sync([]) }
        XCTAssertNotNil(AgentArtwork.original(for: profile.name))
        let form = try XCTUnwrap(BotForm.form(for: profile.name, ground: .dark))
        XCTAssertEqual(form.spec.ownEyes?.count, 0, "custom artwork keeps its own face")
        let actor = BotActor(form: form, staysBot: true, period: 3, seed: 1)
        actor.resize(side: 30, scale: 2, outline: 0)
        actor.set(BotState(look: .plain), at: 0)
        actor.play(.start, at: 0)
        _ = actor.step(to: 0, yRunsDown: true, aim: { .zero })
        let first = actor.layer.affineTransform()
        _ = actor.step(to: 0.25, yRunsDown: true, aim: { .zero })
        XCTAssertFalse(actor.layer.affineTransform() == first, "uses the live bot-motion transform")
        XCTAssertNotNil(actor.layer.contents)
    }

    func testAnimationCanBeDisabledAndCachesRefreshAfterAvatarChange() throws {
        var profile = CustomBalanceProfile(name: "Sample avatar", currency: "CREDITS", balancePath: "/left")
        profile.avatar = try CustomBalanceAvatar(emoji: "🐦")
        CustomAvatarRegistry.shared.sync([profile])
        defer { CustomAvatarRegistry.shared.sync([]) }
        let before = try XCTUnwrap(BotForm.form(for: profile.name, ground: .dark))
        let revision = CustomAvatarRegistry.shared.revision
        profile.avatar = try CustomBalanceAvatar(emoji: "🤖", animated: false)
        CustomAvatarRegistry.shared.sync([profile])
        XCTAssertTrue(CustomAvatarRegistry.shared.revision != revision)
        XCTAssertNil(BotForm.form(for: profile.name, ground: .dark))
        XCTAssertNotNil(AgentArtwork.image(for: profile.name))
        profile.avatar?.animated = true
        CustomAvatarRegistry.shared.sync([profile])
        let after = try XCTUnwrap(BotForm.form(for: profile.name, ground: .dark))
        XCTAssertFalse(before === after)
    }

    func testCustomSourcesDoNotReplaceBundledAgentArtwork() throws {
        var profile = CustomBalanceProfile(name: "Codex", currency: "USD", balancePath: "/left")
        profile.avatar = try CustomBalanceAvatar(emoji: "🐦")
        CustomAvatarRegistry.shared.sync([profile])
        defer { CustomAvatarRegistry.shared.sync([]) }
        XCTAssertTrue(CustomAvatarRegistry.shared.avatars.isEmpty)
        XCTAssertNotNil(BotForm.form(for: "Codex", ground: .dark))
    }
}
