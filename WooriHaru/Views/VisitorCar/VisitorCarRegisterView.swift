import SwiftUI

/// 신규 방문차량 등록. **차량번호와 기간이면 끝난다** —
/// 웹 폼에 있는 휴대폰 칸은 서버가 요구하지 않아 뺐고, 동·호는 서비스가 채운다.
struct VisitorCarRegisterView: View {
    /// 등록에 성공해 물러날 때 홈이 잔여시간을 다시 읽게 한다.
    let onSaved: () -> Void

    @State private var viewModel = VisitorCarRegisterViewModel()
    @State private var showingFrequentCars = false
    @State private var frequentCars = FrequentCarStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                carCard
                periodCard
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                submitButton
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("신규 차량 등록")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("자주 쓰는 차량", isPresented: $showingFrequentCars, titleVisibility: .visible) {
            ForEach(frequentCars.cars) { car in
                Button("\(car.nickname) · \(car.carNo)") { viewModel.apply(car) }
            }
            Button("취소", role: .cancel) {}
        }
        .onChange(of: viewModel.didSucceed) {
            guard viewModel.didSucceed else { return }
            onSaved()
            dismiss()
        }
    }

    private var carCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("차량 정보", systemImage: "car")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                TextField("차량번호", text: $viewModel.carNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let error = viewModel.validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                // 저장된 게 없으면 감춘다 — 눌러 봐야 빈 목록이다.
                if !frequentCars.cars.isEmpty {
                    Button {
                        showingFrequentCars = true
                    } label: {
                        Label("자주 쓰는 차량 선택", systemImage: "bookmark")
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var periodCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("방문 기간", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작일", selection: $viewModel.startDate, displayedComponents: .date)
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료일", selection: $viewModel.endDate, displayedComponents: .date)

                Divider().overlay(VehicleTheme.cardStroke)

                TextField("방문사유 (선택)", text: $viewModel.visitReason)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                    // 서버 폼이 20자로 잘라 둔 칸이다 — 수정 시트와 같은 규칙을 쓴다.
                    .onChange(of: viewModel.visitReason) {
                        viewModel.visitReason = VisitorCarValidation.clampVisitReason(viewModel.visitReason)
                    }
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
        // 시작일·종료일 선택기가 기기 시간대가 아니라 한국 시각으로 뜨고 움직이게 한다.
        .seoulDatePickerEnvironment()
    }

    private var submitButton: some View {
        Button {
            Task { await viewModel.submit() }
        } label: {
            HStack {
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView().tint(VehicleTheme.background)
                } else {
                    Text("방문 차량 등록").fontWeight(.semibold)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(
                viewModel.canSubmit ? VehicleTheme.accent : VehicleTheme.trackFill,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(viewModel.canSubmit ? VehicleTheme.background : VehicleTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit)
    }
}
