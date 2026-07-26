//
//  ChartDayDetector.swift
//  GigPilot
//
//  Works out which day a daily earnings screenshot is showing.
//
//  Uber's daily view is a trap for a text-only parser. Seven screenshots of
//  the same week are near-identical in text: each carries the same header
//  ("Jun 1 - Jun 8") and the same row of day labels. Nothing written on the
//  screen says which day you're looking at. The only signal is colour — the
//  selected bar is solid, the rest are washed out.
//
//  So this reads pixels. It finds the row of day labels via OCR, looks at the
//  chart directly above each one, and picks the column whose bars are most
//  saturated. If most columns are saturated it isn't a day view at all; that's
//  the weekly total, and saying so is what stops seven days of earnings being
//  imported on top of a week's aggregate.
//
//  Saturation rather than hue, deliberately: it survives Uber changing their
//  blue, works for Lyft's pink and DoorDash's red, and doesn't care about
//  dark mode.
//

import Foundation
import CoreGraphics

enum ChartDayDetector {

    /// What the chart turned out to be.
    enum Reading: Equatable {
        /// One column stands out: index into the labels, left to right.
        case day(index: Int, weekday: String?)
        /// Everything is highlighted — a total, not a single day.
        case aggregate
        /// No chart found, or nothing conclusive. The caller falls back to
        /// asking, which is the honest outcome.
        case inconclusive
    }

    /// Day-of-week abbreviations as the platforms print them.
    private static let weekdayNames = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// A column counts as selected when this much of its saturation lead is
    /// over the field. Set high because the cost of guessing wrong is a day's
    /// earnings filed on the wrong date.
    private static let selectionMargin: Double = 0.18

    // MARK: Entry point

    static func read(image: CGImage, lines: [RecognisedLine]) -> Reading {
        guard let labels = dayLabels(in: lines), labels.count >= 3 else { return .inconclusive }
        guard let sampler = Sampler(image: image) else { return .inconclusive }

        // The chart lives above the labels. Bound the search from the top of
        // the image to just above the tallest label, and ignore the top
        // eighth — that's the status bar and the navigation title.
        let labelTop = labels.map(\.top).min() ?? 0
        let bandTop = max(labelTop - 0.34, 0.06)
        let bandBottom = max(labelTop - 0.005, bandTop + 0.01)

        let scores = labels.map { label in
            sampler.saturation(xRange: label.xRange, yRange: bandTop...bandBottom)
        }
        guard let peak = scores.max(), peak > 0.25 else { return .inconclusive }

        // How many columns are near the peak. In a week view every bar is
        // solid, so this is all of them.
        let nearPeak = scores.filter { $0 > peak - selectionMargin }.count
        if nearPeak > max(labels.count / 2, 1) { return .aggregate }
        guard nearPeak == 1, let index = scores.firstIndex(of: peak) else { return .inconclusive }

        return .day(index: index, weekday: labels[index].weekday)
    }

    /// Resolves a reading against the week the screenshot covers.
    ///
    /// Prefers the weekday name over the column position: OCR can drop a
    /// label and shift every index by one, but "Wed" is unambiguous.
    static func date(for reading: Reading,
                     weekStart: Date,
                     calendar: Calendar = .gigPilot) -> Date? {
        guard case .day(let index, let weekday) = reading else { return nil }

        if let weekday, let offset = weekdayNames.firstIndex(of: weekday.lowercased()) {
            // weekStart is a Monday in GigPilot's calendar, and the names are
            // listed from Monday, so the offset is the index directly.
            return calendar.date(byAdding: .day, value: offset, to: weekStart)
        }
        return calendar.date(byAdding: .day, value: index, to: weekStart)
    }

    // MARK: Labels

    private struct Label {
        let xRange: ClosedRange<CGFloat>
        let top: CGFloat
        let weekday: String?
    }

