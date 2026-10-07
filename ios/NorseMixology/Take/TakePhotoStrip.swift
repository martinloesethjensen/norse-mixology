import SwiftUI
import PhotosUI
import NorseMixologyCore

/// The photo strip: thumbnails, an "Add photo" tile (system picker, no photo-library
/// permission needed) and a viewer. Partial failures and the six-photo limit are
/// reported, never silent.
struct TakePhotoStrip: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewerTarget: ViewerTarget?
    @State private var message: AddMessage?
    @State private var isAdding = false

    private struct ViewerTarget: Identifiable {
        let id: UUID
    }

    private enum AddMessage {
        case partial(added: Int, total: Int)
        case limit
        case failed
    }

    var body: some View {
        // Reading the count makes the strip refresh after an add or delete.
        let count = take.photoCounts[recipe.id] ?? 0
        let photos = take.photos(for: recipe.id)
        let freeSlots = max(0, TakeLimits.maxPhotos - count)

        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            viewerTarget = ViewerTarget(id: photo.id)
                        } label: {
                            thumbnail(photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                        .accessibilityHint("Opens the photo")
                    }
                    if freeSlots > 0 {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: freeSlots, matching: .images) {
                            addTile
                        }
                        .disabled(isAdding)
                        .accessibilityLabel("Add photo")
                    }
                }
                .padding(.vertical, 2)
            }

            if freeSlots == 0 {
                Text("\(TakeLimits.maxPhotos) photos is the limit")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            if let message, !(freeSlots == 0 && isLimit(message)) {
                messageText(message)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.matchSubstituted)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            TakePhotoViewer(recipe: recipe, startID: target.id)
        }
    }

    private func isLimit(_ message: AddMessage) -> Bool {
        if case .limit = message { return true }
        return false
    }

    private func thumbnail(_ photo: PhotoItem) -> some View {
        Group {
            if let image = UIImage(data: photo.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(DesignTokens.surfaceRaised)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
    }

    private var addTile: some View {
        VStack(spacing: 4) {
            Image(systemName: isAdding ? "hourglass" : "plus")
                .font(.title3)
            Text("Add photo")
                .dsText(.body)
        }
        .foregroundStyle(DesignTokens.accent)
        .frame(width: 88, height: 88)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DesignTokens.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignTokens.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    @ViewBuilder
    private func messageText(_ message: AddMessage) -> some View {
        switch message {
        case .partial(let added, let total): Text("\(added) of \(total) added")
        case .limit: Text("\(TakeLimits.maxPhotos) photos is the limit")
        case .failed: Text("Couldn't add that photo")
        }
    }

    private func add(_ items: [PhotosPickerItem]) async {
        isAdding = true
        message = nil
        var datas: [Data] = []
        var unreadable = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
            } else {
                unreadable += 1
            }
        }
        pickerItems = []

        let result = await take.addPhotos(datas, for: recipe)
        let total = items.count
        let failed = result.failed + unreadable
        if result.added == total {
            message = nil
        } else if result.added > 0 {
            message = .partial(added: result.added, total: total)
        } else if result.refusedForLimit > 0 && failed == 0 {
            message = .limit
        } else {
            message = .failed
        }
        isAdding = false
    }
}
