import SwiftUI

/// 타임라인에 쌓인 하루 총평 카드. 그 날짜의 총평이 처음 완성된 시각에 앉는다 —
/// 나중에 재생성돼도 자리가 움직이지 않는다.
struct ChatDayCardView: View {
    let card: ChatDayCard
    /// 어느 날 총평인가. "2026-08-06"
    let date: String
    /// 「08-01」. 구분선(`createdAt`) 날짜와 다를 때만 온다.
    var badge: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                if let badge {
                    ChatDateBadge(text: badge)
                }

                HStack(spacing: 6) {
                    Text("\(Date.from(date)?.monthDayText ?? date) 마감")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.slate300)
                    Text("\(card.dayScore)점")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }

                // **분모는 그날 첫 끼니의 스냅샷이다** — 프로필의 현재 목표가 아니라서
                // 몸무게를 바꿔도 과거 카드가 흔들리지 않는다.
                Text("\(Int(card.totalKcal.rounded()).formatted()) / \(card.targetKcal.formatted()) kcal")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)

                feedbackRow
            }
        }
    }

    /// **`DietHomeView.feedbackSection`과 같은 문구를 쓴다.** 두 화면이 같은 상태를 다르게
    /// 말하면 사용자는 다른 일이 일어났다고 읽는다.
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
                Text("마감 피드백을 만들고 있어요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
        }
    }
}
