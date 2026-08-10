import SwiftUI

/// 타임라인에 쌓인 끼니 카드. 서버가 끼니를 확정할 때 놓는다.
///
/// **값은 조회 시점의 끼니에서 온다** — 확정 뒤에 항목을 고쳐도 카드가 낡지 않는다.
struct ChatMealCardView: View {
    let card: ChatMealCard
    /// 「08-01」. **카드의 `date`가 구분선 날짜와 다를 때만 온다** — 8월 1일 끼니를 8월 3일에
    /// 뒤늦게 확정하면 카드는 8월 3일 자리에 앉는다.
    var badge: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if let badge {
                    ChatDateBadge(text: badge)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        titleRow
                        Text("\(Int(card.totalKcal.rounded()).formatted()) kcal")
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                        macroRow
                    }

                    Spacer(minLength: 0)

                    thumbnail
                }

                if let basis = card.scoreBasis {
                    MacroStackBar(macros: basis.macros)
                }

                feedbackRow
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: card.mealType.iconName)
                .font(.caption)
                .foregroundStyle(Color.blue500)
            Text(card.mealType.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)
            Text("·")
                .font(.caption)
                .foregroundStyle(Color.slate300)
            Text(card.score.map { "\($0)점" } ?? "점수 없음")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.slate900)
        }
    }

    /// 색을 막대와 맞춘다 — 어느 칸이 무엇인지 알 길이 그 색뿐이다.
    private var macroRow: some View {
        HStack(spacing: 8) {
            macroText("탄", card.carbsG, name: "탄수화물")
            macroText("단", card.proteinG, name: "단백질")
            macroText("지", card.fatG, name: "지방")
        }
    }

    private func macroText(_ label: String, _ grams: Double, name: String) -> some View {
        Text("\(label) \(Int(grams.rounded()))g")
            .font(.caption2.weight(.medium))
            .foregroundStyle(MacroStackBar.tint(for: name))
    }

    @ViewBuilder
    private var thumbnail: some View {
        // presigned URL이라 매 조회 새로 발급된다. 사진 없이 기록한 끼니는 아무것도 안 그린다.
        if let url = card.photoUrl, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(Color.slate300)
                default:
                    ProgressView()
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// **재시도 버튼을 두지 않는다** — 끼니를 고치면 자연히 다시 만들어진다(하루 화면이 이미
    /// 같은 판단을 한다). 폴링하지도 않는다 — 화면을 다시 열면 채워져 있다.
    @ViewBuilder
    private var feedbackRow: some View {
        if let feedback = card.feedback {
            Text(feedback)
                .font(.footnote)
                .foregroundStyle(Color.slate700)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("코치가 보고 있어요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
        }
    }
}
