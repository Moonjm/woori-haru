import Foundation
import Observation

struct CategoryStat: Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let count: Int
    let ratio: Double  // 0.0 ~ 1.0
}

enum RecordFilter: String, CaseIterable {
    case all = "전체"
    case together = "같이"
    case solo = "혼자"
}

@MainActor
@Observable
final class StatsViewModel {
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date()) // 현재 월; 0 = 전체
    var filterType: RecordFilter = .all
    var stats: [CategoryStat] = []
    var totalCount: Int = 0
    var isPaired: Bool = false
    var isLoading = false
    var errorMessage: String?

    private let recordService = RecordService()
    private let pairService = PairService()

    var periodLabel: String {
        if selectedMonth == 0 { return "\(selectedYear)년" }
        return "\(selectedYear)년 \(selectedMonth)월"
    }

    func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = Date.monthRange(year: selectedYear, month: selectedMonth)

        do {
            let pairInfo = try? await pairService.getStatus()
            isPaired = pairInfo?.status == .connected

            let myRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)

            var partnerRecords: [DailyRecord] = []
            if isPaired {
                partnerRecords = (try? await pairService.fetchPartnerRecords(from: fromStr, to: toStr)) ?? []
            }

            let filtered: [DailyRecord]
            switch filterType {
            case .all:
                filtered = myRecords + partnerRecords.filter { $0.together }
            case .together:
                filtered = myRecords.filter { $0.together } + partnerRecords.filter { $0.together }
            case .solo:
                filtered = myRecords.filter { !$0.together }
            }

            var countMap: [Int: (emoji: String, name: String, count: Int)] = [:]
            for record in filtered {
                let cat = record.category
                if let existing = countMap[cat.id] {
                    countMap[cat.id] = (cat.emoji, cat.name, existing.count + 1)
                } else {
                    countMap[cat.id] = (cat.emoji, cat.name, 1)
                }
            }

            totalCount = filtered.count
            stats = countMap.map { (id, val) in
                CategoryStat(id: id, emoji: val.emoji, name: val.name, count: val.count,
                            ratio: totalCount > 0 ? Double(val.count) / Double(totalCount) : 0)
            }.sorted { $0.count > $1.count }

        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }

}
