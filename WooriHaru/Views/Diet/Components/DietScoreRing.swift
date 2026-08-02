import SwiftUI

/// 점수 링. `score`가 nil이면(물·커피처럼 매크로가 0인 끼니) 「–」를 그린다.
struct DietScoreRing: View {
    let score: Int?
    var size: CGFloat = 96
    var caption: String?

    private var progress: Double { Double(score ?? 0) / 100.0 }

    private var tint: Color {
        guard let score else { return .slate300 }
        switch score {
        case 80...: return .green600
        case 60..<80: return .blue500
        default: return .orange400
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.slate200, lineWidth: size * 0.09)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)

            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                if let caption {
                    Text(caption)
                        .font(.system(size: size * 0.11))
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(score.map { "점수 \($0)점" } ?? "점수 없음")
    }
}
