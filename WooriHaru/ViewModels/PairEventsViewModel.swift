import Foundation
import Observation

@MainActor
@Observable
final class PairEventsViewModel {

    // MARK: - State

    var events: [PairEvent] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Form State

    var newEmoji: String = ""
    var newTitle: String = ""
    var newDate: Date = .now
    var newRecurring: Bool = false

    // MARK: - Service

    private let pairEventService = PairEventService()

    // MARK: - Actions

    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            events = try await pairEventService.fetchEvents()
        } catch {
            errorMessage = "기념일을 불러오지 못했습니다."
        }
    }

    func createEvent() async {
        let emoji = newEmoji.trimmingCharacters(in: .whitespaces)
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !emoji.isEmpty, !title.isEmpty else {
            errorMessage = "이모지와 제목을 입력해주세요."
            return
        }

        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: newDate)

        let request = PairEventRequest(
            title: title,
            emoji: emoji,
            eventDate: dateStr,
            recurring: newRecurring
        )

        do {
            try await pairEventService.createEvent(request)
            resetForm()
            await loadEvents()
            successMessage = "기념일이 추가되었습니다."
        } catch {
            errorMessage = "기념일 추가에 실패했습니다."
        }
    }

    func deleteEvent(_ event: PairEvent) async {
        errorMessage = nil
        do {
            try await pairEventService.deleteEvent(id: event.id)
            events.removeAll { $0.id == event.id }
        } catch {
            errorMessage = "기념일 삭제에 실패했습니다."
        }
    }

    private func resetForm() {
        newEmoji = ""
        newTitle = ""
        newDate = .now
        newRecurring = false
    }
}
