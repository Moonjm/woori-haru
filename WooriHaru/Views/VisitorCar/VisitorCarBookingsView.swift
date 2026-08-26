import SwiftUI

/// 등록 내역 조회. 조건 카드 + 결과 목록 + 상세 시트(수정·삭제).
struct VisitorCarBookingsView: View {
    @State private var viewModel = VisitorCarBookingsViewModel()
    @State private var selected: VisitorCarBooking?
    @State private var pendingDeletion: VisitorCarBooking?

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                conditionCard

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.bookings.isEmpty && !viewModel.isLoading {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(VehicleTheme.textTertiary)
                            Text("등록 내역이 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(viewModel.bookings) { booking in
                        Button { selected = booking } label: { row(booking) }
                            .buttonStyle(.plain)
                    }

                    // 무한 스크롤을 만들지 않는다 — 세대 하나가 쌓는 건수가 그만큼 되지 않는다.
                    if viewModel.hasMore {
                        Button { Task { await viewModel.loadMore() } } label: {
                            Text("더 보기")
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("등록 내역 조회")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
        .sheet(item: $selected) { booking in
            detailSheet(booking)
                .presentationDetents([.medium])
                .vehicleDarkTheme()
        }
        .alert("등록 내역 삭제", isPresented: .constant(pendingDeletion != nil)) {
            Button("삭제", role: .destructive) {
                guard let target = pendingDeletion else { return }
                pendingDeletion = nil
                Task {
                    if await viewModel.delete(id: target.id) { selected = nil }
                }
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("\(pendingDeletion?.carNo ?? "") 등록을 삭제할까요?")
        }
    }

    private var conditionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("조회 조건", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작일", selection: $viewModel.from, displayedComponents: .date)
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료일", selection: $viewModel.to, displayedComponents: .date)

                Button { Task { await viewModel.search() } } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Label("조회", systemImage: "magnifyingglass").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
    }

    private func row(_ booking: VisitorCarBooking) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.carNo)
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Text(periodText(booking))
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                Spacer(minLength: 0)
                if !booking.insertType.label.isEmpty {
                    Text(booking.insertType.label)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VehicleTheme.tileFill, in: Capsule())
                        .foregroundStyle(VehicleTheme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private func detailSheet(_ booking: VisitorCarBooking) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GlassTokens.cardSpacing) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow("차량번호", booking.carNo)
                            detailRow("방문 기간", periodText(booking))
                            detailRow("등록구분", booking.insertType.label)
                            detailRow("방문사유", booking.visitReason.isEmpty ? "—" : booking.visitReason)
                            detailRow("등록자", booking.registrant)
                        }
                    }

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(VehicleTheme.danger)
                    }

                    Button(role: .destructive) {
                        pendingDeletion = booking
                    } label: {
                        Text("삭제")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(VehicleTheme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(VehicleTheme.danger)
                    }
                    .buttonStyle(.plain)

                    // 웹 화면에 「입차 후 수정/삭제 불가능」이라 적혀 있다. **앱이 그 조건을
                    // 판정하지 않는다** — 흉내 내면 서버 규칙과 갈라진다. 보내고 거절당하면 띄운다.
                    Text("입차한 뒤에는 수정·삭제가 거절될 수 있습니다.")
                        .font(.caption2)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                .padding(GlassTokens.cardPadding)
            }
            .glassScreenBackground()
            .navigationTitle("등록 상세")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }

    /// 서버가 시각을 `00:00:00`/`23:59:59`로 채워 준다 — 그때는 날짜만 적는다(웹과 같다).
    private func periodText(_ booking: VisitorCarBooking) -> String {
        let start = VisitorCarDateFormat.day.string(from: booking.startDate)
        let end = VisitorCarDateFormat.day.string(from: booking.endDate)
        return start == end ? start : "\(start) ~ \(end)"
    }
}

#Preview {
    NavigationStack { VisitorCarBookingsView() }
}
