import SwiftUI

/// 최근 며칠의 상태를 하루 한 줄씩 가로 띠로. **위가 가장 오래된 날, 아래가 오늘이다** —
/// 아래로 읽어 내려가면 지금에 닿는다.
///
/// **오늘 행은 지금 이후가 빈칸이다.** 아직 오지 않은 시간을 색으로 칠하지 않는다.
///
/// 실측(2026-08-19)으로 최근 7일은 오프라인이 131시간(78%)이라 화면 대부분이 회색이다.
/// 그게 사실이므로 그대로 그린다.
struct StateTimelineChart: View {
    private let days: Int
    private let from: Date
    /// 행별로 미리 갈라 둔다 — 매 프레임 `filter`를 7번 도는 것을 피한다.
    /// 입력이 이미 레이어 순으로 정렬돼 있어 넣는 순서가 곧 덧칠 순서다.
    private let rows: [[TimelineBar]]

    @Environment(\.displayScale) private var displayScale

    private let rowHeight: CGFloat = 14
    private let rowSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 34

    init(bars: [TimelineBar], days: Int, from: Date) {
        self.days = max(0, days)
        self.from = from
        var rows = Array(repeating: [TimelineBar](), count: max(0, days))
        // **행 밖의 막대를 버리는 것은 일부러다.** 서버의 `days`와 `from..to` 창이 어긋나면
        // 인덱스가 범위를 넘는데, 그때 무너지는 것보다 그 막대를 안 그리는 편이 낫다.
        for bar in bars where bar.dayIndex >= 0 && bar.dayIndex < rows.count {
            rows[bar.dayIndex].append(bar)
        }
        self.rows = rows
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 \(days)일")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                VStack(spacing: rowSpacing) {
                    ForEach(0..<days, id: \.self) { dayIndex in
                        row(dayIndex)
                    }
                }

