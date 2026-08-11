import SwiftUI

/// 주의 영양소 한 줄. **앱은 판정하지 않는다** — `status`가 `WARN`이면 강조하고 `OK`면 평범하게
/// 둔다. `standardText`는 서버 문구를 그대로 쓴다(기준이 개정되면 앱 배포 없이 따라간다).
///
/// **점수와 무관하다는 게 화면에서 드러나야 한다.** 점수는 탄단지 비율만 보므로 이 줄을 점수 링
/// 옆에 붙여 감점 요인처럼 보이게 하면 안 된다.
struct NutrientLimitRow: View {
    let limit: NutrientLimit

    private var isWarning: Bool { limit.status == .warn }

    var body: some View {
        HStack(spacing: 8) {
            Text(limit.name)
                .font(.caption)
                .foregroundStyle(isWarning ? Color.orange400 : Color.slate500)

            Spacer()

            Text(intakeText)
                .font(.caption.weight(isWarning ? .bold : .medium))
                .foregroundStyle(isWarning ? Color.orange400 : Color.slate700)

            Text(limit.standardText)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(limit.name) \(intakeText), 기준 \(limit.standardText)\(isWarning ? ", 주의" : "")")
    }

    /// 나트륨은 mg이라 소수가 의미 없고 g 단위는 소수 한 자리까지 보여준다.
    private var intakeText: String {
        limit.unit == "mg"
            ? "\(Int(limit.intake.rounded()))\(limit.unit)"
            : String(format: "%.1f%@", limit.intake, limit.unit)
    }
}
