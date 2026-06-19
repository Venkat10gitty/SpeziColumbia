//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct BackendSettingsView: View {
    @State private var selection: BackendTarget = BackendPrefs.get()

    var body: some View {
        Form {
            Section(header: Text("Data Destination")) {
                Picker("Upload to", selection: $selection) {
                    ForEach(BackendTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .onChange(of: selection) { newValue in
                    BackendPrefs.set(newValue)
                }
            }

            Section(footer: Text("Changes apply immediately for the next uploads.")) {
                EmptyView()
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            selection = BackendPrefs.get()
        }
    }
}
