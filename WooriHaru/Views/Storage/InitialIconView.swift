import SwiftUI

struct InitialIconView: View {
    let name: String
    var size: CGFloat = 32

    private static let colors: [Color] = [
        .red, .orange, .green, .blue, .purple, .pink,
    ]

    private var initial: String {
        String(name.prefix(1))
    }

    private var color: Color {
        guard let first = name.unicodeScalars.first else { return .gray }
        return Self.colors[Int(first.value) % Self.colors.count]
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }
}
