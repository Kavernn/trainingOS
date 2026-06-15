import SwiftUI

// MARK: - HRV Chart

struct HRVChart: View {
    let entries: [RecoveryEntry]
    var baseline: Double? = nil
    var zoneColor: Color = .statusGreen

    @State private var trim: CGFloat = 0
    @State private var selectedPt: Int? = nil

    private let kL: CGFloat = 28  // leading space for Y labels

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var pts: [(idx: Int, val: Double)] {
        entries.enumerated().compactMap { i, e in
            guard let v = e.hrv, v > 0 else { return nil }
            return (i, v)
        }
    }
    private var yMax: Double { max((pts.map(\.val).max() ?? 60) * 1.1, 60) }
    private var yMin: Double { max((pts.map(\.val).min() ?? 0) - 15, 0) }
    private var yRng: Double { max(yMax - yMin, 1) }

    private func xAt(_ idx: Int, w: CGFloat) -> CGFloat {
        guard entries.count > 1 else { return kL + (w - kL) / 2 }
        return kL + CGFloat(idx) / CGFloat(entries.count - 1) * (w - kL)
    }
    private func yAt(_ val: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((val - yMin) / yRng) * h
    }

    private func linePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path(); var moved = false
        for pt in pts {
            let cp = CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
            if !moved { path.move(to: cp); moved = true } else { path.addLine(to: cp) }
        }
        return path
    }
    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: xAt(first.idx, w: w), y: h))
        path.addLine(to: CGPoint(x: xAt(first.idx, w: w), y: yAt(first.val, h: h)))
        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))) }
        path.addLine(to: CGPoint(x: xAt(last.idx, w: w), y: h))
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMin + frac * yRng
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.appSurfaceInset, lineWidth: 0.5)
        Text(String(format: "%.0f", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HRV — 14 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let b = baseline {
                    Text("baseline \(Int(b)) ms")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.6))
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    if let b = baseline, b > yMin, b < yMax {
                        let by = yAt(b, h: h)
                        Path { p in p.move(to: CGPoint(x: kL, y: by)); p.addLine(to: CGPoint(x: w, y: by)) }
                            .stroke(zoneColor.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    areaPath(w: w, h: h).fill(zoneColor.opacity(0.07))

                    linePath(w: w, h: h)
                        .trim(from: 0, to: trim)
                        .stroke(zoneColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(pts.enumerated()), id: \.0) { j, pt in
                        Circle()
                            .fill(zoneColor)
                            .frame(width: selectedPt == j ? 8 : 4,
                                   height: selectedPt == j ? 8 : 4)
                            .position(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
                            .animation(.easeInOut(duration: 0.15), value: selectedPt)
                    }

                    if let j = selectedPt, j < pts.count {
                        let pt = pts[j]
                        let tx = xAt(pt.idx, w: w)
                        let ty = yAt(pt.val, h: h)
                        let lbl = entries.indices.contains(pt.idx) ? (entries[pt.idx].date ?? "") : ""
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f ms", pt.val))
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            Text(lbl).font(.appMicro).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(zoneColor.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(tx, 55), w - 55), y: max(ty - 36, 22))
                    }

                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !pts.isEmpty else { return }
                                let tx = v.location.x
                                let j = pts.indices.min(by: {
                                    abs(xAt(pts[$0].idx, w: w) - tx) <
                                    abs(xAt(pts[$1].idx, w: w) - tx)
                                }) ?? 0
                                selectedPt = j
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedPt = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeInOut(duration: 0.5)) { trim = 1 } }

            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(zoneColor).frame(width: 6, height: 6)
                    Text("HRV personnelle").font(.appMicro).foregroundColor(.gray)
                }
                if baseline != nil {
                    HStack(spacing: 4) {
                        HStack(spacing: 1) {
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 3, height: 1)
                            Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 3, height: 1)
                            Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                            Rectangle().fill(zoneColor.opacity(0.5)).frame(width: 2, height: 1)
                        }
                        Text("Baseline 7j").font(.appMicro).foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(16).glassCard(color: .statusGreen, intensity: 0.05)
    }
}

// MARK: - RHR Chart

struct RHRChart: View {
    let entries: [RecoveryEntry]

    @State private var trim: CGFloat = 0
    @State private var selectedPt: Int? = nil

