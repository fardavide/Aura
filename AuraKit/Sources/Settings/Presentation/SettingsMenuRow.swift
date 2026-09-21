import SwiftUI

import CommonDesign

/// A menu row: a title, an optional trailing value summary, and an optional leading/trailing
/// accessory (e.g. the App Icon preview artwork). The enclosing `NavigationLink` draws the
/// system disclosure chevron — this view is only the row's content.
struct SettingsMenuRow<Accessory: View>: View {
    let title: String
    let value: String?
    let accessory: Accessory

    init(title: String, value: String?, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.value = value
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
                .auroraText(.headline)
                .foregroundStyle(.auroraTextPrimary)
            Spacer()
            accessory
            if let value {
                Text(value)
                    .auroraText(.bodyEmphasis)
                    .foregroundStyle(.auroraTextSecondary)
                    // The server value is a host the user typed, so it has no length bound. It
                    // truncates in the middle because the ends carry the meaning — which server,
                    // and on which port — and it is the only flexible thing on the row, so the
                    // title and any accessory beside it keep their shape.
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension SettingsMenuRow where Accessory == EmptyView {
    init(title: String, value: String?) {
        self.init(title: title, value: value) { EmptyView() }
    }
}
