import SwiftUI

/// 충전 상세 — 목록이 아는 값으로 먼저 그리고, 서버 상세(출력·효율·주소)를 덧입힌다.
/// 고칠 수 있는 것은 금액 하나뿐이다.
struct ChargeDetailView: View {
    let item: ChargeItem
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var detail: ChargeDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCostEdit = false
    /// 진행 중 상세 요청의 세대 번호 — 첫 요청이 도는 중에 금액을 저장하면 요청이 겹치는데,
    /// 늦게 도착한 옛 응답이 방금 저장한 금액을 덮어쓰면 안 된다.
    @State private var detailGeneration = 0
    /// 저장에 성공한 금액. 이어지는 상세 조회가 실패해도 화면이 옛 금액으로 되돌아가지 않게 한다.
    /// 상세를 다시 받으면 서버 값이 사실이므로 비운다.
    @State private var savedCost: Decimal?
    @State private var curve: [ChargeCurveSample]?
    @State private var curveFailed = false

    private let service = ChargeService()

    /// 금액은 방금 저장한 값 > 상세 값 > 목록 값 순으로 고른다.
    private var cost: Decimal? { savedCost ?? detail?.cost ?? item.cost }

    /// 단가의 분모. 목록에도 실려 오므로 상세를 받기 전부터 낼 수 있다.
    private var energyUsedKwh: Decimal? { detail?.energyUsedKwh ?? item.energyUsedKwh }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    costCard
                    sessionCard
                    if let detail {
                        chargerCard(detail)
                        if let curve {
                            ChargeCurveChart(samples: curve)
                        }
                        placeCard(detail)
                    } else if isLoading {
                        ProgressView().padding(.top, 8)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .glassScreenBackground()
            .vehicleDarkTheme()
            .navigationTitle("충전 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("금액 수정") { showingCostEdit = true }
                }
            }
            .sheet(isPresented: $showingCostEdit) {
                ChargeCostEditSheet(chargeId: item.id, initialCost: cost) { saved in
                    // 저장한 값을 먼저 세워 시트가 닫히는 순간 화면이 맞게 한다.
                    // 새로고침은 시트 밖에서 돈다 — 시트를 붙잡아 둘 이유가 없다.
                    savedCost = saved
                    Task {
                        await reloadDetail()
                        await onChanged()
                    }
                }
                .presentationDetents([.height(280)])
            }
            .task { await reloadDetail() }
            // 상세의 id에 매인다 — 시트가 닫히면 뷰와 함께 취소된다.
            // 상세가 아직 없으면(id가 nil) 아무 것도 하지 않으니 상세보다 먼저 돌지 않는다.
            .task(id: detail?.id) {
                guard let detail else { return }
                await loadCurveIfFast(detail)
            }
        }
    }

    // MARK: - 카드

    private var costCard: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 8) {
                Text(ChargeFormat.cost(cost))
                    .font(.system(size: 32, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(cost == nil ? VehicleTheme.warning : VehicleTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // 단가는 **화면에 보이는 그 금액**으로 낸다 — 저장은 됐는데 상세를 다시 못 받은
                // 사이에 `detail.costPerKwh`를 쓰면 새 금액 아래에 옛 금액으로 나눈 단가가 붙는다.
                if let unit = ChargeMath.costPerKwh(cost: cost, energyUsedKwh: energyUsedKwh) {
                    Text(ChargeFormat.unitPrice(unit))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textSecondary)
                } else if cost == nil {
                    Text("오른쪽 위 「금액 수정」으로 채워 넣어요")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sessionCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                detailRow("시작", LedgerFormat.full(item.startDate))
                Divider().padding(.vertical, 8)
                detailRow("종료", item.endDate.map(LedgerFormat.full) ?? ChargeFormat.placeholder)
                Divider().padding(.vertical, 8)
                detailRow("소요", ChargeFormat.duration(detail?.durationMin ?? item.durationMin))
                Divider().padding(.vertical, 8)
                detailRow("충전량", ChargeFormat.energy(detail?.energyAddedKwh ?? item.energyAddedKwh))
                if let detail {
                    Divider().padding(.vertical, 8)
                    detailRow("사용 전력", ChargeFormat.energy(detail.energyUsedKwh))
                    Divider().padding(.vertical, 8)
                    // 효율은 서버가 아니라 여기서 나눈다 — 분모가 없으면 「—」다.
                    detailRow("효율", ChargeFormat.percent(detail.efficiency))
                }
                Divider().padding(.vertical, 8)
                detailRow("배터리", ChargeFormat.batteryRange(
                    detail?.startBatteryLevel ?? item.startBatteryLevel,
                    detail?.endBatteryLevel ?? item.endBatteryLevel
                ))
                if let detail {
                    Divider().padding(.vertical, 8)
                    detailRow("주행가능거리", rangeText(detail))
                }
            }
        }
    }

    private func rangeText(_ detail: ChargeDetail) -> String {
        guard let start = detail.startRatedRangeKm, let end = detail.endRatedRangeKm else {
            return ChargeFormat.placeholder
        }
        let gain = detail.ratedRangeGainKm.map { " (+\(ChargeFormat.distance($0)))" } ?? ""
        return "\(ChargeFormat.distance(start)) → \(ChargeFormat.distance(end))\(gain)"
    }

    private func chargerCard(_ detail: ChargeDetail) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                detailRow("충전기", chargerTypeText(detail))
                Divider().padding(.vertical, 8)
                detailRow("최대 출력", ChargeFormat.power(detail.maxPowerKw.map { Decimal($0) }))
                Divider().padding(.vertical, 8)
                detailRow("평균 출력", ChargeFormat.power(detail.avgPowerKw))
                Divider().padding(.vertical, 8)
                detailRow("외기 온도", ChargeFormat.temperature(detail.outsideTempAvg))
            }
        }
    }

    /// `charges` 샘플이 없으면 급속 여부 자체를 모른다 — 「완속」이라고 단정하지 않는다.
    private func chargerTypeText(_ detail: ChargeDetail) -> String {
        guard let fast = detail.fastCharger else { return ChargeFormat.placeholder }
        guard fast else { return "완속" }
        let extra = [detail.fastChargerBrand, detail.fastChargerType]
            .compactMap { $0 }
            .joined(separator: " ")
        return extra.isEmpty ? "급속" : "급속 · \(extra)"
    }

    private func placeCard(_ detail: ChargeDetail) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.geofenceName ?? item.locationName ?? "장소 없음")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                if let address = detail.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 로드

    private func reloadDetail() async {
        detailGeneration += 1
        let generation = detailGeneration
        isLoading = true
        defer {
            if generation == detailGeneration { isLoading = false }
        }
        do {
            let loaded = try await service.fetchDetail(id: item.id)
            guard generation == detailGeneration else { return } // 밀려난 응답은 폐기
            detail = loaded
            savedCost = nil // 서버 값이 사실이다
            errorMessage = nil
            // 곡선은 `.task(id: detail?.id)`가 따로 돈다 — 상세가 이미 그려진 뒤에 시작되고,
            // 뷰가 사라지면 함께 취소된다.
        } catch is CancellationError {
            return
        } catch {
            guard generation == detailGeneration else { return }
            // 목록에서 아는 값은 그대로 두고 못 받은 사실만 알린다.
            errorMessage = "상세를 불러오지 못했습니다."
        }
    }

    /// **급속에만 곡선을 그린다.** 완속은 실측으로 7시간 내내 6kW 한 줄이라 볼 것이 없는데
    /// 샘플만 급속의 3.4배다(1,980개까지 온다). `fastCharger`가 nil이면 급속 여부를 모르는
    /// 것이므로 그리지 않는다 — 「완속」이라고 단정하지도 않는 기존 표기와 같은 규칙이다.
    private func loadCurveIfFast(_ detail: ChargeDetail) async {
        guard detail.fastCharger == true, curve == nil, !curveFailed else { return }
        do {
            curve = try await service.fetchCurve(id: detail.id).samples
        } catch is CancellationError {
            return
        } catch {
            // 곡선 하나 때문에 상세를 죽이지 않는다. 조용히 접는다.
            curveFailed = true
        }
    }
}

