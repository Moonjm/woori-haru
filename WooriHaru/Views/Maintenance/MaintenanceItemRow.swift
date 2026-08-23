import SwiftUI

/// 항목 한 줄 — 이름과 금액. **행을 따로 뺀 이유는 폼이 커지기 때문이다**(항목 스무 줄에
/// 사용량 다섯 칸에 금액 여섯 칸). 한 파일이 400줄을 넘기기 전에 가른다.
struct MaintenanceItemRow: View {
    @Binding var item: MaintenanceItemDraft

    var body: some View {
        HStack(spacing: 10) {
            // 서버 한도 50자. 넘겨 보내면 400이라 여기서 자른다.
            TextField("항목명", text: $item.name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: item.name) { _, new in
                    if new.count > 50 { item.name = String(new.prefix(50)) }
                }
            TextField("금액", text: $item.amount)
                // **`.numberPad`가 아니다** — 소수점이 없어 소수 금액을 못 넣는다.
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 110)
        }
        .font(.subheadline)
        .foregroundStyle(VehicleTheme.textPrimary)
    }
}
