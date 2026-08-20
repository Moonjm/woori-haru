import SwiftUI

/// 통계 탭 차트 카드의 껍데기 — 제목 · 콜아웃 · 그림. **열네 장이 같은 껍데기를 쓴다.**
/// 껍데기가 섹션마다 다르면 스크롤하면서 카드 경계를 다시 배워야 한다.
struct ChartCard<Content: View>: View {
    let title: String
    /// 오른쪽 위에 붙는 한 줄. 선택한 달의 값이거나 「전 기간」 같은 범위 표시다.
    var callout: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    if let callout {
                        Text(callout)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.accentBright)
                            .lineLimit(1)
                    }
                }
                content()
            }
        }
    }
}