/// 금액 입력 — 원화 정수만 받는다. 서버가 되돌리기(null)를 두지 않으므로 빈 값 저장도 없다.
struct ChargeCostEditSheet: View {
    let chargeId: Int
    let initialCost: Decimal?
    /// 저장에 성공한 금액을 그대로 넘긴다 — 부르는 쪽이 상세를 다시 못 받아도 화면을 맞출 수 있다.
    ///
    /// **async가 아니다.** 이어지는 새로고침을 여기서 기다리면, 저장은 이미 끝났는데도
    /// 시트가 그 요청들의 타임아웃만큼 닫히지 않고 잠긴 채로 남는다.
    let onSaved: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private let service = ChargeService()

    init(chargeId: Int, initialCost: Decimal?, onSaved: @escaping (Decimal) -> Void) {
        self.chargeId = chargeId
        self.initialCost = initialCost
        self.onSaved = onSaved
        _text = State(initialValue: initialCost.map(ChargeFormat.plainNumber) ?? "")
    }

    /// 서버가 받아 주는 값만 통과한다 — 규칙은 `ChargeFormat.parseCost` 참고.
    private var parsedCost: Decimal? { ChargeFormat.parseCost(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("금액", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .focused($focused)
                    .padding(14)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 14))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                } else {
                    Text("충전 1건의 금액이에요. 비울 수는 없고, 잘못 넣었으면 다시 저장해요.")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassScreenBackground()
            .vehicleDarkTheme()
            .navigationTitle("금액 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(parsedCost == nil || isSaving)
                }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard let cost = parsedCost else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await service.updateCost(id: chargeId, cost: cost)
                onSaved(cost)
                dismiss()
            } catch {
                // 404는 「없는 충전」이 아니라 「아직 안 끝난 충전」인 경우가 대부분이다 —
                // 서버가 진행 중인 행의 수정을 막는다(마감하면서 금액이 덮어써지기 때문).
                if case let APIError.serverError(status, _) = error, status == 404 {
                    errorMessage = "아직 끝나지 않았거나 사라진 충전이라 금액을 적을 수 없어요."
                } else {
                    errorMessage = "금액을 저장하지 못했습니다."
                }
            }
        }
    }
}
