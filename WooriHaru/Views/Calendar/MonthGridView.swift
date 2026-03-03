import SwiftUI

struct MonthGridView: View {
    let monthData: MonthData
    let records: [String: [DailyRecord]]
    let overeats: [String: OvereatLevel]
    let holidays: [String: [String]]
    let onSelectDate: (Date) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0.5), count: 7), spacing: 0.5) {
            ForEach(monthData.cells) { cell in
                DayCellView(
                    date: cell.date,
                    records: cell.isCurrentMonth ? (records[cell.date.dateString] ?? []) : [],
                    overeatLevel: cell.isCurrentMonth ? overeats[cell.date.dateString] : nil,
                    holidays: cell.isCurrentMonth ? (holidays[cell.date.dateString] ?? []) : [],
                    isCurrentMonth: cell.isCurrentMonth,
                    onTap: { onSelectDate(cell.date) }
                )
            }
        }
        .background(Color.slate200.opacity(0.5))
    }
}
