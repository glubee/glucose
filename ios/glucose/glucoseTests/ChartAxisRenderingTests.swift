import XCTest
import SwiftUI
import Vision
@testable import glucose

@MainActor
final class ChartAxisRenderingTests: XCTestCase {
    func testHourLabelsAreCenteredOnTheirActualTime() throws {
        let day = ReportDay.today()
        let points = [GlucosePoint(time: day, value: 150, segment: 0),
                      GlucosePoint(time: day.addingTimeInterval(23.75 * 3600), value: 150, segment: 0)]
        let chart = GlucoseDayChart(day: day, points: points, episodes: [], insulinEvents: [], height: 240)
            .frame(width: 360).environment(\.colorScheme, .light).background(Color.white)
        let renderer = ImageRenderer(content: chart)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var line: (first: Int, last: Int)?
        for y in 0..<height {
            let dark = (0..<width).filter { x in
                let p = (y * width + x) * 4
                return pixels[p] < 80 && pixels[p + 1] < 80 && pixels[p + 2] < 80 && pixels[p + 3] > 200
            }
            if let first = dark.first, let last = dark.last,
               dark.count > Int(Double(width) * 0.65), last - first > Int(Double(width) * 0.7) {
                line = (first, last)
                break
            }
        }
        let span = try XCTUnwrap(line)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ko-KR"]
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        for hour in [6, 9] {
            let labelX = try XCTUnwrap((request.results ?? []).compactMap { observation -> Double? in
                guard let candidate = observation.topCandidates(1).first,
                      let range = candidate.string.range(of: "\(hour)\\s*시", options: .regularExpression),
                      let box = try? candidate.boundingBox(for: range) else { return nil }
                return box.boundingBox.midX * Double(width)
            }.first)
            let expected = Double(span.first) + Double(span.last - span.first) * Double(hour) / 23.75
            XCTAssertEqual(labelX, expected, accuracy: 8,
                           "시간 글자는 해당 시각 눈금에 가운데 정렬되어야 한다")
        }
    }
}
