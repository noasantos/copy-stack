import AppKit
import Foundation

protocol TextRunMeasuring {
    /// Locates the caret that follows the first `prefixLength` UTF-16 units of `text`, given the
    /// screen frame the whole run occupies and the width at which the run wraps.
    /// Returns a 1pt-wide rect in the same coordinate space as `runFrame`, or `nil` when the
    /// layout cannot be reproduced with confidence.
    func caretRect(prefixLength: Int, in text: String, runFrame: CGRect, wrapWidth: CGFloat) -> CGRect?
}

/// Reproduces a text run's layout with TextKit so the caret can be placed inside a run whose
/// only known geometry is its bounding frame. The font is unknown, so the size is derived from
/// the line height and the horizontal scale is calibrated against the run width.
struct TextKitRunMeasurer: TextRunMeasuring {
    static let lineHeightToFontSize: CGFloat = 1.2
    static let acceptableScale: ClosedRange<CGFloat> = 0.6...1.6

    func caretRect(prefixLength: Int, in text: String, runFrame: CGRect, wrapWidth: CGFloat) -> CGRect? {
        let length = (text as NSString).length
        guard length > 0, runFrame.height > 0, runFrame.width > 0 else {
            return nil
        }
        let prefix = min(max(prefixLength, 0), length)
        let maximumLines = min(60, max(1, Int(runFrame.height / 6)))

        for lineCount in 1...maximumLines {
            let lineHeight = runFrame.height / CGFloat(lineCount)
            let fontSize = min(max(lineHeight / Self.lineHeightToFontSize, 4), 256)
            let width = lineCount == 1 ? CGFloat.greatestFiniteMagnitude : max(wrapWidth, 1)
            let lines = Self.layoutLines(text, fontSize: fontSize, width: width)
            guard lines.count == lineCount, let widest = lines.map(\.usedWidth).max(), widest > 0 else {
                continue
            }
            let scale = runFrame.width / widest
            guard Self.acceptableScale.contains(scale) else {
                continue
            }

            let index = lines.firstIndex { prefix < NSMaxRange($0.characters) } ?? lines.count - 1
            let line = lines[index]
            let offset = line.caretOffset(at: prefix) * scale
            return CGRect(
                x: runFrame.minX + offset,
                y: runFrame.minY + CGFloat(index) * lineHeight,
                width: 1,
                height: lineHeight
            )
        }
        return nil
    }

    struct Line {
        let characters: NSRange
        let usedWidth: CGFloat
        let caretOffsets: [CGFloat]

        func caretOffset(at characterIndex: Int) -> CGFloat {
            let local = min(max(characterIndex - characters.location, 0), caretOffsets.count - 1)
            return caretOffsets[local]
        }
    }

    static func layoutLines(_ text: String, fontSize: CGFloat, width: CGFloat) -> [Line] {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let container = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        var lines: [Line] = []
        var glyphIndex = 0
        let glyphCount = manager.numberOfGlyphs
        while glyphIndex < glyphCount {
            var glyphRange = NSRange(location: 0, length: 0)
            let used = manager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            let characters = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            var offsets: [CGFloat] = []
            for character in characters.location...NSMaxRange(characters) {
                if character >= NSMaxRange(characters) {
                    offsets.append(used.width)
                } else {
                    let glyph = manager.glyphIndexForCharacter(at: character)
                    offsets.append(manager.location(forGlyphAt: glyph).x)
                }
            }
            lines.append(Line(characters: characters, usedWidth: used.width, caretOffsets: offsets))
            glyphIndex = NSMaxRange(glyphRange)
        }
        return lines
    }
}
