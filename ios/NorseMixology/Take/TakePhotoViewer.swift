import SwiftUI
import NorseMixologyCore

/// Full-screen photo viewer: swipe between a recipe's photos, delete with confirmation.
struct TakePhotoViewer: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var isConfirmingDelete = false

    init(recipe: Recipe, startID: UUID) {
        self.recipe = recipe
        _selection = State(initialValue: startID)
    }

    var body: some View {
        // Reading the count makes the viewer refresh after a delete.
        let _ = take.photoCounts[recipe.id]
        let photos = take.photos(for: recipe.id)

        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    FullPhoto(id: photo.id)
                        .tag(photo.id)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) { deleteSelected(from: photos) }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .alert(
            "Couldn't save your changes",
            isPresented: Binding(get: { take.lastError != nil }, set: { if !$0 { take.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your device couldn't save this change right now. It will be saved automatically when it can — check that your device has free space.")
        }
        }
    }

    private func deleteSelected(from photos: [PhotoItem]) {
        guard let position = photos.firstIndex(where: { $0.id == selection }) else { return }
        let neighbour = photos.indices.contains(position + 1) ? photos[position + 1].id
            : (position > 0 ? photos[position - 1].id : nil)
        take.removePhoto(id: selection)
        if let neighbour {
            selection = neighbour
        } else {
            dismiss()
        }
    }
}

/// One full-size photo, decoded once when it appears.
private struct FullPhoto: View {
    let id: UUID

    @Environment(RecipeTakeViewModel.self) private var take
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            image = take.fullImage(id: id).flatMap { UIImage(data: $0) }
        }
    }
}
