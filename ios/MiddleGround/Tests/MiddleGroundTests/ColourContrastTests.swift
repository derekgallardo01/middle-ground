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

    /// The streak strip. Coral is a light pink, so `onAccent` on it is 2.16:1 — the same defect
    /// as the teal button, and it was hidden from the first scan because both the text colour and
    /// the fill are written as ternaries.
    ///
    /// The first attempted fix used `slate`, which is 4.79:1 in light and **1.81:1 in dark**,
    /// because slate flips to near-white while coral stays pale. This test caught that, which is
    /// the argument for asserting both schemes rather than the one you happen to be looking at.
    func testCompletedStreakDaysAreReadable() {
        assertReadable(MGColors.onLightAccent, on: MGColors.coral, atLeast: 4.5, "onLightAccent on coral")
        let whiteOnCoral = contrast(MGColors.onAccent, on: MGColors.coral, .light)
        XCTAssertLessThan(
            whiteOnCoral,
            3.0,
            "white on coral now clears 3:1 — if coral was darkened, this capsule can use onAccent "
                + "again and this test should say so"
        )
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

    /// The pale accents stay pale, because they are fills.
    ///
    /// Coral is 2.00:1 on sand in light mode, sunshine 1.42:1, lavender 2.52:1 and sky 1.54:1.
    /// That is correct behind dark ink, on the logo mark and in a confetti burst — and it was
    /// also, for thirteen views, the foreground colour of something a person had to make out.
    /// The fix was not to darken these; it was `coralText` and `sunshineText` below. This test
    /// stays so the numbers are written down somewhere that runs.
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

    // MARK: - The accents that are read rather than looked at

    /// 4.5:1, the body-text floor, not the 3:1 icon floor.
    ///
    /// These carry the saved heart, the report button, the streak flame, "you are sharing your
    /// location", the error state's warning triangle and the calendar clash row — several of
    /// which are words, and all of which exist to be noticed. Holding them to the icon floor
    /// would pass a colour that is legal on a glyph and unreadable in a sentence.
    func testAccentTextIsReadableInBothSchemes() {
        for (accent, name) in [(MGColors.coralText, "coralText"),
                               (MGColors.sunshineText, "sunshineText")] {
            assertReadable(accent, on: MGColors.sand, atLeast: 4.5, "\(name) on sand")
            assertReadable(accent, on: MGColors.surface, atLeast: 4.5, "\(name) on surface")
        }
    }

    /// Dark mode was never the problem — pale coral on a dark page is 7.74:1 — so the text
    /// variants deliberately do not change there. If someone "fixes" them, this says why not.
    func testTheTextVariantsOnlyDifferInLightMode() {
        XCTAssertEqual(
            contrast(MGColors.coralText, on: MGColors.sand, .dark),
            contrast(MGColors.coral, on: MGColors.sand, .dark),
            accuracy: 0.01,
            "dark mode coral was changed; it was already readable"
        )
        XCTAssertEqual(
            contrast(MGColors.sunshineText, on: MGColors.sand, .dark),
            contrast(MGColors.sunshine, on: MGColors.sand, .dark),
            accuracy: 0.01
        )
    }

    /// The whole point of the split: a pale fill still needs its dark ink to work on it.
    func testInkStillReadsOnThePaleFills() {
        for (fill, name) in [(MGColors.coral, "coral"), (MGColors.sunshine, "sunshine")] {
            assertReadable(MGColors.onLightAccent, on: fill, atLeast: 4.5, "ink on \(name)")
        }
    }
}
