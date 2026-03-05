import SwiftUI

private let pickerDarkBg = Color(red: 0.15, green: 0.15, blue: 0.17)

struct CalendarHeaderView: View {
    let monthLabel: String
    let isPickerOpen: Bool
    let onMenuTap: () -> Void
    let onMonthTap: () -> Void
    let onSearchTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundStyle(isPickerOpen ? .white.opacity(0.8) : Color.slate700)
            }

            Button(action: onMonthTap) {
                HStack(spacing: 6) {
                    Text(monthLabel)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(isPickerOpen ? .white : Color.slate900)
                    Image(systemName: isPickerOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPickerOpen ? .white.opacity(0.6) : Color.slate400)
                }
            }

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(isPickerOpen ? .white.opacity(0.8) : Color.slate700)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isPickerOpen ? pickerDarkBg : .white)
    }
}
