import Foundation

extension RuntimeSettings {
    static func defaults() -> RuntimeSettings {
        return RuntimeSettings(
            arkApiKey: "",
            arkModel: DEFAULT_ARK_MODEL,
            arkBaseUrl: DEFAULT_ARK_BASE_URL,
            arkEndpoint: DEFAULT_ARK_ENDPOINT,
            arkSystemPrompt: DEFAULT_ARK_SYSTEM_PROMPT,
            imagePrompt: DEFAULT_IMAGE_PROMPT,
            openSpeechApiKey: "",
            openSpeechResourceId: DEFAULT_OPENSPEECH_RESOURCE_ID,
            openSpeechSubmitUrl: DEFAULT_OPENSPEECH_SUBMIT_URL,
            openSpeechQueryUrl: DEFAULT_OPENSPEECH_QUERY_URL,
            openSpeechUid: DEFAULT_OPENSPEECH_UID,
            flowStudyServerUrl: "",
            flowStudyDeviceId: "",
            flowStudyDeviceToken: "",
            customModelBaseUrl: "",
            customModelApiKey: "",
            customModelName: "",
            customModelPresets: []
        )
    }

    func hasCompleteCustomModel() -> Bool {
        return !customModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !customModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearCustomModel() -> RuntimeSettings {
        var copy = self
        copy.customModelBaseUrl = ""
        copy.customModelApiKey = ""
        copy.customModelName = ""
        return copy
    }

    func applyModelPreset(_ preset: ModelPreset) -> RuntimeSettings {
        var copy = self
        copy.customModelBaseUrl = preset.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customModelApiKey = preset.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customModelName = preset.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    func saveCurrentModelPreset(_ name: String) -> RuntimeSettings {
        guard hasCompleteCustomModel() else { return self }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmedName = String(normalizedName.prefix(18))
        if trimmedName.isEmpty { return self }

        let preserved = customModelPresets.filter { !$0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
        let id = "preset-\(currentTimeMillis())-\(trimmedName.lowercased().hashValue)"
        let nextPreset = ModelPreset(
            id: id,
            name: trimmedName,
            baseUrl: customModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: customModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var copy = self
        copy.customModelPresets = Array(([nextPreset] + preserved).prefix(16))
        return copy
    }

    func removeModelPreset(presetId: String) -> RuntimeSettings {
        var copy = self
        copy.customModelPresets = customModelPresets.filter { $0.id != presetId }
        return copy
    }

    func currentModelDisplayName() -> String {
        if hasCompleteCustomModel() {
            return "自定义 · \(customModelName.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return "系统豆包 · \(arkModel.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func currentModelDisplayHint() -> String {
        if hasCompleteCustomModel() {
            return customModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return arkBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func customModelConfigOrNull() -> ArkRuntimeConfig? {
        let baseUrlInput = customModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKeyInput = customModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelInput = customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseUrlInput.isEmpty || apiKeyInput.isEmpty || modelInput.isEmpty {
            return nil
        }

        let normalizedBase = String(baseUrlInput.reversed().drop(while: { $0 == "/" }).reversed())
        let endpoint: String
        let baseUrl: String
        if normalizedBase.lowercased().hasSuffix("/chat/completions") {
            endpoint = "chat/completions"
            baseUrl = String(normalizedBase.dropLast("/chat/completions".count))
        } else if normalizedBase.lowercased().hasSuffix("/responses") {
            endpoint = "responses"
            baseUrl = String(normalizedBase.dropLast("/responses".count))
        } else {
            endpoint = "chat/completions"
            baseUrl = normalizedBase
        }
        let resolvedBaseUrl = baseUrl.isEmpty ? normalizedBase : baseUrl

        return ArkRuntimeConfig(
            apiKey: apiKeyInput,
            model: modelInput,
            baseUrl: resolvedBaseUrl,
            endpoint: endpoint,
            systemPrompt: normalizeSystemPrompt(arkSystemPrompt)
        )
    }

    func toArkRuntimeConfig() -> ArkRuntimeConfig {
        if let custom = customModelConfigOrNull() {
            return custom
        }
        return ArkRuntimeConfig(
            apiKey: arkApiKey,
            model: arkModel,
            baseUrl: arkBaseUrl,
            endpoint: arkEndpoint,
            systemPrompt: normalizeSystemPrompt(arkSystemPrompt)
        )
    }

    func toOpenSpeechRuntimeConfig() -> OpenSpeechRuntimeConfig {
        return OpenSpeechRuntimeConfig(
            apiKey: openSpeechApiKey,
            resourceId: openSpeechResourceId,
            submitUrl: openSpeechSubmitUrl,
            queryUrl: openSpeechQueryUrl,
            uid: openSpeechUid
        )
    }
}

func normalizeSystemPrompt(_ prompt: String) -> String {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return DEFAULT_ARK_SYSTEM_PROMPT }
    if trimmed == LEGACY_ARK_SYSTEM_PROMPT { return DEFAULT_ARK_SYSTEM_PROMPT }
    return trimmed
}

func normalizeImagePrompt(_ prompt: String) -> String {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return DEFAULT_IMAGE_PROMPT }
    if trimmed == LEGACY_IMAGE_PROMPT { return DEFAULT_IMAGE_PROMPT }
    return trimmed
}

func builtinModelPresetTemplates() -> [ModelPreset] {
    return [
        ModelPreset(id: "template-openai-official", name: "OpenAI 模板", baseUrl: "https://api.openai.com/v1", apiKey: "", modelName: "gpt-4o-mini"),
        ModelPreset(id: "template-compatible-api", name: "兼容接口模板", baseUrl: "https://your-api.example.com/v1", apiKey: "", modelName: "your-model")
    ]
}

struct OpenSpeechRuntimeConfig {
    var apiKey: String
    var resourceId: String
    var submitUrl: String
    var queryUrl: String
    var uid: String
}
