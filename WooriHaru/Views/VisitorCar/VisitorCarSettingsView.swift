import SwiftUI

/// 방문차량 설정 — 자주 쓰는 차량 관리와 로그아웃.
///
/// **비밀번호 변경을 넣지 않는다.** 사이트에 경로가 있지만 일 년에 한 번 쓸까 말까라
/// 브라우저로 한다(스펙 비목표).
struct VisitorCarSettingsView: View {
    /// 로그아웃하면 홈이 로그인 카드로 되돌아가야 한다.
    let onLoggedOut: () -> Void

    @State private var store = FrequentCarStore.shared
    @State private var viewModel = VisitorCarHomeViewModel()
    @State private var nickname = ""
    @State private var carNo = ""
    @State private var addError: String?
    @State private var showingLogoutConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                noticeCard
                addCard
                savedCars
                logoutButton
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("방문차량 설정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("로그아웃", isPresented: $showingLogoutConfirm) {
            Button("로그아웃", role: .destructive) {
                Task {
                    await viewModel.logout()
                    onLoggedOut()
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 주차관제 계정을 지웁니다. 다시 쓰려면 로그인해야 합니다.")
        }
    }

    private var noticeCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(VehicleTheme.textTertiary)
                // 참고 앱과 같은 안내다. 서버에 올리지 않는다는 사실을 사용자가 알아야 한다.
                Text("자주 쓰는 차량 정보는 이 기기에만 저장됩니다. 앱을 지우거나 기기를 바꾸면 사라집니다.")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var addCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("차량 추가", systemImage: "bookmark")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                TextField("별칭", text: $nickname)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                TextField("차량번호", text: $carNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                Button {
                    addError = store.add(nickname: nickname, carNo: carNo)
                    if addError == nil {
                        nickname = ""
                        carNo = ""
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var savedCars: some View {
        if !store.cars.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("저장된 차량")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(store.cars) { car in
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "car")
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(car.nickname)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(VehicleTheme.textPrimary)
                                Text(car.carNo)
                                    .font(.caption)
                                    .foregroundStyle(VehicleTheme.textTertiary)
                            }

                            Spacer(minLength: 0)

                            Button { store.remove(id: car.id) } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(VehicleTheme.textTertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(car.nickname) 삭제")
                        }
                    }
                }
            }
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            showingLogoutConfirm = true
        } label: {
            Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(VehicleTheme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(VehicleTheme.danger)
        }
        .buttonStyle(.plain)
    }
}
