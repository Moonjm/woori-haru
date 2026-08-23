import SwiftUI

/// 한 달 상세. **서버에서 다시 받지 않는다** — 목록 응답이 이미 같은 필드를 다 갖고 있다.
/// 수정하고 돌아올 때만 목록을 새로 받는다(`onChanged`).
struct MaintenanceBillDetailView: View {
    let bill: MaintenanceBill
    /// 수정이 저장됐다. 목록을 다시 받아야 한다.
    var onChanged: () -> Void = {}
    /// 삭제됐다. 화면이 물러난 뒤 목록에서도 빠져야 한다.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var deleteTask: Task<Void, Never>?

    private let service: any MaintenanceServing = MaintenanceService()

    /// **금액 큰 순.** 서버 순서는 고지서 표 순서인데, 이 표가 답하는 질문은 「무엇이 컸나」다.
    private var sortedItems: [MaintenanceBillItem] {
        bill.items.sorted { $0.amount > $1.amount }
    }

    private var usageRows: [(label: String, value: Decimal, unit: String)] {
        guard let usage = bill.usage else { return [] }
        // **값이 있는 것만 담는다.** 「—」 다섯 줄은 정보가 아니다.
        return [
            ("전기", usage.electricityKwh, "kWh"),
            ("수도", usage.waterM3, "m³"),
            ("온수", usage.hotWaterM3, "m³"),
            ("난방", usage.heatingGcal, "Gcal"),
            ("음식물", usage.foodKg, "kg"),
        ].compactMap { label, value, unit in
            value.map { (label, $0, unit) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard
                discountCard
                itemsCard
                if !usageRows.isEmpty { usageCard }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle(MaintenanceFormat.monthTitle(bill.yearMonth))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { deleteTask?.cancel() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("수정") { showingEdit = true }
                    Button("삭제", role: .destructive) { showingDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
                .accessibilityLabel("더 보기")
            }
        }
        .navigationDestination(isPresented: $showingEdit) {
            MaintenanceBillFormView(mode: .edit(bill)) {
                onChanged()
                // 이 화면이 들고 있는 `bill`은 수정 전 값이다. 그대로 남기면 방금 고친
                // 금액과 다른 숫자를 보여준다 — 목록으로 물러나 새로 받은 값을 보게 한다.
                dismiss()
            }
        }
        .alert("삭제할까요?", isPresented: $showingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                deleteTask?.cancel()
                deleteTask = Task { await delete() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(MaintenanceFormat.monthTitle(bill.yearMonth)) 관리비를 지웁니다. 되돌릴 수 없습니다.")
        }
    }

    private func delete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await service.deleteBill(yearMonth: bill.yearMonth)
            onDeleted()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            // **실패하면 물러나지 않는다** — 물러나면 사용자는 지워진 줄 안다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("부과액")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textSecondary)
                Text(MaintenanceFormat.won(bill.chargedAmount))
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.accentBright)
                HStack(spacing: 8) {
                    if let dong = bill.dong, let ho = bill.ho {
                        Text("\(dong)동 \(ho)호")
                    }
                    if let areaM2 = bill.areaM2 {
                        Text("\(NSDecimalNumber(decimal: areaM2).stringValue)m²")
                    }
                }
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    /// **0이 아닐 때만 그린다.** 늘 「할인 0원」이 붙어 있으면 그 줄은 읽히지 않고,
    /// 실제로 할인이 붙은 달에도 눈에 안 들어온다.
    @ViewBuilder private var discountCard: some View {
        if bill.discountTotal != 0 {
            GlassCard {
                HStack {
                    Text("할인")
                        .font(.subheadline)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer()
                    Text(MaintenanceFormat.won(bill.discountTotal))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.accent)
                }
            }
        }
    }

    private var itemsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("항목")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                // 비율 막대의 분모는 항목 중 최댓값이다 — 「가장 큰 항목 대비 얼마나」가
                // 눈이 읽는 질문이고, 나눗셈은 `ChartScale`이 이미 하는 일이다.
                let maxAmount = ChartScale.maxValue(
                    sortedItems.map { ChartPoint(id: $0.name, label: $0.name, value: $0.amount) }
                )
                ForEach(sortedItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(MaintenanceFormat.won(item.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(VehicleTheme.textSecondary)
                        }
                        GeometryReader { proxy in
                            let ratio = ChartScale.ratio(item.amount, max: maxAmount)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(VehicleTheme.trackFill)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(VehicleTheme.accentMuted)
                                    .frame(width: ratio > 0 ? max(3, proxy.size.width * ratio) : 0)
                            }
                        }
                        .frame(height: 5)
                    }
                }
                if sortedItems.isEmpty {
                    Text("항목이 없습니다")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
    }

    private var usageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("사용량")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                ForEach(usageRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        Spacer()
                        Text("\(NSDecimalNumber(decimal: row.value).stringValue) \(row.unit)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textPrimary)
                    }
                }
            }
        }
    }
}
