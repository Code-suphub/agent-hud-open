import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The camera housing at a hardware notch drawn black over a light or glass look's surface (`NotchInk`): black where the
/// collapsed island is, and past its edge a fade over `NotchInk.feather` points into the surface, so the housing melts
/// into the look instead of meeting it at a line.
@MainActor
final class NotchInkTests: XCTestCase {
    private let island = CGSize(width: 200, height: 32)
    private let canvas = CGSize(width: 280, height: 90)

    /// The fade reaches 14 points past the housing: enough to soften its edge on a light surface without reading as a
    /// shadow under it.
    func testTheFadeIsFourteenPoints() {
        XCTAssertEqual(NotchInk.feather, 14)
        XCTAssertEqual(NotchInk(size: island, topRadius: 8, bottomRadius: 12).feather, NotchInk.feather)
    }

    /// Over the housing the ink is black. Past its lower edge it fades out over the feather instead of stopping at a
    /// line: grey a few points past the edge, lighter with every point further, and gone a feather and more past it.
    func testTheHousingFadesIntoTheSurfaceOverTheFeather() throws {
        let rep = try drawn(NotchInk(size: island, topRadius: NotchGeometry.collapsedTopRadius, bottomRadius: 12))
        let middle = canvas.width / 2
        XCTAssertLessThan(try level(rep, middle, island.height / 2), 0.05, "black over the housing")
        XCTAssertLessThan(try level(rep, middle, island.height - 1), 0.05, "to its very edge")

        let near = try level(rep, middle, island.height + 3)
        XCTAssertGreaterThan(near, 0.05, "past the edge the black fades, never a hard line")
        XCTAssertLessThan(near, 0.8, "and is still plainly there a few points past it")
        let past = try stride(from: 1, through: Int(NotchInk.feather), by: 1).map {
            try level(rep, middle, island.height + CGFloat($0))
        }
        XCTAssertEqual(past, past.sorted(), "lighter with every point further: \(past)")
        XCTAssertGreaterThan(try level(rep, middle, island.height + NotchInk.feather + 10), 0.95, "gone past the feather")
        XCTAssertGreaterThan(try level(rep, 4, island.height / 2), 0.9, "beside the flares, past the feather, the surface")
    }

    // MARK: Helpers

    /// The ink at the top centre of a white canvas, drawn at 2 pixels a point.
    private func drawn(_ ink: NotchInk) throws -> NSBitmapImageRep {
        let view = ZStack(alignment: .top) {
            Color.white
            ink
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    /// The level of grey at a point, from the top left in points.
    private func level(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat, file: StaticString = #filePath,
                       line: UInt = #line) throws -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / canvas.width
        let color = try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB),
                                  file: file, line: line)
        return color.redComponent
    }
}