    /// Finds the horizontal strip of day labels.
    ///
    /// Vision may return "1 Mon" as one line or "1" and "Mon" as two, so this
    /// keys on anything containing a weekday name and groups by vertical
    /// position rather than assuming a layout.
    private static func dayLabels(in lines: [RecognisedLine]) -> [Label]? {
        let candidates = lines.compactMap { line -> (line: RecognisedLine, name: String)? in
            let lower = line.text.lowercased()
            guard let name = weekdayNames.first(where: { lower.contains($0) }) else { return nil }
            // A sentence mentioning a day isn't a chart label.
            guard line.text.count <= 8 else { return nil }
            return (line, name)
        }
        guard candidates.count >= 3 else { return nil }

        // Keep the widest horizontal band — if a screen shows two rows of
        // weekday text, the chart's is the one with the most entries.
        let grouped = Dictionary(grouping: candidates) { candidate in
            (candidate.line.topDownY * 40).rounded()
        }
        guard let row = grouped.values.max(by: { $0.count < $1.count }), row.count >= 3 else {
            return nil
        }

        return row
            .sorted { $0.line.box.minX < $1.line.box.minX }
            .map { candidate in
                // Widen slightly: the bar is usually a touch wider than its
                // label, and clipping it loses the colour that matters.
                let box = candidate.line.box
                let pad = box.width * 0.3
                return Label(
                    xRange: max(box.minX - pad, 0)...min(box.maxX + pad, 1),
                    top: candidate.line.topDownY,
                    weekday: candidate.name
                )
            }
    }

    // MARK: Pixels

    /// Reads saturation out of a region of the image.
    private struct Sampler {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let data: [UInt8]

        init?(image: CGImage) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0 else { return nil }

            // Redraw into a known layout. The source could be anything —
            // indexed colour, 16-bit, a different byte order — and guessing
            // at CGImage's native format is how you get a detector that works
            // on your phone and nobody else's.
            let bytesPerRow = width * 4
            var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
            guard let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
                CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }) else { return nil }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            self.width = width
            self.height = height
            self.bytesPerRow = bytesPerRow
            self.data = buffer
        }

        /// Mean saturation of the most colourful pixels in a region.
        ///
        /// The mean over everything would be dominated by the white
        /// background, and every column would score about the same. Taking
        /// the top decile asks the question that matters: how strong is the
        /// strongest colour in this column.
        func saturation(xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>) -> Double {
            let x0 = clamp(Int(xRange.lowerBound * CGFloat(width)), 0, width - 1)
            let x1 = clamp(Int(xRange.upperBound * CGFloat(width)), 0, width - 1)
            let y0 = clamp(Int(yRange.lowerBound * CGFloat(height)), 0, height - 1)
            let y1 = clamp(Int(yRange.upperBound * CGFloat(height)), 0, height - 1)
            guard x1 > x0, y1 > y0 else { return 0 }

            // Step across large screenshots rather than reading every pixel;
            // this runs once per image but there may be twenty of them.
            let xStep = max((x1 - x0) / 40, 1)
            let yStep = max((y1 - y0) / 60, 1)

            var samples: [Double] = []
            samples.reserveCapacity(2_500)

            var y = y0
            while y <= y1 {
                var x = x0
                while x <= x1 {
                    let offset = y * bytesPerRow + x * 4
                    guard offset + 2 < data.count else { break }
                    let r = Double(data[offset]) / 255
                    let g = Double(data[offset + 1]) / 255
                    let b = Double(data[offset + 2]) / 255

                    let high = max(r, g, b)
                    let low = min(r, g, b)
                    // Saturation, HSV definition. Black scores zero rather
                    // than dividing by nothing.
                    samples.append(high <= 0.001 ? 0 : (high - low) / high)
                    x += xStep
                }
                y += yStep
            }
            guard !samples.isEmpty else { return 0 }

            samples.sort(by: >)
            let decile = max(samples.count / 10, 1)
            return samples.prefix(decile).reduce(0, +) / Double(decile)
        }

        private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
            min(max(value, low), high)
        }
    }
}
