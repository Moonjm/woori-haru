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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0.5), count: 7), spacing: 0.5) {
            ForEach(monthData.cells) { cell in
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
            }
        }
        .background(Color.slate200.opacity(0.5))
    }
}
