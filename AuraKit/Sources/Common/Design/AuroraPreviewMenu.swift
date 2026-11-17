import SwiftUI

/// A title control that opens a strip of previews. Each opening owns one context so an
/// advancing playhead cannot change what the tiles show or where a selection lands.
public struct AuroraPreviewMenu<Option: Identifiable, Context>: View {
    private let selected: Option
    private let options: [Option]
    private let name: (Option) -> String
    private let captureContext: () -> Context
    private let caption: (Context) -> Text
    private let loadPreview: @MainActor (Option, Context) async -> Image?
    private let onSelect: (Option, Context) -> Void

    @State private var session: Session?

    public init(
        selected: Option,
        options: [Option],
        name: @escaping (Option) -> String,
        captureContext: @escaping () -> Context,
        caption: @escaping (Context) -> Text,
        loadPreview: @escaping @MainActor (Option, Context) async -> Image?,
        onSelect: @escaping (Option, Context) -> Void
    ) {
        self.selected = selected
        self.options = options
        self.name = name
        self.captureContext = captureContext
        self.caption = caption
        self.loadPreview = loadPreview
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            session = Session(context: captureContext())
        } label: {
            HStack(spacing: 5) {
                Text(name(selected))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch camera")
        .accessibilityValue(name(selected))
        .popover(item: $session, arrowEdge: .top) { session in
            VStack(alignment: .leading, spacing: 10) {
                caption(session.context)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(options) { option in
                            Button {
                                self.session = nil
                                if option.id != selected.id {
                                    onSelect(option, session.context)
                                }
                            } label: {
                                PreviewTile(name: name(option), isSelected: option.id == selected.id) {
                                    await loadPreview(option, session.context)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(option.id == selected.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    private struct Session: Identifiable {
        let id = UUID()
        let context: Context
    }

    private struct PreviewTile: View {
        let name: String
        let isSelected: Bool
        let load: @MainActor () async -> Image?

        @State private var preview = Preview.loading

        private enum Preview {
            case loading
            case image(Image)
            case unavailable
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Color.auroraNoFootage
                    .frame(width: 102, height: 58)
                    .overlay {
                        switch preview {
                        case .loading:
                            ProgressView().controlSize(.small)
                        case .image(let image):
                            image.resizable().scaledToFill()
                        case .unavailable:
                            Image(systemName: "video.slash").foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 7))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }
                    .accessibilityHidden(true)
                Text(name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(width: 102, alignment: .leading)
            }
            .contentShape(Rectangle())
            .task {
                let image = await load()
                guard !Task.isCancelled else { return }
                preview = image.map(Preview.image) ?? .unavailable
            }
        }
    }
}