    private let kL: CGFloat = 28
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var pts: [(idx: Int, val: Double)] {
        entries.enumerated().compactMap { i, e in
            guard let v = e.restingHr, v > 0 else { return nil }
            return (i, v)
        }
    }
    private var lineColor: Color {
        let avg = pts.isEmpty ? 0 : pts.map(\.val).reduce(0, +) / Double(pts.count)
        return avg <= 55 ? .statusGreen : (avg <= 65 ? .statusOrange : .statusRed)
    }
    // Ensure 40–60 reference band is always visible
    private var yMax: Double { max((pts.map(\.val).max() ?? 60) + 5, 70) }
    private var yMin: Double { min((pts.map(\.val).min() ?? 50) - 5, 35) }
    private var yRng: Double { max(yMax - yMin, 1) }

    private func xAt(_ idx: Int, w: CGFloat) -> CGFloat {
        guard entries.count > 1 else { return kL + (w - kL) / 2 }
        return kL + CGFloat(idx) / CGFloat(entries.count - 1) * (w - kL)
    }
    private func yAt(_ val: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((val - yMin) / yRng) * h
    }

    private func linePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path(); var moved = false
        for pt in pts {
            let cp = CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
            if !moved { path.move(to: cp); moved = true } else { path.addLine(to: cp) }
        }
        return path
    }
    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: xAt(first.idx, w: w), y: h))
        path.addLine(to: CGPoint(x: xAt(first.idx, w: w), y: yAt(first.val, h: h)))
        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))) }
        path.addLine(to: CGPoint(x: xAt(last.idx, w: w), y: h))
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMin + frac * yRng
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.appSurfaceInset, lineWidth: 0.5)
        Text(String(format: "%.0f", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FC REPOS — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // Optimal zone band fill (40–60 bpm)
                    let y40 = yAt(40, h: h)
                    let y60 = yAt(60, h: h)
                    Rectangle()
                        .fill(Color.statusGreen.opacity(0.05))
                        .frame(width: w - kL, height: abs(y40 - y60))
                        .position(x: kL + (w - kL) / 2, y: min(y40, y60) + abs(y40 - y60) / 2)

                    // 60 bpm dashed reference
                    Path { p in p.move(to: CGPoint(x: kL, y: y60)); p.addLine(to: CGPoint(x: w, y: y60)) }
                        .stroke(Color.statusGreen.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    // 40 bpm dashed reference
                    Path { p in p.move(to: CGPoint(x: kL, y: y40)); p.addLine(to: CGPoint(x: w, y: y40)) }
                        .stroke(Color.statusGreen.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    areaPath(w: w, h: h).fill(lineColor.opacity(0.07))

                    linePath(w: w, h: h)
                        .trim(from: 0, to: trim)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(Array(pts.enumerated()), id: \.0) { j, pt in
                        Circle()
                            .fill(lineColor)
                            .frame(width: selectedPt == j ? 8 : 4,
                                   height: selectedPt == j ? 8 : 4)
                            .position(x: xAt(pt.idx, w: w), y: yAt(pt.val, h: h))
                            .animation(.easeInOut(duration: 0.15), value: selectedPt)
                    }

                    if let j = selectedPt, j < pts.count {
                        let pt  = pts[j]
                        let tx  = xAt(pt.idx, w: w)
                        let ty  = yAt(pt.val, h: h)
                        let lbl = entries.indices.contains(pt.idx) ? (entries[pt.idx].date ?? "") : ""
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f bpm", pt.val))
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            Text(lbl).font(.appMicro).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(lineColor.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(tx, 55), w - 55), y: max(ty - 36, 22))
                    }

                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !pts.isEmpty else { return }
                                let tx = v.location.x
                                let j = pts.indices.min(by: {
                                    abs(xAt(pts[$0].idx, w: w) - tx) <
                                    abs(xAt(pts[$1].idx, w: w) - tx)
                                }) ?? 0
                                selectedPt = j
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedPt = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeInOut(duration: 0.5)) { trim = 1 } }

            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(lineColor).frame(width: 6, height: 6)
                    Text("FC repos").font(.appMicro).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Zone optimale 40–60 bpm").font(.appMicro).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .statusRed, intensity: 0.04)
    }
}

// MARK: - HR Moments Chart

struct HRMomentsChart: View {
    let entries: [RecoveryEntry]

