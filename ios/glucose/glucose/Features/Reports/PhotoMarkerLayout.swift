import Foundation
import CoreGraphics

/// 사진 버튼은 곡선 가까이 두되 겹침·경계를 피한다. 남는 사진은 아래 기록 줄에서 볼 수 있다.
struct PhotoMarkerLayout {
    struct Anchor {
        let id: String
        let point: CGPoint
    }
    struct Placement: Identifiable {
        let id: String
        let anchor: CGPoint
        let frame: CGRect
    }

    static func place(anchors: [Anchor], bounds: CGSize) -> [Placement] {
        let side: CGFloat = 44
        guard bounds.width >= side, bounds.height >= side else { return [] }
        let plot = CGRect(origin: .zero, size: bounds)
        var result: [Placement] = []
        for anchor in anchors {
            guard anchor.point.x.isFinite, anchor.point.y.isFinite,
                  plot.contains(anchor.point) else { continue }
            let centerX = min(max(anchor.point.x, side / 2), bounds.width - side / 2)
            let ys = [anchor.point.y - side - 6, anchor.point.y + 8]
            let shifts: [CGFloat] = [0, -side / 2, side / 2]
            var selected: CGRect?
            for y in ys {
                for shift in shifts {
                    let x = min(max(centerX + shift - side / 2, 0), bounds.width - side)
                    let frame = CGRect(x: x, y: y, width: side, height: side)
                    if plot.contains(frame), !result.contains(where: { $0.frame.insetBy(dx: -3, dy: -3).intersects(frame) }) {
                        selected = frame
                        break
                    }
                }
                if selected != nil { break }
            }
            if let selected { result.append(Placement(id: anchor.id, anchor: anchor.point, frame: selected)) }
        }
        return result
    }
}
