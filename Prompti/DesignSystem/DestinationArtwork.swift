import SwiftUI

/// Reviewed landmark SVGs are compiled as vector templates by the asset catalog.
/// Custom destinations use a neutral locator rather than an invented landmark.
struct DestinationArtwork: View {
    let destination: Destination
    var size: CGFloat = 64

    var body: some View {
        Group {
            if !destination.isCustom, CatalogLocalization.destinations[destination.id] != nil {
                Image("Destination-\(destination.id)")
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
            }
        }
        .foregroundStyle(Color.promptAccent)
        .padding(size * 0.08)
        .frame(width: size, height: size)
        .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.compact))
        .accessibilityHidden(true)
    }
}
