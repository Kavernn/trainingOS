import SwiftUI

enum MuscleMapDisplayMode {
    case front
    case back
    case both
}

struct MuscleMapView: View {
    let zones: Set<MuscleZone>
    let tint: Color
    let displayMode: MuscleMapDisplayMode

    init(
        zones: Set<MuscleZone>,
        tint: Color,
        displayMode: MuscleMapDisplayMode = .both
    ) {
        self.zones = zones
        self.tint = tint
        self.displayMode = displayMode
    }

    var body: some View {
        Group {
            switch displayMode {
            case .front:
                muscleFigure(.front)
            case .back:
                muscleFigure(.back)
            case .both:
                HStack(spacing: 8) {
                    muscleFigure(.front)
                    muscleFigure(.back)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func muscleFigure(_ orientation: MuscleMapOrientation) -> some View {
        ZStack {
            imageLayer(named: orientation.bodyAssetName, renderingMode: .original)

            ForEach(orientation.maskAssets.filter { zones.contains($0.zone) }) { mask in
                imageLayer(named: mask.assetName, renderingMode: .template)
                    .foregroundStyle(tint)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    private func imageLayer(
        named assetName: String,
        renderingMode: Image.TemplateRenderingMode
    ) -> some View {
        Image(assetName)
            .renderingMode(renderingMode)
            .resizable()
            .scaledToFit()
    }
}

private struct MuscleMaskAsset: Identifiable {
    let zone: MuscleZone
    let assetName: String

    var id: String { assetName }
}

private enum MuscleMapOrientation {
    case front
    case back

    var bodyAssetName: String {
        switch self {
        case .front: return "MuscleBodyFront"
        case .back: return "MuscleBodyBack"
        }
    }

    var maskAssets: [MuscleMaskAsset] {
        switch self {
        case .front:
            return [
                MuscleMaskAsset(zone: .chest, assetName: "MuscleMaskFrontChest"),
                MuscleMaskAsset(zone: .shoulders, assetName: "MuscleMaskFrontShoulders"),
                MuscleMaskAsset(zone: .biceps, assetName: "MuscleMaskFrontBiceps"),
                MuscleMaskAsset(zone: .core, assetName: "MuscleMaskFrontCore"),
                MuscleMaskAsset(zone: .quads, assetName: "MuscleMaskFrontQuads")
            ]
        case .back:
            return [
                MuscleMaskAsset(zone: .generalBack, assetName: "MuscleMaskBackGeneralBack"),
                MuscleMaskAsset(zone: .traps, assetName: "MuscleMaskBackTraps"),
                MuscleMaskAsset(zone: .shoulders, assetName: "MuscleMaskBackShoulders"),
                MuscleMaskAsset(zone: .triceps, assetName: "MuscleMaskBackTriceps"),
                MuscleMaskAsset(zone: .glutes, assetName: "MuscleMaskBackGlutes"),
                MuscleMaskAsset(zone: .hamstrings, assetName: "MuscleMaskBackHamstrings"),
                MuscleMaskAsset(zone: .calves, assetName: "MuscleMaskBackCalves")
            ]
        }
    }
}

#Preview("Muscle map — front + back") {
    MuscleMapView(
        zones: Set(MuscleZone.allCases),
        tint: Color.domainAccent(.training),
        displayMode: .both
    )
    .padding()
}
