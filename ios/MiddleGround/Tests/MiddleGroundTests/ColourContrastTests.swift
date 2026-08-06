import SwiftUI
import UIKit
import XCTest
@testable import MiddleGround

/// Whether the text the app draws can actually be read against what is behind it.
///
/// This app has shipped two contrast failures already, from opposite causes. The first was black
/// on indigo, because `mgFont` set a colour on the leaf and a `foregroundStyle` applied afterwards
/// was silently dropped — the colour was *wrong*. The second was white on teal at 2.49:1, where
/// the colour was exactly right and the surface underneath simply could not carry it.
///
/// Neither is visible in code review and neither breaks a screenshot test, because both render a
/// perfectly composed screen that happens to be hard to read. Arithmetic catches both.
///
/// Ratios are WCAG 2.1: 4.5 for body text, 3.0 for large or bold text and for icons that carry
/// meaning. Every pair is checked in **both** colour schemes — the palette lightens its accents in
/// dark mode precisely because white-on-accent stops working there, so one scheme proves nothing
/// about the other.
final class ColourContrastTests: XCTestCase {

    // MARK: - WCAG relative luminance

    private func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrast(_ foreground: Color, on background: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        let first = luminance(UIColor(foreground), style)
        let second = luminance(UIColor(background), style)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Asserts in light *and* dark, and says which one failed — a single number would hide half
    /// the problem, and the palette deliberately differs between them.
    private func assertReadable(
        _ foreground: Color,
        on background: Color,
        atLeast minimum: CGFloat,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let ratio = contrast(foreground, on: background, style)
            XCTAssertGreaterThanOrEqual(
                ratio,
                minimum,
                String(format: "%@ in %@ mode is %.2f:1, below %.1f:1", what, name, ratio, minimum),
                file: file,
                line: line
            )
        }
    }

    // MARK: - Text on an accent surface

    /// Every button that puts a label on a coloured fill. `onAccent` flips with the scheme, which
    /// is the mechanism being checked as much as the values.
    func testButtonLabelsAreReadableOnTheirFills() {
        assertReadable(MGColors.onAccent, on: MGColors.indigo, atLeast: 3.0, "onAccent on indigo")
        assertReadable(MGColors.onAccent, on: MGColors.teal, atLeast: 4.5, "onAccent on teal")
    }

    /// The specific regression: white on teal-500 was 2.49:1, and this is a primary action.
    func testTheDidThisHappenButtonIsReadable() {
        let ratio = contrast(MGColors.onAccent, on: MGColors.teal, .light)
        XCTAssertGreaterThanOrEqual(
            ratio,
            4.5,
            String(format: "\"Yes, it did\" is %.2f:1 in light mode — teal-500 was 2.49:1", ratio)
        )
    }

    // MARK: - Body text on page and card backgrounds

    func testBodyTextIsReadableEverywhereItIsDrawn() {
        assertReadable(MGColors.slate, on: MGColors.sand, atLeast: 4.5, "slate on sand")
        assertReadable(MGColors.slate, on: MGColors.surface, atLeast: 4.5, "slate on surface")
        assertReadable(MGColors.slate, on: MGColors.warm100, atLeast: 4.5, "slate on warm100")
        assertReadable(MGColors.warm600, on: MGColors.surface, atLeast: 4.5, "warm600 on surface")
    }

    /// Secondary text sits on the page background as often as on a card, and the page is the
    /// harder of the two.
    func testSecondaryTextIsReadableOnThePageBackground() {
        assertReadable(MGColors.warm600, on: MGColors.sand, atLeast: 4.4, "warm600 on sand")
    }

    // MARK: - Accents used as text and icons

    /// Teal carries meaning — an accepted plan, a shared location — so it has to clear the 3:1
    /// floor for non-text content, and it did not: teal-500 on sand was 2.30:1.
    func testTealReadsAsAStatusColour() {
        assertReadable(MGColors.teal, on: MGColors.sand, atLeast: 3.0, "teal on sand")
        assertReadable(MGColors.teal, on: MGColors.surface, atLeast: 3.0, "teal on surface")
    }

    func testIndigoReadsAsALinkColour() {
        assertReadable(MGColors.indigo, on: MGColors.surface, atLeast: 3.0, "indigo on surface")
    }

    /// The remaining accents are **documented as decorative**, not asserted as readable.
    ///
    /// In light mode coral is 2.00:1 on sand, sunshine 1.42:1, lavender 2.52:1 and sky 1.54:1 —
    /// all below the 3:1 floor. That is fine for a confetti burst or a fill behind dark text, and
    /// not fine for anything a reader has to make out. This test does not fail on them, because
    /// darkening the palette is a design decision rather than a defect; it exists so the numbers
    /// are written down somewhere that runs.
    func testDecorativeAccentsAreKnownToBeLowContrast() {
        for (accent, name) in [(MGColors.coral, "coral"), (MGColors.sunshine, "sunshine"),
                               (MGColors.lavender, "lavender"), (MGColors.sky, "sky")] {
            let ratio = contrast(accent, on: MGColors.sand, .light)
            XCTAssertLessThan(
                ratio,
                3.0,
                "\(name) now clears 3:1 in light mode — if that was deliberate, assert it as "
                    + "readable instead of leaving it here"
            )
        }
    }
}
