import SwiftUI
import NorseMixologyCore

struct AddIngredientConfirmationView: View {
    let style: IngredientStyle
    let cabinetViewModel: CabinetViewModel
    let taxonomyStore: TaxonomyStore
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var brandText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(style.name)
                            .dsText(.heading)
                            .foregroundStyle(DesignTokens.textPrimary)
                        Spacer()
                        FlavorProfileIndicatorView(profile: style.flavorProfile)
                    }
                    if !style.exampleBrands.isEmpty {
                        Text("Example brands: \(style.exampleBrands.joined(separator: ", "))")
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .listRowBackground(DesignTokens.surface)
                Section {
                    TextField("e.g. Hendrick's", text: $brandText)
                } header: {
                    Text("Brand (optional)")
                        .dsText(.label)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .listRowBackground(DesignTokens.surface)
            }
            .dsListBackground()
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Cabinet") {
                        cabinetViewModel.add(style, taxonomyStore: taxonomyStore, brand: brandText)
                        onAdded()
                    }
                }
            }
        }
    }
}
