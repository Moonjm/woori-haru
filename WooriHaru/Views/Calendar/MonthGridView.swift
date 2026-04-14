import SwiftUI

struct MonthGridView: View {
    let monthData: MonthData
    let onSelectDate: (Date) -> Void

    /// 기본 셀 높이(default size category) — CalendarView.monthTotalHeight 계산의 기준.
    /// 이 값이 바뀌면 CalendarView의 `monthCellHeight` 기본값도 자동으로 따라온다.
    static let cellHeightBase: CGFloat = 120

    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = MonthGridView.cellHeightBase
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(monthData.cells, id: \.id) { cell in
                let dateStr = cell.date.dateString
                let displayData = DayCellDisplayData(
                    records: cell.isCurrentMonth ? (monthData.records[dateStr] ?? []) : [],
                    partnerRecords: cell.isCurrentMonth ? (monthData.partnerRecords[dateStr] ?? []) : [],
                    holidays: cell.isCurrentMonth ? (monthData.holidays[dateStr] ?? []) : [],
                    pairEvents: cell.isCurrentMonth ? (monthData.pairEvents[dateStr] ?? []) : [],
                    birthdays: cell.isCurrentMonth ? (monthData.birthdayMap[dateStr] ?? []) : []
                )
                DayCellView(
                    date: cell.date,
                    displayData: displayData,
                    overeatLevel: cell.isCurrentMonth ? monthData.overeats[dateStr] : nil,
                    isCurrentMonth: cell.isCurrentMonth,
                    onTap: { onSelectDate(cell.date) }
                )
                .frame(height: cellHeight)
            }
        }
        .background(.white)
        .overlay {
            GridLinesOverlay(
                rows: monthData.cells.count / 7,
                cellHeight: cellHeight
            )
        }
    }
}

// MARK: - Grid Lines Overlay

private struct GridLinesOverlay: View {
    let rows: Int
    let cellHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let colWidth = geo.size.width / 7

            // Vertical lines
            ForEach(1..<7, id: \.self) { col in
                Rectangle()
                    .fill(Color.slate200.opacity(0.4))
                    .frame(width: 0.5)
                    .position(x: colWidth * CGFloat(col), y: geo.size.height / 2)
            }

            // Horizontal lines
            ForEach(1..<rows, id: \.self) { row in
                Rectangle()
                    .fill(Color.slate200.opacity(0.4))
                    .frame(height: 0.5)
                    .position(x: geo.size.width / 2, y: cellHeight * CGFloat(row))
            }
        }
        .allowsHitTesting(false)
    }
}
