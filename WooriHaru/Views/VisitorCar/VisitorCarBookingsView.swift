import SwiftUI

/// 등록 내역 조회. 조건 카드 + 결과 목록 + 상세 시트(수정·삭제).
struct VisitorCarBookingsView: View {
    @State private var viewModel = VisitorCarBookingsViewModel()
    @State private var selected: VisitorCarBooking?
    @State private var pendingDeletion: VisitorCarBooking?

    @State private var isEditing = false
    @State private var editCarNo = ""
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editReason = ""

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
        // 시트가 닫히면 편집 모드도 되돌린다 — 다음에 다른 건을 열었을 때 이전 편집 흔적이 남지 않게.
        .onChange(of: selected) { if selected == nil { isEditing = false } }
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
                        if isEditing {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("차량번호", text: $editCarNo)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                                DatePicker("시작일", selection: $editStart, displayedComponents: .date)
                                Divider().overlay(VehicleTheme.cardStroke)
                                DatePicker("종료일", selection: $editEnd, displayedComponents: .date)

                                TextField("방문사유 (선택)", text: $editReason)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                detailRow("차량번호", booking.carNo)
                                detailRow("방문 기간", periodText(booking))
                                detailRow("등록구분", booking.insertType.label)
                                detailRow("방문사유", booking.visitReason.isEmpty ? "—" : booking.visitReason)
                                detailRow("등록자", booking.registrant)
                            }
                        }
                    }

                    if isEditing {
                        Button {
                            Task {
                                let ok = await viewModel.update(
                                    id: booking.id,
                                    carNo: editCarNo,
                                    startDate: editStart,
                                    endDate: editEnd,
                                    visitReason: editReason
                                )
                                if ok {
                                    isEditing = false
                                    selected = nil
                                }
                            }
                        } label: {
                            Text("저장")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(VehicleTheme.background)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            // 편집을 시작할 때 현재 값을 옮겨 담는다.
                            editCarNo = booking.carNo
                            editStart = booking.startDate
                            editEnd = booking.endDate
                            editReason = booking.visitReason
                            isEditing = true
                        } label: {
                            Text("수정")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(VehicleTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
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
        // **시트 자신의 presentation context에서 띄운다.** 바깥 뷰에 체이닝하면 이미 시트가
        // 올라간 상태에서 시스템 alert를 띄우는 셈이 되어, iOS 버전·타이밍에 따라 시트 위에
        // 뜨거나 조용히 삼켜질 수 있다(SwiftUI/UIKit의 알려진 presentation-stacking 함정).
        .alert(
            "등록 내역 삭제",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in if !isPresented { pendingDeletion = nil } }
            )
        ) {
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
