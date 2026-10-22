import SwiftUI

/// The website's palette (dark only, like peridot.ai).
enum Theme {
    static let background = Color(hex: 0x141413)
    static let surface = Color(hex: 0x1B1A19)
    static let surfaceHigh = Color(hex: 0x262523)
    static let border = Color(hex: 0xE8E6E0).opacity(0.1)
    static let text = Color(hex: 0xE8E6E0)
    static let muted = Color(hex: 0x8C8A83)
    static let mint = Color(hex: 0x6FD3B7)
    static let onMint = Color(hex: 0x0F1D19)
    static let error = Color(hex: 0xE5866F)
    static let code = Color(hex: 0x0F0F0E)

    static let logoGradient = LinearGradient(
        colors: [Color(hex: 0xD4F3EA), Color(hex: 0x8FE0C8), Color(hex: 0x5CC9A8)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The Peridot logo: four dots in a square. With `thinking` the dots pulse one after another,
/// which is how the app shows that an answer is on its way.
struct PeridotLogo: View {
    var size: CGFloat
    var thinking = false

    var body: some View {
        if thinking {
            TimelineView(.animation) { context in
                dots(phase: context.date.timeIntervalSinceReferenceDate / 0.35)
            }
        } else {
            dots(phase: nil)
        }
    }

    private func dots(phase: Double?) -> some View {
        // In the 512-unit logo: centers at 156 and 356, radius 56
        let unit = size / 512
        // Clockwise, so the pulse goes round
        let centers: [CGPoint] = [.init(x: 156, y: 156), .init(x: 356, y: 156), .init(x: 356, y: 356), .init(x: 156, y: 356)]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(Theme.logoGradient)
                    .frame(width: 112 * unit, height: 112 * unit)
                    .opacity(opacity(i, phase))
                    .offset(x: (centers[i].x - 56) * unit, y: (centers[i].y - 56) * unit)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func opacity(_ i: Int, _ phase: Double?) -> Double {
        guard let phase else { return 1 }
        let d = (phase - Double(i)).truncatingRemainder(dividingBy: 4)
        let distance = d < 0 ? d + 4 : d
        return distance < 1 ? 1 - 0.65 * distance : 0.35
    }
}

struct Avatar: View {
    var name: String
    var size: CGFloat = 32

    var body: some View {
        Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.onMint)
            .frame(width: size, height: size)
            .background(Theme.mint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "5 min ago" for a database time ("YYYY-MM-DD HH:MM:SS", UTC), in the phone's language.
func ago(_ value: String?) -> String {
    guard let value else { return "" }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(identifier: "UTC")
    parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let date = parser.date(from: value) else { return "" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
}

func planName(_ plan: String?, unlimited: Bool) -> String {
    if unlimited { return String(localized: "plan_unlimited") }
    switch plan {
    case "plus": return "Plus"
    case "extended": return "Extended 5x"
    case "extended10": return "Extended 10x"
    default: return String(localized: "plan_free")
    }
}
