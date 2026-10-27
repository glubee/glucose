//
//  MeadowScene.swift
//  glucose
//
//  글루비 뒤 작은 장면(디자이너 v5): 위에서 아래로 흰색→연노랑, 오른쪽 위 해, 아래 풀밭, 꽃 네 송이.
//  장식이라 VoiceOver에서 숨긴다.
//

import SwiftUI

struct MeadowScene<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    private var skyBottom: Color {
        scheme == .dark ? Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x14 / 255)
                        : Color(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xE3 / 255)
    }
    private var ground: Color {
        scheme == .dark ? Color(red: 0x16 / 255, green: 0x26 / 255, blue: 0x1F / 255)
                        : Color(red: 0xEA / 255, green: 0xF5 / 255, blue: 0xEE / 255)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color.canvas, skyBottom], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color.brandSoft)
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 30, y: 12)
            Ellipse()
                .fill(ground)
                .frame(height: 84)
                .padding(.horizontal, -40)
                .offset(y: 36)
            flowers
                .frame(height: 70)
                .padding(.bottom, 10)
            content()
                .padding(.bottom, 6)
        }
        .clipped()
    }

    private var flowers: some View {
        Canvas { context, size in
            let stem = scheme == .dark ? Color(red: 0x3E / 255, green: 0x7D / 255, blue: 0x66 / 255)
                                       : Color(red: 0x8C / 255, green: 0xC7 / 255, blue: 0xB0 / 255)
            let pink = Color(red: 0xF2 / 255, green: 0xA0 / 255, blue: 0x8F / 255)
            let sky = Color(red: 0x9C / 255, green: 0xC3 / 255, blue: 0xEC / 255)
            let flowers: [(CGFloat, CGFloat, Color)] = [(38, 34, pink), (72, 46, .brand), (size.width - 72, 40, sky), (size.width - 40, 50, pink)]
            for (x, height, color) in flowers {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - height))
                context.stroke(path, with: .color(stem), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for petal in 0..<5 {
                    let angle = Double(petal) * 2 * .pi / 5
                    let rect = CGRect(x: x + 6 * cos(angle) - 4.6, y: size.height - height + 6 * sin(angle) - 4.6, width: 9.2, height: 9.2)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: size.height - height - 3.4, width: 6.8, height: 6.8)),
                             with: .color(scheme == .dark ? .brand : .white))
            }
            // 풀잎
            for x in [120.0, 134, size.width - 140, size.width - 126] {
                var blade = Path()
                blade.move(to: CGPoint(x: x, y: size.height))
                blade.addQuadCurve(to: CGPoint(x: x + 8, y: size.height), control: CGPoint(x: x + 4, y: size.height - 12))
                context.stroke(blade, with: .color(stem), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
    }
}
