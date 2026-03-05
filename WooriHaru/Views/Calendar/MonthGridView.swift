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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(weekRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, cell in
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
                        if columnIndex < row.count - 1 {
                            Divider()
                                .frame(width: 0.5)
                                .background(Color.slate200.opacity(0.35))
                        }
                    }
                }
                if rowIndex < weekRows.count - 1 {
                    Divider()
                        .background(Color.slate200.opacity(0.35))
                }
            }
        }
        .background(.white)
    }

    private var weekRows: [[MonthData.DayCell]] {
        stride(from: 0, to: monthData.cells.count, by: 7).map { start in
            Array(monthData.cells[start..<min(start + 7, monthData.cells.count)])
        }
    }
}
