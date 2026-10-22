import SwiftUI
import PhotosUI
import AVFoundation
import NorseMixologyCore

/// The photo strip: thumbnails, an "Add photo" tile (a menu: take a photo with the camera, or
/// choose from the system picker, which needs no photo-library permission) and a viewer. Partial failures and the six-photo limit are
/// reported, never silent.
struct TakePhotoStrip: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewerTarget: ViewerTarget?
    @State private var message: AddMessage?
    @State private var isAdding = false
    @State private var showsLibrary = false
    @State private var showsCamera = false

    private struct ViewerTarget: Identifiable {
        let id: UUID
    }

    private enum AddMessage {
        case partial(added: Int, total: Int)
        case limit
        case failed
        case cameraDenied
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
                        addMenu
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
        .photosPicker(isPresented: $showsLibrary, selection: $pickerItems, maxSelectionCount: max(1, freeSlots), matching: .images)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in Task { await addCaptured(image) } }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            TakePhotoViewer(recipe: recipe, startID: target.id)
        }
    }

    /// Camera first (when the device has one), then the library.
    private var addMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { Task { await openCamera() } }
            }
            Button("Choose from Library", systemImage: "photo.on.rectangle") { showsLibrary = true }
        } label: {
            addTile
        }
        .disabled(isAdding)
        .accessibilityLabel("Add photo")
    }

    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            message = .cameraDenied
        case .notDetermined:
            // The system camera asks on first use; asking here first keeps a "no" from showing a black screen.
            if await AVCaptureDevice.requestAccess(for: .video) {
                message = nil
                showsCamera = true
            } else {
                message = .cameraDenied
            }
        default:
            message = nil
            showsCamera = true
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
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Add photo")
                    .dsText(.body)
            }
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
        case .cameraDenied: Text("Allow camera access in Settings to take photos")
        }
    }

    private func addCaptured(_ image: UIImage) async {
        isAdding = true
        message = nil
        // Orientation is carried in the JPEG metadata, which the photo processor honours.
        if let data = image.jpegData(compressionQuality: 0.95) {
            let result = await take.addPhotos([data], for: recipe)
            if result.added == 1 {
                message = nil
            } else {
                message = result.refusedForLimit > 0 && result.failed == 0 ? .limit : .failed
            }
        } else {
            message = .failed
        }
        isAdding = false
    }

    private func add(_ items: [PhotosPickerItem]) async {
        isAdding = true
        message = nil
        var totals = AddPhotosResult()
        var unreadable = 0
        // One photo at a time: load, process, store, then let the data go.
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                unreadable += 1
                continue
            }
            let one = await take.addPhotos([data], for: recipe)
            totals.added += one.added
            totals.failed += one.failed
            totals.refusedForLimit += one.refusedForLimit
        }
        pickerItems = []

        let total = items.count
        let failed = totals.failed + unreadable
        if totals.added == total {
            message = nil
        } else if totals.added > 0 {
            message = .partial(added: totals.added, total: total)
        } else if totals.refusedForLimit > 0 && failed == 0 {
            message = .limit
        } else {
            message = .failed
        }
        isAdding = false
    }
}
