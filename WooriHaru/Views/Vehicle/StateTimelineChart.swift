import SwiftUI

/// 최근 몇 시간의 상태를 **한 줄**로. **오른쪽 끝이 「지금」이다** — 서버가 `to`를 요청 시각으로
/// 주고 자정에 맞추지 않는다.
///
/// **4단계의 7행 격자를 버렸다.** 한 행이 화면 폭의 1/7이면 밤새 충전 한 건이 손톱만 하게
/// 찍힌다. 같은 폭에 24시간만 놓으면 실측 22개 구간이 들어가 하나가 7배 넓어진다.
///
/// 눈금은 **절대 시각**이다. 이 그림이 답하려는 질문이 「밤새 충전이 **언제** 걸렸나」이므로
/// 「-12시간」 같은 상대 표기로는 읽을 수 없다.
struct StateTimelineChart: View {
    private let bars: [TimelineBar]
    private let from: Date
    private let to: Date

    @Environment(\.displayScale) private var displayScale

    private let barHeight: CGFloat = 24
    private let tickLabelWidth: CGFloat = 30

    init(bars: [TimelineBar], from: Date, to: Date) {
        // 입력이 이미 레이어 순으로 정렬돼 있어 그리는 순서가 곧 덧칠 순서다. 다시 정렬하지 않는다.
        self.bars = bars
        self.from = from
        self.to = to
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("최근 \(hours)시간")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                    // 띠의 접근성 이름이 같은 말을 이미 하고 있다 — 제목은 눈을 위한 장식이다.
                    .accessibilityHidden(true)

                strip
                axis
                legend
            }
        }
    }

    private var strip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                // **트랙은 어느 상태보다도 뚜렷하게 어두워야 한다.** 막대가 이 위에 겹쳐
                // 칠해지므로, 트랙이 가장 어두운 상태(`asleep`)와 가까우면 「자는 중」과
                // 「기록 없음」이 안 갈린다. 그 관계는 `VehicleThemeTests`가 붙잡는다.
                Rectangle().fill(VehicleTheme.timelineTrack)
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Rectangle()
                        .fill(Self.color(bar.kind))
                        // **최소 폭을 두지 않는다.** 바닥값을 깔면 짧은 구간이 실제보다 길어
                        // 보이는 띠가 된다 — 「한쪽만으로 그린 막대는 거짓말이다」와 같은 규칙이다.
                        // 화면의 물리적 하한인 1픽셀만 둔다.
                        .frame(width: max(1 / displayScale, width * (bar.end - bar.start)))
                        .offset(x: width * bar.start)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: barHeight)
        // 구간을 하나씩 읽게 만들지 않는다 — 띠 전체가 한 정거장이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stripLabel)
    }

    /// 4시간 간격의 정각과, 오른쪽 끝의 「지금」.
    ///
    /// **정각을 고르는 산술은 `StateTimelineMath.ticks`가 한다.** 여기 남은 것은 폭을 알아야
    /// 정할 수 있는 일 하나 — 어느 눈금을 버릴지다. 그 판정은 `StateTimelineMath.visibleTicks`가
    /// 한다(왼쪽으로 삐져나오는 것 · 앞 눈금과 겹치는 것 · 「지금」과 겹치는 것을 한 번에 거른다).
    /// 순수 함수로 뺀 이유는 폭이 길어지는 범위(서버가 자정에 맞춘 145~168시간)에서 눈금이
    /// 서른 몇 개가 되어도 테스트가 겹침을 잡게 하려는 것이다.
    private var axis: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(StateTimelineMath.visibleTicks(
                    StateTimelineMath.ticks(from: from, to: to),
                    width: width, labelWidth: tickLabelWidth
                ).enumerated()), id: \.offset) { _, tick in
                    Text(Self.hourFormatter.string(from: tick.date))
                        .frame(width: tickLabelWidth)
                        .offset(x: width * tick.fraction - tickLabelWidth / 2)
                }
                Text("지금")
                    .fontWeight(.bold)
                    .frame(width: tickLabelWidth, alignment: .trailing)
                    .offset(x: width - tickLabelWidth)
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(VehicleTheme.textTertiary)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    /// **`asleep`을 빼지 않는다.** 최근 표본에 0건이어도 2026년에 월 1~4건씩 있었다.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Array(Self.legendItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(item.kind))
                        .frame(width: 8, height: 8)
                    Text(item.label)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .foregroundStyle(VehicleTheme.textSecondary)
        .accessibilityHidden(true)
    }

    // MARK: - 값

    private var span: TimeInterval { to.timeIntervalSince(from) }

    /// **띠 길이를 `to − from`에서 낸다.** 서버가 범위 길이를 따로 싣지 않으므로,
    /// 그린 범위와 말하는 길이가 갈릴 자리가 아예 없다.
    private var hours: Int { StateTimelineMath.hours(from: from, to: to) }

    /// 띠 전체를 한 문장으로.
    ///
    /// **오프라인·잠자는 중도 온라인과 똑같이 시간으로 읽는다.** 실측상 대부분이 오프라인이라
    /// 그것을 빼고 읽으면 화면은 꽉 찬 회색 띠를 그리는데 소리는 아무것도 없었다고 말한다.
    /// 「기록 없음」은 막대가 정말 하나도 없을 때만 쓴다.
    private var stripLabel: String {
        var parts = ["최근 \(hours)시간"]

        for (kind, label) in Self.spokenStates {
            let ratio = bars.filter { $0.kind == kind }.reduce(0.0) { $0 + ($1.end - $1.start) }
            // **그려진 범위에서 낸다.** 반올림한 `hours`로 곱하면 분 단위로 어긋난 범위에서
            // 띠는 범위대로 그려지는데 소리만 다른 길이를 말한다.
            let hoursSpent = ratio * (span / 3600)
            // 0.05시간(3분) 미만은 말하지 않는다 — 「0.0시간」은 있으나 마나다.
            if hoursSpent >= 0.05 { parts.append("\(label) \(String(format: "%.1f", hoursSpent))시간") }
        }

        let drives = bars.filter { $0.kind == .driving }.count
        let charges = bars.filter { $0.kind == .charging }.count
        if drives > 0 { parts.append("주행 \(drives)회") }
        if charges > 0 { parts.append("충전 \(charges)회") }

        if parts.count == 1 {
            // 3분 미만 조각만 있는 것은 「기록이 없음」이 아니라 「말할 만큼 길지 않음」이다.
            parts.append(bars.isEmpty ? "기록 없음" : "짧은 구간뿐")
        }
        return parts.joined(separator: ", ")
    }

    /// **색을 여기서 고르지 않는다.** 띠와 범례가 같은 함수를 부르므로 한 곳에만 적혀야 하고,
    /// 다섯이 서로 다른지는 `VehicleThemeTests`가 지킨다.
    private static func color(_ kind: TimelineKind) -> Color {
        VehicleTheme.color(for: kind)
    }

    /// VoiceOver가 시간으로 읽는 상태 셋. 범례와 같은 순서다 — 눈으로 보는 순서와
    /// 귀로 듣는 순서가 갈리면 같은 그림을 두 가지로 설명하는 셈이 된다.
    private static let spokenStates: [(kind: TimelineKind, label: String)] = [
        (.online, "온라인"), (.offline, "오프라인"), (.asleep, "잠자는 중")
    ]

    private static let legendItems: [(kind: TimelineKind, label: String)] = [
        (.online, "온라인"), (.offline, "오프라인"), (.asleep, "잠자는 중"),
        (.driving, "주행"), (.charging, "충전")
    ]

    private static let kst = TimeZone(identifier: "Asia/Seoul") ?? .current

    /// **KST로 찍는다.** `from`·`to`는 `VehicleFormat.parseKST`가 KST 벽시계로 읽은 값이라,
    /// 기기 시간대로 찍으면 시차만큼 어긋난다.
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = kst
        formatter.dateFormat = "H시"
        return formatter
    }()
}

