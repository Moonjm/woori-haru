import SwiftUI

struct MonthGridView: View {
    let monthData: MonthData
    let records: [String: [DailyRecord]]
    let partnerRecords: [String: [DailyRecord]]
    let overeats: [String: OvereatLevel]
    let holidays: [String: [String]]
    let pairEvents: [String: [PairEvent]]
    let birthdayMap: [String: [(emoji: String, label: String)]]
    let onSelectDate: (Date) -> Void

    private static let cellHeight: CGFloat = 120
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(monthData.cells, id: \.id) { cell in
                let dateStr = cell.date.dateString
                DayCellView(
                    date: cell.date,
                    records: cell.isCurrentMonth ? (records[dateStr] ?? []) : [],
                    partnerRecords: cell.isCurrentMonth ? (partnerRecords[dateStr] ?? []) : [],
                    overeatLevel: cell.isCurrentMonth ? overeats[dateStr] : nil,
                    holidays: cell.isCurrentMonth ? (holidays[dateStr] ?? []) : [],
                    pairEvents: cell.isCurrentMonth ? (pairEvents[dateStr] ?? []) : [],
                    birthdays: cell.isCurrentMonth ? (birthdayMap[dateStr] ?? []) : [],
                    isCurrentMonth: cell.isCurrentMonth,
                    onTap: { onSelectDate(cell.date) }
                )
                .frame(height: Self.cellHeight)
            }
        }
        .background(.white)
        .overlay {
            GridLinesOverlay(
                rows: monthData.cells.count / 7,
                cellHeight: Self.cellHeight
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
