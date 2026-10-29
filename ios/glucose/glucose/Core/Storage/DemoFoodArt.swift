//
//  DemoFoodArt.swift
//  glucose
//
//  DEBUG 전용: 데모·예시 기록에 붙이는 "음식 사진" 그림. 실제 사진이 아니라 음식 이름에 맞는 그림 문자를
//  나무 식탁 위 접시에 올려 그린다(사진 파일을 저장소에 넣지 않기 위해 코드로 만든다).
//

#if DEBUG
import UIKit

enum DemoFoodArt {
    /// 음식 이름 → 그림 문자. 이름 일부만 맞아도 된다(위에서부터 먼저 맞는 것)
    private static let table: [(String, String)] = [
        ("현미밥", "🍚"), ("백미밥", "🍚"), ("밥", "🍚"), ("계란", "🍳"), ("우유", "🥛"), ("요거트", "🥣"),
        ("김치찌개", "🍲"), ("찌개", "🍲"), ("샌드위치", "🥪"), ("아메리카노", "☕️"), ("커피", "☕️"),
        ("짜장면", "🍜"), ("라면", "🍜"), ("바나나", "🍌"), ("사과 주스", "🧃"), ("오렌지 주스", "🧃"), ("주스", "🧃"),
        ("사과", "🍎"), ("떡볶이", "🍢"), ("튀김", "🍤"), ("비빔밥", "🥘"), ("샐러드", "🥗"), ("닭가슴살", "🍗"),
        ("제육", "🥓"), ("초콜릿", "🍫"), ("치킨", "🍗"), ("맥주", "🍺"), ("소주", "🍶"), ("피자", "🍕"),
        ("콜라", "🥤"), ("캔디", "🍬"), ("사탕", "🍬"), ("포도당", "🍬"), ("빵", "🍞"), ("쿠키", "🍪"),
    ]

    static func emoji(for food: String) -> String {
        table.first { food.contains($0.0) }?.1 ?? "🍽️"
    }

    /// 음식 여러 개를 한 접시(또는 식탁)에 올린 그림. 4:3
    static func image(foods: [String], size: CGSize = CGSize(width: 480, height: 360)) -> UIImage {
        let emojis = Array(foods.map(emoji(for:)).prefix(3))
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            // 나무 식탁
            let wood = [UIColor(red: 0.76, green: 0.56, blue: 0.38, alpha: 1).cgColor,
                        UIColor(red: 0.60, green: 0.42, blue: 0.27, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: wood, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.black.withAlphaComponent(0.06).setStroke()
            for index in stride(from: 0, to: Int(size.height), by: 22) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: CGFloat(index)))
                path.addCurve(to: CGPoint(x: size.width, y: CGFloat(index) + 8),
                              controlPoint1: CGPoint(x: size.width * 0.3, y: CGFloat(index) - 6),
                              controlPoint2: CGPoint(x: size.width * 0.7, y: CGFloat(index) + 14))
                path.lineWidth = 2
                path.stroke()
            }
            // 접시
            let plate = rect.insetBy(dx: size.width * 0.14, dy: size.height * 0.08)
            UIColor.black.withAlphaComponent(0.18).setFill()
            UIBezierPath(ovalIn: plate.offsetBy(dx: 6, dy: 10)).fill()
            UIColor(white: 0.98, alpha: 1).setFill()
            UIBezierPath(ovalIn: plate).fill()
            UIColor(white: 0.90, alpha: 1).setStroke()
            let rim = UIBezierPath(ovalIn: plate.insetBy(dx: plate.width * 0.12, dy: plate.height * 0.12))
            rim.lineWidth = 3
            rim.stroke()
            // 음식
            let positions: [CGPoint] = switch emojis.count {
            case 1: [CGPoint(x: 0.5, y: 0.5)]
            case 2: [CGPoint(x: 0.38, y: 0.52), CGPoint(x: 0.64, y: 0.46)]
            default: [CGPoint(x: 0.36, y: 0.42), CGPoint(x: 0.63, y: 0.40), CGPoint(x: 0.50, y: 0.66)]
            }
            let fontSize = size.height * (emojis.count == 1 ? 0.46 : 0.32)
            for (emoji, position) in zip(emojis, positions) {
                let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
                let textSize = text.size()
                text.draw(at: CGPoint(x: size.width * position.x - textSize.width / 2,
                                      y: size.height * position.y - textSize.height / 2))
            }
        }
    }

    static func jpeg(foods: [String]) -> Data? {
        image(foods: foods).jpegData(compressionQuality: 0.8)
    }
}
#endif
