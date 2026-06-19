//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SpeziViews
import SwiftUI


struct Consent: View {
    @Environment(ManagedNavigationStack.Path.self) private var onboardingNavigationPath

    private var consentText: String {
        guard let path = Bundle.main.url(forResource: "ConsentDocument", withExtension: "md"),
              let text = try? String(contentsOf: path, encoding: .utf8) else {
            return String(localized: "CONSENT_LOADING_ERROR")
        }
        return text
    }

    var body: some View {
        OnboardingView {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingTitleView(
                    title: "Consent",
                    subtitle: "Please read and accept the consent form."
                )
                ScrollView {
                    Text(consentText)
                        .font(.body)
                        .padding(.horizontal)
                }
            }
        } footer: {
            OnboardingActionsView("I Agree") {
                onboardingNavigationPath.nextStep()
            }
        }
        .navigationTitle(Text(verbatim: ""))
    }
}


#if DEBUG
#Preview {
    ManagedNavigationStack {
        Consent()
    }
    .previewWith(standard: TemplateApplicationStandard()) {
    }
}
#endif
