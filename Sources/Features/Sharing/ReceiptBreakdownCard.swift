import SwiftUI

/// A breakdown drawn as a torn receipt slip over the receipt's colors, for sharing as an image.
/// It is built from plain views because `ImageRenderer` can't draw lists, glass, or shaders.
struct ReceiptBreakdownCard: View {
  private static let paper = Color(red: 1, green: 0.995, blue: 0.984)

  let breakdown: ReceiptBreakdown

  var body: some View {
    VStack(spacing: 16) {
      slip
      footer
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 18)
    .background { backdrop }
  }

  private var slip: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      PerforationLine()
      switch breakdown.content {
      case .person(let share):
        PersonBreakdown(share: share, breakdown: breakdown, accent: accent)
      case .group(let shares):
        GroupBreakdown(shares: shares, breakdown: breakdown, accent: accent)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 24)
    .padding(.bottom, 24 + ReceiptSlipShape.toothHeight)
    .background {
      ReceiptSlipShape()
        .fill(Self.paper)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text(breakdown.merchantTitle)
          .font(.title2.weight(.bold))
          .lineLimit(2)
        Text(breakdown.purchaseDate, format: .dateTime.month(.wide).day().year())
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Image(systemName: "receipt")
        .font(.title3.weight(.semibold))
        .foregroundStyle(accent)
    }
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "receipt")
      Text("Split with Open Receipt")
    }
    .font(.footnote.weight(.medium))
    .foregroundStyle(.black.opacity(0.45))
  }

  private var backdrop: some View {
    let colors = breakdown.style.colors(for: .light)
    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
      .overlay {
        RadialGradient(
          colors: [breakdown.style.secondary.accentColor(for: .light).opacity(0.22), .clear],
          center: .bottomTrailing,
          startRadius: 0,
          endRadius: 420)
      }
  }

  private var accent: Color {
    breakdown.style.accentColor(for: breakdown.accentScheme)
  }
}

private struct PersonBreakdown: View {
  let share: ReceiptParticipantShare
  let breakdown: ReceiptBreakdown
  let accent: Color

  var body: some View {
    HStack(spacing: 12) {
      PersonAvatarView(
        name: share.participant.displayName,
        imageData: share.participant.avatarData,
        size: 42)
      VStack(alignment: .leading, spacing: 2) {
        Text(share.participant.displayName)
          .font(.headline)
        Text(share.itemCountText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }

    VStack(alignment: .leading, spacing: 12) {
      ForEach(share.items) { item in
        BreakdownLine(
          title: item.description,
          detail: item.fraction < 1 ? "\(item.fraction.sharePercentText) share" : nil,
          amount: item.amount,
          currency: breakdown.currency)
      }
    }

    if !share.adjustments.isEmpty {
      PerforationLine()
      VStack(alignment: .leading, spacing: 12) {
        ForEach(share.adjustments) { adjustment in
          BreakdownLine(
            title: adjustment.title,
            detail: adjustment.fraction.sharePercentText,
            amount: adjustment.amount,
            currency: breakdown.currency)
        }
      }
    }

    PerforationLine()
    BreakdownTotal(
      title: "Total", amount: share.total, currency: breakdown.currency, accent: accent)
  }
}

private struct GroupBreakdown: View {
  let shares: [ReceiptParticipantShare]
  let breakdown: ReceiptBreakdown
  let accent: Color

  var body: some View {
    let colors = shareColors

    BreakdownTotal(
      title: "Total", amount: breakdown.total, currency: breakdown.currency, accent: accent)

    ShareBar(fractions: fractions, colors: colors)

    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
        row(share, color: colors[index])
      }
    }

    Text(
      breakdown.adjustmentMethod == .proportional
        ? "Tax and tip split proportionally by each person’s item share."
        : "Tax and tip split equally."
    )
    .font(.footnote)
    .foregroundStyle(.secondary)
  }