    private var maxHR: Double {
        let all = entries.flatMap { [$0.hrMorning, $0.hrPostWorkout, $0.hrEvening].compactMap { $0 } }
        return max(all.max() ?? 1, 100)
    }
    private var minHR: Double {
        let all = entries.flatMap { [$0.hrMorning, $0.hrPostWorkout, $0.hrEvening].compactMap { $0 } }
        return max((all.min() ?? 50) - 10, 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FC JOURNALIÈRE — 14 DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let isLast = i == entries.count - 1
                    VStack(spacing: 1) {
                        if let m = e.hrMorning {
                            dot(.statusCyan, m, maxHR, minHR, isLast)
                        }
                        if let pw = e.hrPostWorkout {
                            dot(Color.forge, pw, maxHR, minHR, isLast)
                        }
                        if let ev = e.hrEvening {
                            dot(.statusBlue, ev, maxHR, minHR, isLast)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70, alignment: .bottom)
                }
            }
            .frame(height: 70)

            HStack(spacing: 12) {
                legendDot(.statusCyan,   "Matin")
                legendDot(Color.forge, "Post séance")
                legendDot(.statusBlue,   "Soir")
            }
        }
        .padding(16).glassCard(color: .statusCyan, intensity: 0.04)
    }

    @ViewBuilder
    private func dot(_ color: Color, _ value: Double, _ maxV: Double, _ minV: Double, _ bright: Bool) -> some View {
        let range = maxV - minV
        let pct   = range > 0 ? (value - minV) / range : 0.5
        let h     = max(CGFloat(pct) * 50, 4)
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(bright ? 0.9 : 0.5))
            .frame(height: h)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
    }
}

// MARK: - Sleep Chart

struct SleepChart: View {
    let entries: [RecoveryEntry]

    @State private var appeared  = false
    @State private var selectedIdx: Int? = nil

    private let kL: CGFloat = 28

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var yMax: Double { max(entries.compactMap(\.sleepHours).max() ?? 8, 9) }

