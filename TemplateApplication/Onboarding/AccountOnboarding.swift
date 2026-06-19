//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport) import SpeziAccount
import SpeziOnboarding
import SpeziViews
import SwiftUI


struct AccountOnboarding: View {
    @Environment(ManagedNavigationStack.Path.self) private var onboardingNavigationPath


    var body: some View {
        AccountSetup { _ in
            Task {
                // Placing the nextStep() call inside this task will ensure that the sheet dismiss animation is
                // played till the end before we navigate to the next step.
                onboardingNavigationPath.nextStep()
            }
        } header: {
            AccountSetupHeader()
        } continue: {
            OnboardingActionsView(
                "Next",
                action: {
                    onboardingNavigationPath.nextStep()
                }
            )
        }
    }
}


#if DEBUG
#Preview("Account Onboarding SignIn") {
    ManagedNavigationStack {
        AccountOnboarding()
    }
    .previewWith {
        AccountConfiguration(service: InMemoryAccountService())
    }
}

#Preview("Account Onboarding") {
    let details: AccountDetails = {
        var accountDetails = AccountDetails()
        accountDetails.userId = "lelandstanford@stanford.edu"
        accountDetails.name = PersonNameComponents(givenName: "Leland", familyName: "Stanford")
        return accountDetails
    }()
    ManagedNavigationStack {
        AccountOnboarding()
    }
    .previewWith {
        AccountConfiguration(service: InMemoryAccountService(), activeDetails: details)
    }
}
#endif