  private func row(_ share: ReceiptParticipantShare, color: Color) -> some View {
    HStack(spacing: 12) {
      PersonAvatarView(
        name: share.participant.displayName,
        imageData: share.participant.avatarData,
        size: 34
      )
      .overlay(alignment: .bottomTrailing) {
        Circle()
          .fill(color)
          .frame(width: 11, height: 11)
          .overlay(Circle().stroke(.white, lineWidth: 2))
      }
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(share.participant.displayName)
            .font(.subheadline.weight(.semibold))
          if share.participant.source.isCurrentUser {
            Text("Paid")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(accent)
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(accent.opacity(0.12), in: .capsule)
          }
        }
        Text(share.itemCountText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Text(share.total, format: .currency(code: breakdown.currency))
        .font(.subheadline.weight(.semibold).monospacedDigit())
    }
  }

  private var fractions: [Double] {
    let total = shares.reduce(0) { $0 + max($1.total, 0) }
    guard total > 0 else { return shares.map { _ in 1 / Double(shares.count) } }
    return shares.map { max($0.total, 0) / total }
  }

  /// People take the receipt's two colors first, then the rest of the theme palette, in the
  /// palette's bright variants so the bar stays vivid on the paper.
  private var shareColors: [Color] {
    let style = breakdown.style
    let palette =
      [style.primary, style.secondary]
      + ReceiptThemeColor.allCases.filter { $0 != style.primary && $0 != style.secondary }
    return shares.indices.map { palette[$0 % palette.count].accentColor(for: .dark) }
  }
}

private struct BreakdownLine: View {
  let title: String
  let detail: String?
  let amount: Double
  let currency: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title.isEmpty ? "Item" : title)
          .font(.subheadline)
          .lineLimit(2)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Text(amount, format: .currency(code: currency))
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }
}

private struct BreakdownTotal: View {
  let title: String
  let amount: Double
  let currency: String
  let accent: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.headline)
      Spacer(minLength: 12)
      Text(amount, format: .currency(code: currency))
        .font(.title.weight(.bold).monospacedDigit())
        .foregroundStyle(accent)
    }
  }
}

/// Everyone's portion of the total as one segmented bar.
private struct ShareBar: View {
  let fractions: [Double]
  let colors: [Color]

  var body: some View {
    GeometryReader { proxy in
      let spacing: CGFloat = 3
      let available = proxy.size.width - spacing * CGFloat(max(fractions.count - 1, 0))
      HStack(spacing: spacing) {
        ForEach(fractions.indices, id: \.self) { index in
          Rectangle()
            .fill(colors[index])
            .frame(width: max(available * fractions[index], 0))
        }
      }
      .clipShape(.capsule)
    }
    .frame(height: 10)
  }
}

private struct PerforationLine: View {
  var body: some View {
    Line()
      .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
      .foregroundStyle(.black.opacity(0.18))
      .frame(height: 1)
  }

  private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
      Path { path in
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      }
    }
  }
}

/// A slip of receipt paper: rounded at the top, torn into teeth along the bottom.
private struct ReceiptSlipShape: Shape {
  static let toothHeight: CGFloat = 8
  private static let toothWidth: CGFloat = 16
  private static let cornerRadius: CGFloat = 20

  func path(in rect: CGRect) -> Path {
    let radius = Self.cornerRadius
    let toothTop = rect.maxY - Self.toothHeight
    let teeth = max(Int((rect.width / Self.toothWidth).rounded()), 1)
    let toothWidth = rect.width / CGFloat(teeth)

    return Path { path in
      path.move(to: CGPoint(x: rect.minX, y: toothTop))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
      path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
        radius: radius)
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
      path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
        radius: radius)
      path.addLine(to: CGPoint(x: rect.maxX, y: toothTop))
      for tooth in 0..<teeth {
        let right = rect.maxX - CGFloat(tooth) * toothWidth
        path.addLine(to: CGPoint(x: right - toothWidth / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - toothWidth, y: toothTop))
      }
      path.closeSubpath()
    }
  }
}
