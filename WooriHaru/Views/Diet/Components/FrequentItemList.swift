import SwiftUI

/// 기간 통계의 「자주 먹은 음식」 가로 스트립.
///
/// **표시 전용이다.** 예전에는 탭하면 바로 담기는 자리였지만, 항목을 고르는 화면이
/// `FoodPickRow`를 쓰는 세로 목록으로 바뀌면서 여기서 눌러 담을 곳이 없어졌다. 그런데도
/// 버튼으로 두면 눌러도 반응 없고 접근성 포커스만 잡히는 컨트롤이 된다.
struct FrequentItemList: View {
    let items: [FrequentItem]
    var title: String = "자주 먹은 음식"

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.foodName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.slate700)
                                    .lineLimit(1)
                                Text("\(Int(item.quantityG.rounded()))g · \(item.countText)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.slate400)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassInputField(cornerRadius: 10)
                            // 한 항목이 한 덩어리로 읽히게 묶는다 — 안 묶으면 이름과
                            // 「200g · 7회」가 따로 읽혀 어느 음식의 수치인지 흐려진다.
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}
