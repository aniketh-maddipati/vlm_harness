import SwiftUI

/// A progress-bar map of the shoot. Nodes reveal a chapter without moving focus,
/// changing the set, or writing recipes. Pinch on this axis changes time scale only.
/// Ticks name the hour — or the minutes inside it — on both orientations.
struct ElasticChronologyBar: View {
    let chapters: [ShootChapter]
    let activeID: String?
    var orientation: ElasticChronology.AxisOrientation = .horizontal
    var chronological: Bool = true
    let navigate: (String) -> Void

    @State private var scale: CGFloat = ElasticLayout.ChronAxis.unitLength
    @State private var pinchBase: CGFloat = ElasticLayout.ChronAxis.unitLength

    private var placement: ElasticChronology.Placement {
        ElasticChronology.placement(chapters: chapters, chronological: chronological, scale: scale)
    }

    var body: some View {
        let marks = placement
        Group {
            if marks.nodes.isEmpty && marks.ticks.isEmpty {
                Color.clear
            } else {
                GeometryReader { geo in
                    axisScroll(marks: marks, size: geo.size)
                }
                .padding(ElasticLayout.ChronAxis.endPadding)
            }
        }
        .frame(
            width: orientation == .vertical ? ElasticLayout.ChronAxis.verticalBreadth : nil,
            height: orientation == .horizontal ? ElasticLayout.ChronAxis.horizontalBreadth : nil
        )
        .frame(
            maxWidth: orientation == .horizontal ? .infinity : nil,
            maxHeight: orientation == .vertical ? .infinity : nil
        )
        .background(LuminaTokens.Elastic.paper)
        .gesture(axisPinch)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("chronology")
        .accessibilityIdentifier("p0.chronology.axis")
    }

