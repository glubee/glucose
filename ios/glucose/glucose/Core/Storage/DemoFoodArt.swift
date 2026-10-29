//
//  DemoFoodArt.swift
//  glucose
//
//  DEBUG 전용: 데모·예시 기록에 붙이는 음식 사진.
//  1) 저장소 밖 폴더(음식 이름.jpg, 예: 짜장면.jpg)에 실제 사진이 있으면 그것을 쓴다. 음식 사진은 커밋하지 않는다.
//     폴더: 실행 인자 -demoPhotoDir <경로>, 없으면 시뮬레이터에서 Mac의 ~/glubee-demo-photos
//     (Desktop·Documents·Downloads는 macOS 권한 확인 창 때문에 앱이 멈추므로 쓰지 않는다)
//     (한 번 -demoSeed로 서버에 올리면 같은 데모 계정의 실기기에서도 보인다)
//  2) 없으면 음식 이름에 맞는 그림 문자를 나무 식탁 위 접시에 올려 그린다.
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

    // MARK: - 실제 사진(저장소 밖 폴더)

    private static let photoDirectory: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demoPhotoDir"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        // 시뮬레이터는 Mac 파일을 바로 읽을 수 있다
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        return URL(fileURLWithPath: home).appendingPathComponent("glubee-demo-photos", isDirectory: true)
    }()

    /// 폴더 안 사진 이름(확장자 뺀 음식 이름) → 파일. 긴 이름부터 맞춘다("사과 주스"가 "사과"보다 먼저)
    private static let photoFiles: [(String, URL)] = {
        guard let directory = photoDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .map { ($0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping, $0) }
            .sorted { $0.0.count > $1.0.count }
    }()

    static var hasRealPhotos: Bool { !photoFiles.isEmpty }

    private static func realPhoto(for food: String) -> UIImage? {
        let name = food.precomposedStringWithCanonicalMapping
        guard let url = photoFiles.first(where: { name.contains($0.0) })?.1 else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 실제 사진 한두 장을 4:3 한 장으로(두 장이면 반씩 나란히)
    private static func composite(_ photos: [UIImage], size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let width = size.width / CGFloat(photos.count)
            for (index, photo) in photos.enumerated() {
                let slot = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: size.height)
                let scale = max(slot.width / photo.size.width, slot.height / photo.size.height)
                let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                UIBezierPath(rect: slot).addClip()
                photo.draw(in: CGRect(x: slot.midX - drawn.width / 2, y: slot.midY - drawn.height / 2,
                                      width: drawn.width, height: drawn.height))
                UIGraphicsGetCurrentContext()?.resetClip()
            }
            if photos.count == 2 {
                UIColor.white.setFill()
                UIBezierPath(rect: CGRect(x: width - 1.5, y: 0, width: 3, height: size.height)).fill()
            }
        }
    }

    // MARK: - 그림

    /// 음식 여러 개를 한 장으로. 폴더에 실제 사진이 있으면 그것을, 없으면 접시 그림. 4:3
    static func image(foods: [String], size: CGSize = CGSize(width: 480, height: 360)) -> UIImage {
        let photos = Array(foods.compactMap(realPhoto(for:)).prefix(2))
        if !photos.isEmpty { return composite(photos, size: size) }
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
