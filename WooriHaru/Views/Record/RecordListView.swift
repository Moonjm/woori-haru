import SwiftUI

struct RecordListView: View {
    let records: [DailyRecord]
    let partnerRecords: [DailyRecord]
    let partnerName: String
    let isPaired: Bool
    let onDelete: (DailyRecord) -> Void
    let onTap: (DailyRecord) -> Void

    private var togetherRecords: [DailyRecord] {
        records.filter(\.together) + partnerRecords.filter(\.together)
    }

    private var myRecords: [DailyRecord] {
        if isPaired {
            return records.filter { !$0.together }
        } else {
            return records
        }
    }

    private var partnerSoloRecords: [DailyRecord] {
        partnerRecords.filter { !$0.together }
    }

    var body: some View {
        if records.isEmpty && partnerRecords.isEmpty {
            Text("기록이 없습니다")
                .font(.subheadline)
                .foregroundStyle(Color.slate400)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Together section
                if isPaired && !togetherRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("\u{1F46B}")
                            Text("같이 한 것")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.blue600)
                        }

                        VStack(spacing: 6) {
                            ForEach(togetherRecords) { record in
                                let isMine = records.contains { $0.id == record.id }
                                RecordRow(record: record, showDelete: isMine, onDelete: { onDelete(record) })
                                    .onTapGesture { if isMine { onTap(record) } }
                                    .opacity(isMine ? 1.0 : 0.7)
                            }
                        }
                    }
                }

                // My records
                if !myRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if isPaired {
                            Text("나의 기록")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.slate600)
                        }

                        VStack(spacing: 6) {
                            ForEach(myRecords) { record in
                                RecordRow(record: record, showDelete: true, onDelete: { onDelete(record) })
                                    .onTapGesture { onTap(record) }
                            }
                        }
                    }
                }

                // Partner records (read-only)
                if isPaired && !partnerSoloRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(partnerName)의 기록")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.slate500)

                        VStack(spacing: 6) {
                            ForEach(partnerSoloRecords) { record in
                                RecordRow(record: record, showDelete: false, onDelete: {})
                                    .opacity(0.7)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RecordRow: View {
    let record: DailyRecord
    let showDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(record.category.emoji)
                .font(.subheadline)

            HStack(spacing: 6) {
                Text(record.category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.slate700)

                if let memo = record.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.subheadline)
                        .foregroundStyle(Color.slate500)
                }
            }

            Spacer()

            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.red400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 0
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let resultWidth = maxWidth > 0 ? maxWidth : x - spacing
        return (CGSize(width: resultWidth, height: y + rowHeight), positions)
    }
}