#Preview("타임라인") {
    let response = StateTimelineResponse(
        from: "2026-08-18T13:00:00", to: "2026-08-19T13:00:00",
        states: [
            StateSegment(state: "offline", from: "2026-08-18T13:00:00", to: "2026-08-18T18:30:00"),
            StateSegment(state: "online", from: "2026-08-18T18:30:00", to: "2026-08-18T19:40:00"),
            StateSegment(state: "asleep", from: "2026-08-18T19:40:00", to: "2026-08-19T06:00:00"),
            StateSegment(state: "offline", from: "2026-08-19T06:00:00", to: "2026-08-19T09:00:00"),
            StateSegment(state: "online", from: "2026-08-19T09:00:00", to: "2026-08-19T13:00:00")
        ],
        drives: [
            TimeSegment(from: "2026-08-18T18:40:00", to: "2026-08-18T19:10:00"),
            TimeSegment(from: "2026-08-19T09:20:00", to: "2026-08-19T09:50:00")
        ],
        charges: [TimeSegment(from: "2026-08-18T22:10:00", to: "2026-08-19T02:40:00")])

    return StateTimelineChart(bars: StateTimelineMath.bars(response),
                              from: VehicleFormat.parseKST(response.from) ?? .now,
                              to: VehicleFormat.parseKST(response.to) ?? .now)
        .padding(16)
        .background(VehicleTheme.background)
        .environment(\.vehicleDark, true)
}