                hourAxis
                legend
            }
        }
    }

    private func row(_ dayIndex: Int) -> some View {
        HStack(spacing: 6) {
            Text(Self.dayFormatter.string(from: date(dayIndex)))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
                .frame(width: labelWidth, alignment: .trailing)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.slate100)
                    ForEach(Array(rows[dayIndex].enumerated()), id: \.offset) { _, bar in
                        Rectangle()
                            .fill(Self.color(bar.kind))
                            // **최소 폭을 두지 않는다.** 바닥값을 깔면 짧은 구간이 실제보다
                            // 길어 보이는 띠가 된다 — 「한쪽만으로 그린 막대는 거짓말이다」와
                            // 같은 규칙이다. 화면의 물리적 하한인 1픽셀만 둔다.
                            .frame(width: max(1 / displayScale, width * (bar.end - bar.start)))
                            .offset(x: width * bar.start)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: rowHeight)
        }
        // 구간 168개를 하나씩 읽게 만들지 않는다 — 하루가 한 정거장이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(dayIndex))
    }

    private var hourAxis: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: labelWidth)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(hour == 0 ? "0시" : "\(hour)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("24")
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(Color.slate400)
        }
        .accessibilityHidden(true)
    }

    /// **`asleep`을 빼지 않는다.** 최근 7일 표본에는 0건이지만 2026년에도 월 1~4건씩 있었다.
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
        .foregroundStyle(Color.slate500)
        .accessibilityHidden(true)
    }

    // MARK: - 값

    private func date(_ dayIndex: Int) -> Date {
        from.addingTimeInterval(Double(dayIndex) * StateTimelineMath.secondsPerDay)
    }

    /// 하루를 한 문장으로. 날짜가 먼저다.
    ///
    /// **오프라인·잠자는 중도 온라인과 똑같이 시간으로 읽는다.** 실측상 최근 7일은 오프라인이
    /// 78%라 **가장 흔한 행이 하루 종일 오프라인인 행**인데, 그 행을 「기록 없음」으로 읽으면
    /// 화면은 꽉 찬 회색 띠를 그리는데 소리는 아무것도 없었다고 말한다. 이 저장소에서
    /// 「기록이 없음」과 「그 상태로 있었음」은 다른 말이고, 섞으면 안 된다.
    /// **「기록 없음」은 막대가 정말 하나도 없는 행에만 쓴다.**
    ///
    /// 「주행 N회」는 **세션이 아니라 막대를 센다** — 자정을 넘긴 주행 하나는 두 행으로 쪼개져
    /// 양쪽 날에 한 번씩 잡힌다. 하루치 라벨이 말해야 하는 것이 바로 그 「이 날 있었던 횟수」다.
    private func rowLabel(_ dayIndex: Int) -> String {
        let bars = rows[dayIndex]
        var parts = [Self.voiceOverFormatter.string(from: date(dayIndex))]

        for (kind, label) in Self.spokenStates {
            let hours = bars
                .filter { $0.kind == kind }
                .reduce(0.0) { $0 + ($1.end - $1.start) } * 24
            // 0.05시간(3분) 미만은 말하지 않는다 — 「0.0시간」은 있으나 마나다.
            if hours >= 0.05 { parts.append("\(label) \(String(format: "%.1f", hours))시간") }
        }

        let drives = bars.filter { $0.kind == .driving }.count
        let charges = bars.filter { $0.kind == .charging }.count
        if drives > 0 { parts.append("주행 \(drives)회") }
        if charges > 0 { parts.append("충전 \(charges)회") }

        if parts.count == 1 {
            // 막대가 아예 없는 행만 「기록 없음」이다. 3분 미만 조각만 있는 행은
            // 「기록이 없음」이 아니라 「말할 만큼 길지 않음」이라 다르게 말한다.
            parts.append(bars.isEmpty ? "기록 없음" : "짧은 구간뿐")
        }
        return parts.joined(separator: ", ")
    }

    private static func color(_ kind: TimelineKind) -> Color {
        switch kind {
        case .asleep: Color.slate200
        case .offline: Color.slate300
        case .online: Color.blue300
        case .driving: Color.blue600
        case .charging: Color.green600
        }
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

    /// **KST로 찍는다.** `from`은 `VehicleFormat.parseKST`가 KST 벽시계로 읽은 값이라,
    /// 기기 시간대로 찍으면 시차만큼 날짜가 밀린다.
    private static let dayFormatter = kstFormatter("M/d")
    private static let voiceOverFormatter = kstFormatter("M월 d일")

    private static func kstFormatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = pattern
        return formatter
    }
}

#Preview("타임라인") {
    let response = StateTimelineResponse(
        days: 3, from: "2026-08-17T00:00:00", to: "2026-08-19T12:00:00",
        states: [
            StateSegment(state: "offline", from: "2026-08-17T00:00:00", to: "2026-08-17T07:30:00"),
            StateSegment(state: "online", from: "2026-08-17T07:30:00", to: "2026-08-17T09:10:00"),
            StateSegment(state: "asleep", from: "2026-08-17T09:10:00", to: "2026-08-18T06:00:00"),
            StateSegment(state: "online", from: "2026-08-18T06:00:00", to: "2026-08-18T08:00:00"),
            StateSegment(state: "offline", from: "2026-08-18T08:00:00", to: "2026-08-19T09:00:00"),
            StateSegment(state: "online", from: "2026-08-19T09:00:00", to: "2026-08-19T12:00:00")
        ],
        drives: [
            TimeSegment(from: "2026-08-17T07:40:00", to: "2026-08-17T08:10:00"),
            TimeSegment(from: "2026-08-19T09:20:00", to: "2026-08-19T09:50:00")
        ],
        charges: [TimeSegment(from: "2026-08-18T06:10:00", to: "2026-08-18T07:40:00")])

    return StateTimelineChart(bars: StateTimelineMath.bars(response),
                              days: response.days,
                              from: VehicleFormat.parseKST(response.from) ?? .now)
        .padding(16)
        .background(Color.slate50)
}