    private var axisPinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = pinchBase * value
                scale = min(max(next, ElasticLayout.ChronAxis.scaleMin), ElasticLayout.ChronAxis.scaleMax)
            }
            .onEnded { _ in
                pinchBase = scale
            }
    }

    @ViewBuilder
    private func axisScroll(marks: ElasticChronology.Placement, size: CGSize) -> some View {
        let axisLength = orientation == .vertical ? size.height : size.width
        let contentLength = max(marks.contentLength, ElasticLayout.ChronAxis.unitLength)
        let contentPx = axisLength * contentLength
        let scroll = orientation == .vertical
            ? Axis.Set.vertical : Axis.Set.horizontal

        ScrollViewReader { proxy in
            ScrollView(scroll, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    track(contentPx: contentPx, fillTo: activeFill(marks: marks, axisLength: axisLength), cross: crossExtent(size))
                    ForEach(marks.ticks) { tick in
                        tickMark(tick, axisLength: axisLength, cross: crossExtent(size))
                    }
                    ForEach(marks.nodes) { node in
                        nodeButton(node, axisLength: axisLength, cross: crossExtent(size), labeled: marks.ticks.isEmpty)
                    }
                }
                .frame(
                    width: orientation == .vertical ? size.width : contentPx,
                    height: orientation == .vertical ? contentPx : size.height,
                    alignment: .topLeading
                )
            }
            .onChange(of: activeID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                if let activeID { proxy.scrollTo(activeID, anchor: .center) }
            }
        }
    }

    private func crossExtent(_ size: CGSize) -> CGFloat {
        orientation == .vertical ? size.width : size.height
    }

    private func activeFill(marks: ElasticChronology.Placement, axisLength: CGFloat) -> CGFloat {
        guard let active = marks.nodes.first(where: { $0.chapterID == activeID }) else { return 0 }
        return active.position * axisLength
    }

    private func trackCenter(cross: CGFloat, thickness: CGFloat) -> CGFloat {
        max((cross - thickness) / 2, 0)
    }

    private func track(contentPx: CGFloat, fillTo: CGFloat, cross: CGFloat) -> some View {
        let thickness = ElasticLayout.ChronAxis.trackThickness
        let trackWidth = orientation == .vertical ? thickness : max(contentPx, thickness)
        let trackHeight = orientation == .vertical ? max(contentPx, thickness) : thickness
        let inset = trackCenter(cross: cross, thickness: thickness)
        return ZStack(alignment: orientation == .vertical ? .top : .leading) {
            Capsule()
                .fill(LuminaTokens.Elastic.muted.opacity(ElasticLayout.ChronAxis.trackOpacity))
                .frame(width: trackWidth, height: trackHeight)
            Capsule()
                .fill(LuminaTokens.Elastic.ink.opacity(ElasticLayout.ChronAxis.progressOpacity))
                .frame(
                    width: orientation == .vertical ? thickness : min(max(fillTo, 0), trackWidth),
                    height: orientation == .vertical ? min(max(fillTo, 0), trackHeight) : thickness
                )
        }
        .offset(
            x: orientation == .vertical ? inset : 0,
            y: orientation == .horizontal ? inset : 0
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tickMark(_ tick: ElasticChronology.Tick, axisLength: CGFloat, cross: CGFloat) -> some View {
        let along = tick.position * axisLength
        let length = tick.major
            ? ElasticLayout.ChronAxis.tickMajorLength
            : ElasticLayout.ChronAxis.tickMinorLength
        let thickness = ElasticLayout.ChronAxis.tickWidth
        let trackMid = trackCenter(cross: cross, thickness: ElasticLayout.ChronAxis.trackThickness)
            + ElasticLayout.ChronAxis.trackThickness / 2
        let tickOrigin = trackMid - length / 2

        return Group {
            if orientation == .vertical {
                HStack(alignment: .center, spacing: ElasticLayout.ChronAxis.labelGap) {
                    Capsule()
                        .fill(LuminaTokens.Elastic.ink.opacity(tick.major ? 1 : ElasticLayout.ChronAxis.trackOpacity))
                        .frame(width: length, height: thickness)
                    if tick.major, !tick.label.isEmpty {
                        tickLabel(tick.label)
                            .frame(maxWidth: ElasticLayout.ChronAxis.verticalLabelWidth, alignment: .leading)
                    }
                }
                .frame(maxWidth: cross, alignment: .leading)
                .offset(x: max(tickOrigin, 0), y: along - thickness / 2)
            } else {
                VStack(alignment: .center, spacing: ElasticLayout.ChronAxis.labelGap) {
                    Capsule()
                        .fill(LuminaTokens.Elastic.ink.opacity(tick.major ? 1 : ElasticLayout.ChronAxis.trackOpacity))
                        .frame(width: thickness, height: length)
                    if tick.major, !tick.label.isEmpty {
                        tickLabel(tick.label)
                    }
                }
                .offset(x: along - thickness / 2, y: max(tickOrigin, 0))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tickLabel(_ text: String) -> some View {
        Text(text)
            .font(ElasticType.mono(ElasticLayout.ChronAxis.labelSize))
            .foregroundStyle(LuminaTokens.Elastic.muted)
            .lineLimit(1)
            .minimumScaleFactor(ElasticLayout.ChronAxis.labelMinScale)
            .opacity(ElasticLayout.ChronAxis.labelOpacity)
    }

    private func nodeButton(
        _ node: ElasticChronology.Node,
        axisLength: CGFloat,
        cross: CGFloat,
        labeled: Bool
    ) -> some View {
        let active = node.chapterID == activeID
        let nodeSize = active ? ElasticLayout.ChronAxis.nodeActiveSize : ElasticLayout.ChronAxis.nodeSize
        let along = node.position * axisLength
        let trackMid = trackCenter(cross: cross, thickness: ElasticLayout.ChronAxis.trackThickness)
            + ElasticLayout.ChronAxis.trackThickness / 2
        let nodeOrigin = trackMid - nodeSize / 2
        let label = Text(node.label)
            .font(ElasticType.mono(ElasticLayout.ChronAxis.labelSize))
            .foregroundStyle(active ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.muted)
            .lineLimit(1)
            .minimumScaleFactor(ElasticLayout.ChronAxis.labelMinScale)
            .opacity(ElasticLayout.ChronAxis.labelOpacity)

        return Button { navigate(node.chapterID) } label: {
            Group {
                if labeled {
                    if orientation == .vertical {
                        HStack(alignment: .center, spacing: ElasticLayout.ChronAxis.labelGap) {
                            Circle()
                                .fill(active ? LuminaTokens.Elastic.warmAccent : LuminaTokens.Elastic.ink)
                                .frame(width: nodeSize, height: nodeSize)
                            label
                                .frame(maxWidth: ElasticLayout.ChronAxis.verticalLabelWidth, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .center, spacing: ElasticLayout.ChronAxis.labelGap) {
                            Circle()
                                .fill(active ? LuminaTokens.Elastic.warmAccent : LuminaTokens.Elastic.ink)
                                .frame(width: nodeSize, height: nodeSize)
                            label
                        }
                    }
                } else {
                    Circle()
                        .fill(active ? LuminaTokens.Elastic.warmAccent : LuminaTokens.Elastic.ink)
                        .frame(width: nodeSize, height: nodeSize)
                }
            }
            .frame(
                maxWidth: orientation == .vertical && labeled ? cross : nil,
                alignment: orientation == .vertical ? .leading : .center
            )
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .offset(
            x: orientation == .vertical ? (labeled ? 0 : max(nodeOrigin, 0)) : along - nodeSize / 2,
            y: orientation == .horizontal ? (labeled ? 0 : max(nodeOrigin, 0)) : along - nodeSize / 2
        )
        .accessibilityLabel(node.label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("p0.chronology.\(node.chapterID)")
        .id(node.chapterID)
    }
}
