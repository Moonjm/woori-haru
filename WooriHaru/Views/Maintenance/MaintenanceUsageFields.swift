import SwiftUI

/// 사용량 다섯 칸. **비워 두면 nil로 나간다** — 뷰모델이 빈 문자열을 nil로 옮긴다.
/// 0을 미리 채워 두지 않는 이유가 그것이다: 사람이 지우지 않는 한 「0을 썼다」가 저장된다.
struct MaintenanceUsageFields: View {
    @Bindable var vm: MaintenanceBillFormViewModel

    var body: some View {
        VStack(spacing: 8) {
            field("전기", unit: "kWh", text: $vm.electricityKwh)
            field("수도", unit: "m³", text: $vm.waterM3)
            field("온수", unit: "m³", text: $vm.hotWaterM3)
            field("난방", unit: "Gcal", text: $vm.heatingGcal)
            field("음식물", unit: "kg", text: $vm.foodKg)
        }
    }

    private func field(_ label: String, unit: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
                .frame(width: 56, alignment: .leading)
            TextField("고지서에 없으면 비워 두세요", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
            Text(unit)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