    private func barColor(_ h: Double) -> Color { h >= 7 ? .statusGreen : (h >= 6 ? .statusOrange : .statusRed) }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMax * frac
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.appSurfaceInset, lineWidth: 0.5)
        Text(String(format: "%.0fh", val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    private func barDelay(_ i: Int) -> Double { Double(i) * 0.04 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOMMEIL — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w        = geo.size.width
                let h        = geo.size.height
                let chartW   = w - kL
                let n        = max(entries.count, 1)
                let slot: CGFloat = chartW / CGFloat(n)
                let barW: CGFloat = max(slot * 0.65, 3)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // 7h objective dashed line
                    let y7 = h - CGFloat(7.0 / yMax) * h
                    Path { p in p.move(to: CGPoint(x: kL, y: y7)); p.addLine(to: CGPoint(x: w, y: y7)) }
                        .stroke(Color.statusGreen.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Bars
                    ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                        let hours  = e.sleepHours ?? 0
                        let color  = barColor(hours)
                        let barH   = hours > 0 ? CGFloat(hours / yMax) * h : 0
                        let cx     = kL + CGFloat(i) * slot + slot / 2

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(selectedIdx == i ? 1.0 : 0.65))
                            .frame(width: barW, height: max(barH, hours > 0 ? 2 : 0))
                            .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                            .position(x: cx, y: h - max(barH, hours > 0 ? 2 : 0) / 2)
                            .animation(.easeOut(duration: 0.5).delay(barDelay(i)), value: appeared)
                    }

                    // Tooltip
                    if let j = selectedIdx, entries.indices.contains(j) {
                        let sleepH = entries[j].sleepHours ?? 0
                        let cx     = kL + CGFloat(j) * slot + slot / 2
                        let barH   = CGFloat(sleepH / yMax) * h
                        VStack(spacing: 2) {
                            Text(String(format: "%.1fh", sleepH))
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            Text(entries[j].date ?? "")
                                .font(.appMicro).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(barColor(sleepH).opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(cx, 50), w - 50), y: max(h - barH - 30, 22))
                    }

                    // Touch layer
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let idx = Int((v.location.x - kL) / slot)
                                if entries.indices.contains(idx) { selectedIdx = idx }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedIdx = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }

            // X axis
            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    VStack(spacing: 1) {
                        Text(dayAbbrev(e))
                            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        if e.source == "healthkit" {
                            Image(systemName: "applewatch")
                                .font(.system(size: 6)).foregroundColor(Color.statusBlue.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(.statusGreen,  "≥7h")
                legendDot(Color.forge, "6–7h")
                legendDot(.statusRed,    "<6h")
                Spacer()
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Objectif 7h").font(.appMicro).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .statusBlue, intensity: 0.05)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
    }
}

// MARK: - Steps Chart

struct StepsChart: View {
    let entries: [RecoveryEntry]
    var stepGoal: Int = 10_000

    @State private var appeared   = false
    @State private var selectedIdx: Int? = nil

    private let kL: CGFloat = 30  // slightly wider — "10.5k" Y labels need a bit more room

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var yMax: Double {
        let m = entries.compactMap(\.steps).map(Double.init).max() ?? 0
        return max(m * 1.1, Double(stepGoal) * 1.15)
    }

    private func barColor(_ s: Double) -> Color { s >= 10_000 ? .statusGreen : (s >= 7_000 ? .statusOrange : .statusRed) }

    private func stepsLabel(_ s: Double) -> String {
        s >= 1_000 ? String(format: "%.1fk", s / 1_000) : "\(Int(s))"
    }

    @ViewBuilder
    private func gridLine(step: Int, w: CGFloat, h: CGFloat) -> some View {
        let frac = Double(step) / 4.0
        let yy   = CGFloat(1.0 - frac) * h
        let val  = yMax * frac
        Path { p in p.move(to: CGPoint(x: kL, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
            .stroke(Color.appSurfaceInset, lineWidth: 0.5)
        Text(stepsLabel(val))
            .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
            .frame(width: kL - 4, alignment: .trailing)
            .position(x: (kL - 4) / 2, y: yy)
    }

    private func dayAbbrev(_ e: RecoveryEntry) -> String {
        guard let d = e.date, let date = Self.dateFmt.date(from: d) else { return "" }
        return ["D","L","M","M","J","V","S"][Calendar.current.component(.weekday, from: date) - 1]
    }

    private func barDelay(_ i: Int) -> Double { Double(i) * 0.04 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAS — DERNIERS JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let w      = geo.size.width
                let h      = geo.size.height
                let chartW = w - kL
                let n      = max(entries.count, 1)
                let slot: CGFloat = chartW / CGFloat(n)
                let barW: CGFloat = max(slot * 0.65, 3)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { step in gridLine(step: step, w: w, h: h) }

                    // 10k objective dashed line
                    let yGoal = h - CGFloat(Double(stepGoal) / yMax) * h
                    Path { p in p.move(to: CGPoint(x: kL, y: yGoal)); p.addLine(to: CGPoint(x: w, y: yGoal)) }
                        .stroke(Color.statusGreen.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Bars
                    ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                        let steps  = Double(e.steps ?? 0)
                        let color  = barColor(steps)
                        let barH   = steps > 0 ? CGFloat(steps / yMax) * h : 0
                        let cx     = kL + CGFloat(i) * slot + slot / 2

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(selectedIdx == i ? 1.0 : 0.65))
                            .frame(width: barW, height: max(barH, steps > 0 ? 2 : 0))
                            .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                            .position(x: cx, y: h - max(barH, steps > 0 ? 2 : 0) / 2)
                            .animation(.easeOut(duration: 0.5).delay(barDelay(i)), value: appeared)
                    }

                    // Tooltip
                    if let j = selectedIdx, entries.indices.contains(j) {
                        let steps  = Double(entries[j].steps ?? 0)
                        let cx     = kL + CGFloat(j) * slot + slot / 2
                        let barH   = CGFloat(steps / yMax) * h
                        VStack(spacing: 2) {
                            Text(stepsLabel(steps) + " pas")
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                            Text(entries[j].date ?? "")
                                .font(.appMicro).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.appCard.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(barColor(steps).opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .position(x: min(max(cx, 55), w - 55), y: max(h - barH - 30, 22))
                    }

                    // Touch layer
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let idx = Int((v.location.x - kL) / slot)
                                if entries.indices.contains(idx) { selectedIdx = idx }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { selectedIdx = nil }
                                }
                            }
                        )
                }
            }
            .frame(height: 90)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }

            // X axis
            HStack(spacing: 0) {
                Spacer().frame(width: kL)
                ForEach(Array(entries.enumerated()), id: \.0) { _, e in
                    Text(dayAbbrev(e))
                        .font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(.statusGreen,  "≥10k")
                legendDot(Color.forge, "7k–10k")
                legendDot(.statusRed,    "<7k")
                Spacer()
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 3, height: 1)
                        Rectangle().fill(Color.clear).frame(width: 2, height: 1)
                        Rectangle().fill(Color.statusGreen.opacity(0.5)).frame(width: 2, height: 1)
                    }
                    Text("Objectif 10k").font(.appMicro).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard(color: .statusGreen, intensity: 0.05)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
    }
}
