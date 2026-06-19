//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import SpeziDevicesUI

/// A tab that shows paired devices and lets the user pair a new Omron cuff.
struct DeviceTabView: View {
    var body: some View {
        NavigationStack {
            DevicesView(appName: "SpeziColumbia") {
                Text("Turn on your Omron device and put it in pairing mode. Then tap + to add it.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Devices")
        }
    }
}
