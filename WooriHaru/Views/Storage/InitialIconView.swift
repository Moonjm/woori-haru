import SwiftUI

struct InitialIconView: View {
    let name: String
    var size: CGFloat = 38

    private static let gradients: [(Color, Color)] = [
        (Color(red: 0.40, green: 0.49, blue: 0.92), Color(red: 0.46, green: 0.30, blue: 0.64)),
        (Color(red: 0.96, green: 0.44, blue: 0.10), Color(red: 0.95, green: 0.15, blue: 0.07)),
        (Color(red: 0.31, green: 0.67, blue: 1.0), Color(red: 0.0, green: 0.95, blue: 1.0)),
        (Color(red: 0.98, green: 0.44, blue: 0.60), Color(red: 1.0, green: 0.88, blue: 0.25)),
        (Color(red: 0.63, green: 0.55, blue: 0.82), Color(red: 0.98, green: 0.76, blue: 0.92)),
        (Color(red: 0.26, green: 0.91, blue: 0.48), Color(red: 0.22, green: 0.98, blue: 0.84)),
    ]

    private var initial: String {
        String(name.prefix(1))
    }

    private var gradient: LinearGradient {
        guard let first = name.unicodeScalars.first else {
            return LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let pair = Self.gradients[Int(first.value) % Self.gradients.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26).fill(gradient))
    }
}
