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
                // **`.decimalPad`가 아니다** — 마이너스 키가 없어 「관리비차감 -13,790」
                // 같은 차감 행을 고칠 수가 없다. 그 행은 고지서에 실제로 있고 서버도
                // 음수를 받는다. 대신 아무 글자나 들어올 수 있게 되지만, 뷰모델의
                // 파서가 숫자 모양만 통과시키고 `canSave`가 나머지를 막는다.
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 110)
        }
        .font(.subheadline)
        .foregroundStyle(VehicleTheme.textPrimary)
    }
}
