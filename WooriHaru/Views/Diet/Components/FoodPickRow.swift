import SwiftUI

/// 항목 고르기 세 탭이 공유하는 세로 목록 행.
///
/// **⊕와 행 탭이 다른 동작이다** — ⊕는 기본 수량으로 즉시 담고, 행을 누르면 상세 시트가
/// 열린다. 1인분을 모르는 항목은 ⊕도 상세 시트를 열어야 하는데, 그 판단은 화면이 아니라
/// `FoodPickSource.quickAddItem`이 한다.
struct FoodPickRow: View {
    let source: FoodPickSource
    /// 여러 개 모드에서 이미 담은 횟수. 0이면 배지를 그리지 않는다.
    var pickedCount: Int = 0
    var onTapRow: () -> Void
    var onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTapRow) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(source.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.slate700)
                            .lineLimit(1)

                        if let badge = source.badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(Color.slate500)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.slate100, in: Capsule())
                        }

                        // **이름 줄이 아니라 여기다** — 이름이 `피자_뉴욕 오리진 피자
                        // 오리지널 (L)`처럼 길어서 한 줄에 합치면 둘 다 잘린다. 배지와 달리
                        // 캡슐을 두르지 않는다(브랜드는 분류가 아니라 정보다).
                        if let brand = source.brandText {
                            Text(brand)
                                .font(.caption2)
                                .foregroundStyle(Color.blue500)
                                .lineLimit(1)
                        }

                        if pickedCount > 0 {
                            Text("담김 \(pickedCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue500, in: Capsule())
                        }
                    }

                    Text(source.detailText)
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(source.kcalText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate500)

            Button(action: onQuickAdd) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Color.blue500)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(source.name) 담기")
        }
        .padding(.vertical, 8)
    }
}
