import SwiftUI

/// Settings section for the Anthropic API key. Anthropic appears in the model picker once a key is set.
struct AnthropicSection: View {
    let store: ChatStore

    var body: some View {
        @Bindable var key = store.registry.anthropicKey
        Section {
            SecureField("API key", text: $key.text, prompt: Text("sk-ant-…"))
                .textContentType(.password)
                .autocorrectionDisabled()
                .onSubmit(refreshModels)
        } header: {
            Text("Anthropic")
        } footer: {
            Text("Get a key at console.anthropic.com. Stored in your Keychain.")
                .foregroundStyle(.secondary)
        }
        .onChange(of: key.hasValue, refreshModels)
    }

    private func refreshModels() {
        Task { await store.refreshModels() }
    }
}

/// Settings section for Amazon Bedrock: region, and either a Bedrock API key or IAM access keys.
/// Bedrock appears in the model picker once the chosen sign-in method's fields are filled in.
struct BedrockSection: View {
    let store: ChatStore

    var body: some View {
        @Bindable var bedrock = store.registry.bedrock
        Section {
            TextField("Region", text: $bedrock.region, prompt: Text(BedrockSettings.defaultRegion))
                .autocorrectionDisabled()
                .onSubmit(refreshModels)
            Picker("Sign in with", selection: $bedrock.auth) {
                ForEach(BedrockSettings.Auth.allCases) { auth in
                    Text(auth.label).tag(auth)
                }
            }
            switch bedrock.auth {
            case .apiKey:
                secureField("API key", text: $bedrock.secrets.apiKey)
            case .accessKeys:
                TextField("Access key ID", text: $bedrock.secrets.accessKeyID, prompt: Text("AKIA…"))
                    .autocorrectionDisabled()
                    .onSubmit(refreshModels)
                secureField("Secret access key", text: $bedrock.secrets.secretAccessKey)
                secureField("Session token", text: $bedrock.secrets.sessionToken, prompt: "Optional")
            }
        } header: {
            Text("Amazon Bedrock")
        } footer: {
            Text("Use a Bedrock API key, or an IAM access key allowed to call bedrock:InvokeModelWithResponseStream, ListFoundationModels, and ListInferenceProfiles. Enable model access in the Bedrock console first. Credentials are stored in your Keychain.")
                .foregroundStyle(.secondary)
        }
        .onChange(of: bedrock.provider != nil, refreshModels)
        .onChange(of: bedrock.auth, refreshModels)
    }

    private func secureField(_ title: String, text: Binding<String>, prompt: String? = nil) -> some View {
        SecureField(title, text: text, prompt: prompt.map(Text.init))
            .textContentType(.password)
            .autocorrectionDisabled()
            .onSubmit(refreshModels)
    }

    private func refreshModels() {
        Task { await store.refreshModels() }
    }
}
