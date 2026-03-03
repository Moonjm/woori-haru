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
                if let date = cell.date {
                    DayCellView(
                        date: date,
                        records: records[cell.id] ?? [],
                        overeatLevel: overeats[cell.id],
                        holidays: holidays[cell.id] ?? [],
                        onTap: { onSelectDate(date) }
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .background(Color.slate200.opacity(0.5))
    }
}
