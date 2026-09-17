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
                            .font(.headline)
                        Spacer()
                        FlavorProfileIndicatorView(profile: style.flavorProfile)
                    }
                    if !style.exampleBrands.isEmpty {
                        Text("Example brands: \(style.exampleBrands.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Brand (optional)") {
                    TextField("e.g. Hendrick's", text: $brandText)
                }
            }
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
