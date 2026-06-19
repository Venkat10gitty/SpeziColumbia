//
// LLMAssistantView.swift
// SpeziColumbia
//
// AI Chat tab — powered by SpeziLLM + OpenAI GPT-4o.
// Requires an OpenAI API key entered via the in-view setup screen.
//

import SpeziLLM
import SpeziLLMOpenAI
import SwiftUI


struct LLMAssistantView: View {
    @AppStorage("openai.apiKey") private var apiKey = ""
    @State private var showKeySetup = false

    var body: some View {
        if apiKey.isEmpty {
            NavigationStack {
                APIKeySetupView(apiKey: $apiKey)
                    .navigationTitle("AI Assistant Setup")
            }
        } else {
            chatView
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("API Key") {
                            showKeySetup = true
                        }
                        .font(.caption)
                    }
                }
                .sheet(isPresented: $showKeySetup) {
                    NavigationStack {
                        APIKeySetupView(apiKey: $apiKey)
                            .navigationTitle("API Key")
                    }
                }
        }
    }


    // MARK: - Chat screen

    @ViewBuilder private var chatView: some View {
        LLMChatViewSchema(
            with: LLMOpenAISchema(
                parameters: .init(
                    modelType: .gpt4o,
                    systemPrompt: """
                        You are a helpful digital health assistant integrated into the Stanford Spezi \
                        research platform. You help users understand their health data, answer general \
                        health questions, and provide guidance on using the app. \
                        Always remind users to consult a healthcare professional for medical advice.
                        """,
                    overwritingAuthToken: .closure {
                        UserDefaults.standard.string(forKey: "openai.apiKey")
                    }
                )
            )
        )
        .id(apiKey)
    }
}


// MARK: - API Key entry view

struct APIKeySetupView: View {
    @Binding var apiKey: String
    @State private var draftKey = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                SecureField("sk-...", text: $draftKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Your key is stored locally on device and never transmitted except to OpenAI.")
            }

            Section {
                Button("Save Key") {
                    apiKey = draftKey.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)

                if !apiKey.isEmpty {
                    Button("Clear Saved Key", role: .destructive) {
                        apiKey = ""
                        draftKey = ""
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            draftKey = apiKey
        }
    }
}
