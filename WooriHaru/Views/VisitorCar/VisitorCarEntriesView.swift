// **`Combine`을 직접 들인다.** 아래 `ticker`가 `Publishers.Autoconnect`를 값으로 갖는데,
// `@State` 매크로가 펼쳐 만드는 저장 프로퍼티는 그 타입 이름을 이 파일 안에서 다시 적는다
// — SwiftUI가 재수출해 주는 것만으로는 매크로가 만든 파일이 타입을 못 찾는다.
import Combine
import SwiftUI

/// 우리 세대 차량의 입출차 현황.
///
/// **아직 안 나간 차는 주차시간이 흐른다** — 화면이 떠 있는 동안 1분마다 다시 그린다.
struct VisitorCarEntriesView: View {
    @State private var viewModel = VisitorCarEntriesViewModel()

    /// 1분이면 족하다. 화면에 분 단위까지만 적는다.
    /// **`@State`다.** `let`이면 부모가 뷰 구조체를 다시 만들 때마다(예: 형제 상태 변경으로
    /// 다시 그려질 때) 타이머가 새로 생겨 60초 카운트다운이 초기화된다 — 「흐르는 주차시간」이
    /// 이 화면의 존재 이유인데 그 시계가 뷰 갱신에 끌려다니면 안 된다.
    @State private var ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                conditionCard

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(Color.slate500)
                            Text("입출차 내역이 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(Color.slate500)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(viewModel.entries) { entry in
                        row(entry)
                    }
                    if viewModel.hasMore {
                        Button { Task { await viewModel.loadMore() } } label: {
                            Text("더 보기")
                                .font(.subheadline)
                                .foregroundStyle(Color.blue600)
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
        .navigationTitle("차량 진입 현황")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
        .onReceive(ticker) { _ in viewModel.tick() }
    }

    private var conditionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("조회 조건", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                    .foregroundStyle(Color.slate900)

                DatePicker("시작", selection: $viewModel.from, displayedComponents: [.date, .hourAndMinute])
                Divider()
                DatePicker("종료", selection: $viewModel.to, displayedComponents: [.date, .hourAndMinute])

                Button { Task { await viewModel.search() } } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().tint(Color.white)
                        } else {
                            Label("조회", systemImage: "magnifyingglass").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color.blue600, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .font(.subheadline)
            .foregroundStyle(Color.slate700)
        }
        // 조회 조건 선택기가 기기 시간대가 아니라 한국 시각으로 뜨고 움직이게 한다.
        .seoulDatePickerEnvironment()
    }

    private func row(_ entry: VisitorCarEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.carNo)
                        .font(.headline)
                        .foregroundStyle(Color.slate900)
                    Spacer(minLength: 0)
                    if let status = entry.status {
                        Text(status.label)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                // 아직 안 나간 차만 강조한다 — 나머지는 지난 일이다.
                                (status.isParked ? Color.blue600.opacity(0.20) : Color.slate500.opacity(0.10)),
                                in: Capsule()
                            )
                            .foregroundStyle(status.isParked ? Color.blue600 : Color.slate700)
                    }
                }

                HStack {
                    Text("입차 \(VisitorCarDateFormat.second.string(from: entry.inDate))")
                    Spacer(minLength: 0)
                    Text(VisitorCarEntriesViewModel.parkingText(seconds: entry.parkingSeconds(now: viewModel.now)))
                }
                .font(.caption)
                .foregroundStyle(Color.slate500)

                if let outDate = entry.outDate {
                    Text("출차 \(VisitorCarDateFormat.second.string(from: outDate))")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }
            }
        }
    }
}
