import Foundation
import Darwin
import SQLite3

// UI-free relay core shared by the macOS app target and the native `relay`
// command-line target. This file must not import AppKit, AVFoundation, or any
// macOS UI/audio frameworks so it can compile into a plain command-line tool.

let relayCliVersion = "1.1.2"

let relayMessageTypes = ["update", "complete", "blocked", "needs-input"]
let relayPriorities = ["low", "normal", "high"]
let relayQueueChangedDarwinNotification = "com.jonmagic.tristaterelayservice.queue-changed"
let relayDebugOpenSettingsDarwinNotification = "com.jonmagic.tristaterelayservice.debug.open-settings"
let relayDebugOpenSettingsPanels = ["setup", "voice", "secondary", "advanced"]
let defaultCleanupRetentionMinutes = 365 * 24 * 60
let maxCleanupRetentionMinutes = 10 * 365 * 24 * 60
let defaultVoiceTempCleanupMinutes = 6 * 60
let relayConfigPathEnv = "TSRS_CONFIG_PATH"

struct RelayWakeNotifier {
    let post: () -> Void

    static let darwin = RelayWakeNotifier {
        postRelayQueueChangedNotification()
    }

    static let disabled = RelayWakeNotifier {}
}

func postRelayQueueChangedNotification() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(relayQueueChangedDarwinNotification as CFString),
        nil,
        nil,
        true
    )
}

func postRelayDebugOpenSettingsNotification() {
    postRelayDebugOpenSettingsNotification(panel: nil)
}

func postRelayDebugOpenSettingsNotification(panel: String?) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(relayDebugOpenSettingsNotificationName(panel: panel) as CFString),
        nil,
        nil,
        true
    )
}

func relayDebugOpenSettingsNotificationName(panel: String?) -> String {
    guard let panel, relayDebugOpenSettingsPanels.contains(panel) else {
        return relayDebugOpenSettingsDarwinNotification
    }

    return "\(relayDebugOpenSettingsDarwinNotification).\(panel)"
}

func relayDebugOpenSettingsPanelName(notificationName: String) -> String? {
    guard notificationName.hasPrefix("\(relayDebugOpenSettingsDarwinNotification).") else {
        return nil
    }

    let panel = String(notificationName.dropFirst(relayDebugOpenSettingsDarwinNotification.count + 1))
    return relayDebugOpenSettingsPanels.contains(panel) ? panel : nil
}

struct NewRelayInput {
    let line: String?
    let message: String
    let type: String?
    let priority: String?
    let session: String?
    let app: String?
    let cwd: String?
    let url: String?
}

struct NormalizedRelay {
    let line: String
    let message: String
    let type: String
    let priority: String
    let session: String?
    let app: String?
    let cwd: String?
    let url: String?
}

enum RelayValidationError: LocalizedError, Equatable {
    case required(String)
    case tooLong(String, Int)
    case invalidEnum(String, [String])
    case unsafeMessage

    var errorDescription: String? {
        switch self {
        case .required(let field):
            return "\(field) is required"
        case .tooLong(let field, let maxLength):
            if field == "optional metadata" {
                return "optional metadata must be \(maxLength) characters or fewer"
            }

            return "\(field) must be \(maxLength) characters or fewer"
        case .invalidEnum(let field, let allowed):
            return "\(field) must be one of: \(allowed.joined(separator: ", "))"
        case .unsafeMessage:
            return "message looks like it may contain a secret or token"
        }
    }
}

func normalizeRelay(_ input: NewRelayInput) throws -> NormalizedRelay {
    let line = try normalizeRequiredRelayText(input.line ?? "", field: "line", maxLength: 80)
    let message = try normalizeRequiredRelayText(input.message, field: "message", maxLength: 240)
    let type = try normalizeRelayEnum(input.type ?? "update", allowed: relayMessageTypes, field: "type")
    let priority = try normalizeRelayEnum(input.priority ?? "normal", allowed: relayPriorities, field: "priority")
    let session = try normalizeOptionalRelayText(input.session, maxLength: 120)
    let app = try normalizeOptionalRelayText(input.app, maxLength: 80)
    let cwd = try normalizeOptionalRelayText(input.cwd, maxLength: 500)
    let url = try normalizeOptionalRelayText(input.url, maxLength: 500)

    try rejectUnsafeRelayMessage(message)

    return NormalizedRelay(
        line: line,
        message: message,
        type: type,
        priority: priority,
        session: session,
        app: app,
        cwd: cwd,
        url: url
    )
}

private func normalizeRequiredRelayText(_ value: String, field: String, maxLength: Int) throws -> String {
    let normalized = normalizeRelayWhitespace(value)

    if normalized.isEmpty {
        throw RelayValidationError.required(field)
    }

    if normalized.count > maxLength {
        throw RelayValidationError.tooLong(field, maxLength)
    }

    return normalized
}

private func normalizeOptionalRelayText(_ value: String?, maxLength: Int) throws -> String? {
    guard let value else {
        return nil
    }

    let normalized = normalizeRelayWhitespace(value)

    if normalized.isEmpty {
        return nil
    }

    if normalized.count > maxLength {
        throw RelayValidationError.tooLong("optional metadata", maxLength)
    }

    return normalized
}

private func normalizeRelayEnum(_ value: String, allowed: [String], field: String) throws -> String {
    if allowed.contains(value) {
        return value
    }

    throw RelayValidationError.invalidEnum(field, allowed)
}

private func normalizeRelayWhitespace(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func rejectUnsafeRelayMessage(_ message: String) throws {
    let patterns = [
        #"gh[pousr]_[A-Za-z0-9_]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"(?i)(?:api[_-]?key|token|secret)\s*[:=]\s*\S{8,}"#,
        #"[A-Za-z0-9+/]{32,}={0,2}"#,
    ]

    for pattern in patterns {
        if message.range(of: pattern, options: .regularExpression) != nil {
            throw RelayValidationError.unsafeMessage
        }
    }
}

// MARK: - Native CLI dispatcher

let directRelayCapabilities: [String: Any] = [
    "profile": "direct",
    "nativeSpeech": false,
    "terminalEnqueue": true,
    "externalSpeechCommand": true,
    "externalInactiveLineCombiner": true,
    "lineSourceActions": true,
]

let appProcessorAuthorization = "app-owned-processor"
let appProcessorAuthorizationEnv = "TSRS_PROCESSOR_AUTH"

func processorIsAppAuthorized(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment[appProcessorAuthorizationEnv] == appProcessorAuthorization
}

struct RelayConfig {
    var voiceCommand: String
    var voiceProvider: String?
    var voiceVariables: [String: String]
    var voiceProviders: [String: RelayVoiceProviderConfig]
    var combinerCommand: String
    var combinerVariables: [String: String]
    var cleanupRetentionMinutes: Int

    var activeVoiceProvider: RelayVoiceProviderConfig? {
        guard let voiceProvider else {
            return nil
        }

        return voiceProviders[voiceProvider]
    }

    static func from(settings: [String: String]) -> RelayConfig {
        let storedVoice = settings["voice_command"].flatMap { shouldMigrateVoiceCommand($0) ? nil : $0 } ?? defaultVoiceCommand
        let voice = firstEnabledCommandLine(storedVoice) ?? "/usr/bin/say -f <text-file> -o <output-file>"
        let storedCombiner = settings["inactive_line_combiner_command"] ?? defaultInactiveLineCombinerCommand
        return RelayConfig(
            voiceCommand: voice,
            voiceProvider: nil,
            voiceVariables: [:],
            voiceProviders: [:],
            combinerCommand: firstEnabledCommandLine(storedCombiner) ?? "",
            combinerVariables: [:],
            cleanupRetentionMinutes: cleanupRetentionMinutesFromSettings(settings)
        )
    }

    static func loadExisting(path: String = relayConfigPath()) throws -> RelayConfig {
        if FileManager.default.fileExists(atPath: path) {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let config = try parseRelayConfigTOML(text)
            try config.validate()
            return config
        }

        throw RelayCliStoreError(message: "config file does not exist: \(path)")
    }

    static func loadOrCreate(settings: [String: String], path: String = relayConfigPath()) throws -> RelayConfig {
        if FileManager.default.fileExists(atPath: path) {
            return try loadExisting(path: path)
        }

        let config = RelayConfig.from(settings: settings)
        try config.validate()
        try config.write(to: path)
        return config
    }

    func write(to path: String = relayConfigPath(), lock: Bool = true) throws {
        if lock {
            try withRelayConfigFileLock(path: path) {
                try writeUnlocked(to: path)
            }
            return
        }

        try writeUnlocked(to: path)
    }

    private func writeUnlocked(to path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try tomlString().write(toFile: path, atomically: true, encoding: .utf8)
    }

    func validate() throws {
        try validateCommandPlaceholders(voiceCommand, allowed: ["<text-file>", "<output-file>", "<voice-id>", "<app-bin>"], label: "voice")
        guard !voiceCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayCliStoreError(message: "voice command is empty")
        }
        if let voiceProvider {
            try validateVoiceProviderName(voiceProvider, line: nil)
            guard voiceProviders[voiceProvider] != nil else {
                throw RelayCliStoreError(message: "voice provider [\(voiceProvider)] section is required")
            }
        }
        for (providerName, provider) in voiceProviders {
            try validateVoiceProviderName(providerName, line: nil)
            try provider.validate(providerName: providerName)
        }
        try validateCommandPlaceholders(combinerCommand, allowed: ["<input>", "<system>"], label: "inactive-line combiner")
        guard (1...maxCleanupRetentionMinutes).contains(cleanupRetentionMinutes) else {
            throw RelayCliStoreError(message: "cleanup retention minutes must be between 1 and \(maxCleanupRetentionMinutes)")
        }
    }

    func tomlString() -> String {
        var lines = [
            "# Tri-State Relay Service advanced config.",
            "# Placeholders are inserted as single argv values, not shell-expanded.",
            "",
            "[voice]",
        ]
        if let voiceProvider {
            lines.append("provider = \(tomlQuotedString(voiceProvider))")
        }
        lines += [
            "command = \(tomlQuotedString(voiceCommand))",
            "",
            "[voice.variables]",
        ]
        lines += voiceVariables.sorted { $0.key < $1.key }.map { "\(tomlBareKey($0.key)) = \(tomlQuotedString($0.value))" }
        for providerName in voiceProviderSerializationOrder() {
            guard let provider = voiceProviders[providerName] else {
                continue
            }
            lines += [
                "",
                "[\(providerName)]",
            ]
            if let defaultVoiceId = provider.defaultVoiceId {
                lines.append("default_voice_id = \(tomlQuotedString(defaultVoiceId))")
            }
            lines.append("auto_assign_line_voices = \(provider.autoAssignLineVoices ? "true" : "false")")
            if let catalogCommand = provider.catalogCommand {
                lines.append("catalog_command = \(tomlQuotedString(catalogCommand))")
            }
            lines.append("assignment_strategy = \(tomlQuotedString(provider.assignmentStrategy))")
            if !provider.lineVoices.isEmpty {
                lines += [
                    "",
                    "[\(providerName).line_voices]",
                ]
                lines += provider.lineVoices.sorted { $0.key < $1.key }.map { "\(tomlBareKey($0.key)) = \(tomlQuotedString($0.value))" }
            }
        }
        lines += [
            "",
            "[combiner]",
            "command = \(tomlQuotedString(combinerCommand))",
            "",
            "[combiner.variables]",
        ]
        lines += combinerVariables.sorted { $0.key < $1.key }.map { "\(tomlBareKey($0.key)) = \(tomlQuotedString($0.value))" }
        lines += [
            "",
            "[retention]",
            "cleanup_retention_minutes = \(cleanupRetentionMinutes)",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    private func voiceProviderSerializationOrder() -> [String] {
        var names = voiceProviders.keys.sorted()
        if let voiceProvider, let index = names.firstIndex(of: voiceProvider) {
            names.remove(at: index)
            names.insert(voiceProvider, at: 0)
        }
        return names
    }
}

let defaultLineVoiceAssignmentStrategy = "stable-hash"

struct RelayVoiceProviderConfig: Equatable {
    var defaultVoiceId: String?
    var autoAssignLineVoices: Bool
    var catalogCommand: String?
    var assignmentStrategy: String
    var lineVoices: [String: String]

    static let empty = RelayVoiceProviderConfig(
        defaultVoiceId: nil,
        autoAssignLineVoices: false,
        catalogCommand: nil,
        assignmentStrategy: defaultLineVoiceAssignmentStrategy,
        lineVoices: [:]
    )

    func validate(providerName: String) throws {
        if let defaultVoiceId {
            try validateVoiceIdentifier(defaultVoiceId, label: "[\(providerName)].default_voice_id")
        }
        if let catalogCommand {
            try validateCommandPlaceholders(catalogCommand, allowed: ["<app-bin>"], label: "voice catalog")
        }
        if autoAssignLineVoices && !commandIsEnabled(catalogCommand) {
            throw RelayCliStoreError(message: "[\(providerName)].catalog_command is required when auto_assign_line_voices is true")
        }
        guard assignmentStrategy == defaultLineVoiceAssignmentStrategy else {
            throw RelayCliStoreError(message: "[\(providerName)].assignment_strategy must be stable-hash")
        }
        for (line, voiceId) in lineVoices {
            guard normalizedLineVoiceKey(line) != nil else {
                throw RelayCliStoreError(message: "[\(providerName).line_voices] line name must not be empty")
            }
            try validateVoiceIdentifier(voiceId, label: "[\(providerName).line_voices].\(line)")
        }
    }
}

func relayConfigPath(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
    if let path = environment[relayConfigPathEnv], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return path
    }

    if let databasePath = environment["TSRS_DB_PATH"], !databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: databasePath).deletingLastPathComponent().appendingPathComponent("config.toml").path
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Tri-State Relay Service/config.toml"
}

private func parseRelayConfigTOML(_ text: String) throws -> RelayConfig {
    var config = RelayConfig(
        voiceCommand: defaultVoiceCommand,
        voiceProvider: nil,
        voiceVariables: [:],
        voiceProviders: [:],
        combinerCommand: defaultInactiveLineCombinerCommand,
        combinerVariables: [:],
        cleanupRetentionMinutes: defaultCleanupRetentionMinutes
    )
    var section = ""
    var lineVoiceKeys: Set<String> = []

    for (index, originalLine) in text.components(separatedBy: .newlines).enumerated() {
        let line = originalLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") {
            continue
        }

        if line.hasPrefix("[") && line.hasSuffix("]") {
            section = String(line.dropFirst().dropLast())
            guard isSupportedRelayConfigSection(section) else {
                throw RelayCliStoreError(message: "config line \(index + 1): unsupported section [\(section)]")
            }
            continue
        }

        let parts = try splitTomlKeyValue(line, line: index + 1)
        let key = try parseTomlKey(parts.key, line: index + 1)
        let value = parts.value

        switch section {
        case "voice" where key == "command":
            config.voiceCommand = try parseTomlString(value, line: index + 1)
        case "voice" where key == "provider":
            let provider = try parseTomlString(value, line: index + 1)
            try validateVoiceProviderName(provider, line: index + 1)
            config.voiceProvider = provider
        case "voice.variables":
            config.voiceVariables[key] = try parseTomlString(value, line: index + 1)
        case "combiner" where key == "command":
            config.combinerCommand = try parseTomlString(value, line: index + 1)
        case "combiner.variables":
            config.combinerVariables[key] = try parseTomlString(value, line: index + 1)
        case "retention" where key == "cleanup_retention_minutes":
            guard let minutes = Int(value) else {
                throw RelayCliStoreError(message: "config line \(index + 1): cleanup_retention_minutes must be an integer")
            }
            config.cleanupRetentionMinutes = minutes
        default:
            if let providerName = providerName(forConfigSection: section) {
                var provider = config.voiceProviders[providerName] ?? .empty
                switch section {
                case let currentSection where currentSection == providerName && key == "default_voice_id":
                    provider.defaultVoiceId = try parseTomlString(value, line: index + 1)
                case let currentSection where currentSection == providerName && key == "auto_assign_line_voices":
                    provider.autoAssignLineVoices = try parseTomlBool(value, line: index + 1)
                case let currentSection where currentSection == providerName && key == "catalog_command":
                    provider.catalogCommand = try parseTomlString(value, line: index + 1)
                case let currentSection where currentSection == providerName && key == "assignment_strategy":
                    provider.assignmentStrategy = try parseTomlString(value, line: index + 1)
                case let currentSection where currentSection == "\(providerName).line_voices":
                    guard let normalized = normalizedLineVoiceKey(key) else {
                        throw RelayCliStoreError(message: "config line \(index + 1): line voice key must not be empty")
                    }
                    let duplicateKey = "\(providerName)\u{0}\(normalized)"
                    guard !lineVoiceKeys.contains(duplicateKey) else {
                        throw RelayCliStoreError(message: "config line \(index + 1): duplicate line voice key \(key)")
                    }
                    lineVoiceKeys.insert(duplicateKey)
                    provider.lineVoices[normalized] = try parseTomlString(value, line: index + 1)
                default:
                    throw RelayCliStoreError(message: "config line \(index + 1): unsupported key \(key)")
                }
                config.voiceProviders[providerName] = provider
            } else {
                throw RelayCliStoreError(message: "config line \(index + 1): unsupported key \(key)")
            }
        }
    }

    return config
}

private func isSupportedRelayConfigSection(_ section: String) -> Bool {
    if ["voice", "voice.variables", "combiner", "combiner.variables", "retention"].contains(section) {
        return true
    }

    return providerName(forConfigSection: section) != nil
}

private func providerName(forConfigSection section: String) -> String? {
    if section.hasSuffix(".line_voices") {
        let providerName = String(section.dropLast(".line_voices".count))
        return isValidVoiceProviderName(providerName) ? providerName : nil
    }

    guard !section.contains("."), isValidVoiceProviderName(section) else {
        return nil
    }
    return section
}

private func parseTomlKey(_ value: String, line: Int) throws -> String {
    if value.hasPrefix("\"") {
        return try parseTomlString(value, line: line)
    }

    guard value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
        throw RelayCliStoreError(message: "config line \(line): expected bare or quoted key")
    }
    return value
}

private func splitTomlKeyValue(_ lineText: String, line: Int) throws -> (key: String, value: String) {
    var quote = false
    var escaped = false
    var index = lineText.startIndex

    while index < lineText.endIndex {
        let character = lineText[index]
        if escaped {
            escaped = false
        } else if quote && character == "\\" {
            escaped = true
        } else if character == "\"" {
            quote.toggle()
        } else if character == "=" && !quote {
            let key = lineText[..<index].trimmingCharacters(in: .whitespaces)
            let valueStart = lineText.index(after: index)
            let value = lineText[valueStart...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else {
                throw RelayCliStoreError(message: "config line \(line): expected key = value")
            }
            return (key, value)
        }
        index = lineText.index(after: index)
    }

    throw RelayCliStoreError(message: "config line \(line): expected key = value")
}

private func parseTomlString(_ value: String, line: Int) throws -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
        throw RelayCliStoreError(message: "config line \(line): expected quoted string")
    }

    let body = String(value.dropFirst().dropLast())
    var output = ""
    var escaped = false

    for character in body {
        if escaped {
            switch character {
            case "n": output.append("\n")
            case "t": output.append("\t")
            case "\"": output.append("\"")
            case "\\": output.append("\\")
            default:
                throw RelayCliStoreError(message: "config line \(line): unsupported escape \\" + String(character))
            }
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else {
            output.append(character)
        }
    }

    if escaped {
        throw RelayCliStoreError(message: "config line \(line): unterminated escape")
    }

    return output
}

private func parseTomlBool(_ value: String, line: Int) throws -> Bool {
    if value == "true" {
        return true
    }
    if value == "false" {
        return false
    }
    throw RelayCliStoreError(message: "config line \(line): expected true or false")
}

private func tomlQuotedString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

private func tomlBareKey(_ value: String) -> String {
    if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
        return value
    }

    return tomlQuotedString(value)
}

private func validateCommandPlaceholders(_ command: String, allowed: Set<String>, label: String) throws {
    let pattern = #"<[^>\s]+>"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return
    }
    let range = NSRange(command.startIndex..<command.endIndex, in: command)
    for match in expression.matches(in: command, range: range) {
        guard let placeholderRange = Range(match.range, in: command) else {
            continue
        }
        let placeholder = String(command[placeholderRange])
        if !allowed.contains(placeholder) {
            throw RelayCliStoreError(message: "\(label) command contains unsupported placeholder \(placeholder)")
        }
    }
}

private func isValidVoiceProviderName(_ provider: String) -> Bool {
    guard provider.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
        return false
    }
    return !["voice", "combiner", "retention"].contains(provider)
}

private func validateVoiceProviderName(_ provider: String, line: Int?) throws {
    guard isValidVoiceProviderName(provider) else {
        if let line {
            throw RelayCliStoreError(message: "config line \(line): invalid voice provider name \(provider)")
        }
        throw RelayCliStoreError(message: "invalid voice provider name \(provider)")
    }
}

private func validateVoiceIdentifier(_ value: String, label: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw RelayCliStoreError(message: "\(label) must not be empty")
    }
    guard value.rangeOfCharacter(from: .newlines) == nil else {
        throw RelayCliStoreError(message: "\(label) must be one line")
    }
}

func normalizedLineVoiceKey(_ line: String?) -> String? {
    let normalized = normalizeRelayWhitespace(line ?? "")
    guard !normalized.isEmpty else {
        return nil
    }
    return normalized
}

func resolvedVoiceIdentifier(for line: String?, config: RelayConfig, selectedVoice: String?) -> String {
    if let provider = config.activeVoiceProvider {
        if let lineKey = normalizedLineVoiceKey(line), let voiceId = provider.lineVoices[lineKey] {
            return voiceId
        }
        if let defaultVoiceId = provider.defaultVoiceId, !defaultVoiceId.isEmpty {
            return defaultVoiceId
        }
    }

    let selected = selectedVoice?.trimmingCharacters(in: .whitespacesAndNewlines)
    return selected?.isEmpty == false ? selected! : defaultSpeechUsageVoiceIdentifier
}

struct RelayVoiceResolution {
    let voiceIdentifier: String
    let provider: String?
    let diagnostic: String?
}

func resolvedVoiceIdentifierForPlayback(
    line: String?,
    selectedVoice: String?,
    configPath: String = relayConfigPath(),
    appBin: String = "",
    catalogRunner: ([String]) throws -> [String] = runVoiceCatalogCommand
) -> RelayVoiceResolution {
    var diagnostic: String?
    do {
        _ = try autoAssignLineVoiceIfNeeded(line: line, configPath: configPath, appBin: appBin, catalogRunner: catalogRunner)
    } catch {
        diagnostic = "voice catalog assignment failed: \(relayConfigErrorMessage(error))"
    }

    if let config = try? RelayConfig.loadExisting(path: configPath) {
        let voiceIdentifier = config.voiceCommand.contains("<voice-id>")
            ? resolvedVoiceIdentifier(for: line, config: config, selectedVoice: selectedVoice)
            : (selectedVoice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? selectedVoice! : defaultSpeechUsageVoiceIdentifier)
        return RelayVoiceResolution(
            voiceIdentifier: voiceIdentifier,
            provider: config.voiceProvider,
            diagnostic: diagnostic
        )
    }

    return RelayVoiceResolution(
        voiceIdentifier: selectedVoice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? selectedVoice! : defaultSpeechUsageVoiceIdentifier,
        provider: nil,
        diagnostic: diagnostic
    )
}

@discardableResult
func autoAssignLineVoiceIfNeeded(
    line: String?,
    configPath: String = relayConfigPath(),
    appBin: String = "",
    catalogRunner: ([String]) throws -> [String] = runVoiceCatalogCommand
) throws -> String? {
    let config = try RelayConfig.loadExisting(path: configPath)
    guard
        config.voiceCommand.contains("<voice-id>"),
        let providerName = config.voiceProvider,
        let provider = config.voiceProviders[providerName],
        provider.autoAssignLineVoices,
        let lineKey = normalizedLineVoiceKey(line),
        provider.lineVoices[lineKey] == nil,
        let catalogCommand = firstEnabledCommandLine(provider.catalogCommand)
    else {
        return nil
    }

    let catalog = try catalogRunner(voiceCatalogCommandArguments(catalogCommand, appBin: appBin))
    let voiceIds = stableVoiceCatalogIDs(catalog)
    guard !voiceIds.isEmpty else {
        return nil
    }
    let assignedVoiceId = voiceIds[stableLineVoiceIndex(lineKey, count: voiceIds.count)]

    return try withRelayConfigFileLock(path: configPath) {
        var freshConfig = try RelayConfig.loadExisting(path: configPath)
        guard
            freshConfig.voiceCommand.contains("<voice-id>"),
            freshConfig.voiceProvider == providerName,
            var freshProvider = freshConfig.voiceProviders[providerName],
            freshProvider.autoAssignLineVoices,
            freshProvider.lineVoices[lineKey] == nil
        else {
            return nil
        }

        freshProvider.lineVoices[lineKey] = assignedVoiceId
        freshConfig.voiceProviders[providerName] = freshProvider
        try freshConfig.validate()
        try freshConfig.write(to: configPath, lock: false)
        return assignedVoiceId
    }
}

func voiceCatalogCommandArguments(_ commandLine: String, appBin: String = "") throws -> [String] {
    try splitCommandLine(commandLine).map {
        $0.replacingOccurrences(of: "<app-bin>", with: appBin)
    }
}

private func runVoiceCatalogCommand(_ commandParts: [String]) throws -> [String] {
    guard let executable = commandParts.first else {
        throw RelayCliStoreError(message: "voice catalog command is empty")
    }

    let process = Process()
    if executable.contains("/") {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(commandParts.dropFirst())
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = commandParts
    }
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        semaphore.signal()
    }
    try process.run()
    let completed = semaphore.wait(timeout: .now() + 60) == .success
    if !completed {
        process.terminate()
        throw RelayCliStoreError(message: "voice catalog command timed out")
    }

    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        let detail = redactedVoiceProviderDiagnostic(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        throw RelayCliStoreError(message: detail.isEmpty ? "voice catalog command failed" : "voice catalog command failed: \(detail)")
    }

    return try parseVoiceCatalogOutput(stdout)
}

func parseVoiceCatalogOutput(_ output: String) throws -> [String] {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return []
    }

    if let data = trimmed.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
        if let ids = object as? [String] {
            return stableVoiceCatalogIDs(ids)
        }
        if let objects = object as? [[String: Any]] {
            return stableVoiceCatalogIDs(objects.compactMap { ($0["id"] ?? $0["voice_id"]) as? String })
        }
        if let dictionary = object as? [String: Any], let voices = dictionary["voices"] {
            if let ids = voices as? [String] {
                return stableVoiceCatalogIDs(ids)
            }
            if let objects = voices as? [[String: Any]] {
                return stableVoiceCatalogIDs(objects.compactMap { ($0["id"] ?? $0["voice_id"]) as? String })
            }
        }
        throw RelayCliStoreError(message: "voice catalog command must return voice ids")
    }

    return stableVoiceCatalogIDs(trimmed.components(separatedBy: .newlines))
}

private func stableVoiceCatalogIDs(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    var stable: [String] = []
    for id in ids {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .newlines) == nil, !seen.contains(trimmed) else {
            continue
        }
        seen.insert(trimmed)
        stable.append(trimmed)
    }
    return stable
}

private func stableLineVoiceIndex(_ line: String, count: Int) -> Int {
    guard count > 0 else {
        return 0
    }
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in line.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return Int(hash % UInt64(count))
}

private func redactedVoiceProviderDiagnostic(_ message: String) -> String {
    message
        .replacingOccurrences(of: #"(?i)(bearer\s+)[^\s"]+"#, with: "$1[redacted]", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)(api[_-]?key["'\s:=]+)[^"'\s]+"#, with: "$1[redacted]", options: .regularExpression)
}

func updateRelayConfig(
    path: String = relayConfigPath(),
    fallbackSettings: [String: String]? = nil,
    _ update: (inout RelayConfig) throws -> Void
) throws -> RelayConfig {
    try withRelayConfigFileLock(path: path) {
        let config: RelayConfig
        if FileManager.default.fileExists(atPath: path) {
            do {
                config = try RelayConfig.loadExisting(path: path)
            } catch {
                guard let fallbackSettings else {
                    throw error
                }
                config = RelayConfig.from(settings: fallbackSettings)
            }
        } else if let fallbackSettings {
            config = RelayConfig.from(settings: fallbackSettings)
        } else {
            throw RelayCliStoreError(message: "config file does not exist: \(path)")
        }

        var updated = config
        try update(&updated)
        try updated.validate()
        try updated.write(to: path, lock: false)
        return updated
    }
}

private func withRelayConfigFileLock<T>(path: String, _ body: () throws -> T) throws -> T {
    let lockPath = "\(path).lock"
    let directory = URL(fileURLWithPath: lockPath).deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
        throw RelayCliStoreError(message: "could not open config lock: \(lockPath)")
    }
    defer {
        close(descriptor)
    }

    guard flock(descriptor, LOCK_EX) == 0 else {
        throw RelayCliStoreError(message: "could not lock config: \(lockPath)")
    }
    defer {
        flock(descriptor, LOCK_UN)
    }

    return try body()
}

private func cleanupRetentionMinutesFromSettings(_ settings: [String: String]) -> Int {
    guard let value = settings["cleanup_retention_minutes"], let minutes = Int(value), (1...maxCleanupRetentionMinutes).contains(minutes) else {
        return defaultCleanupRetentionMinutes
    }

    return minutes
}

func relayConfigErrorMessage(_ error: Error) -> String {
    if let error = error as? RelayCliStoreError {
        return error.message
    }

    return error.localizedDescription
}

// Mirrors core/message.ts spokenText: optional line prefix, type prefix for
// non-update relays, then the message body.
func spokenRelayText(line: String, type: String, message: String, includeLine: Bool) -> String {
    let typePrefix = type == "update" ? "" : "\(type). "
    let linePrefix = includeLine ? "\(line). " : ""
    return "\(linePrefix)\(typePrefix)\(message)"
}

let defaultSpeechUsageProvider = "apple"
let defaultSpeechUsageModel = "direct-say"
let defaultSpeechUsageVoiceIdentifier = "default"

struct RelayCliResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct RelayEnqueueOutcome {
    let relay: RelayCliStoredRelay?
}

let relayCliUsage = """
Usage: relay <command> [options]

Commands:
  --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and enqueue a relay.
  list                 List relays.
  status               Print queue status JSON.
  state                Print focus/ready/mute state.
  ready                Release one relay.
  live                 Play new relays automatically, grouped by line.
  focus                Keep queued relays quiet.
  mute                 Mute playback.
  unmute               Unmute playback.
  clear                Clear queued and delivered relays.
  clear-line --line <line>
                       Clear queued relays for one line.
  clear-delivered [--line <line>]
                       Clear delivered relays.
  skip-next [--line <line>]
                       Skip the next queued relay.
  acknowledge [--line <line>]
                       Mark the latest delivered relay handled.
  replay-last [--line <line>]
                       Replay the latest delivered relay.
  line [line|--line <line>]
                       Get or set active line.
  combiner             Get inactive-line combiner command.
  config [path|show|validate|reload]
  config set [--voice-command <command>] [--combiner-command <command>]
             [--cleanup-retention-minutes <minutes>]
                       Inspect, validate, and update TOML-backed advanced config.
  first-start [status|reset|complete]
                       Inspect or change only first-start setup completion.
  first-start dev-reset-database --confirm
                       Development-only: delete relay.db, relay.db-wal, and
                       relay.db-shm, then recreate a fresh first-start DB.
  app-claim-next [--line <line>]
                       Claim the next eligible relay for app-owned playback.
  app-mark-heard --id <id>
                       Mark a relay delivered and record the spoken line.
  app-mark-failed --id <id>
                       Mark a relay failed.
  debug wake            Post the app wake notification without changing queue data.
  debug open-settings [--panel setup|voice|secondary|advanced]
                       Ask the app to open Settings without changing playback state.
  debug settings-roundtrip --voice-command <command> --combiner-command <command>
            --cleanup-retention-minutes <minutes>
                       Ask the app to edit Settings controls for UI smoke tests.
  normalize --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and normalize a relay without writing to the queue.
  --version            Print the CLI version.
  help                 Print this help.

This Swift target is the active `relay` CLI implementation. See
docs/cli-parity-inventory.md for the validation inventory.
"""

// Pure argument dispatcher so behavior is testable without a process boundary.
func runRelayCli(_ arguments: [String], version: String = relayCliVersion, wakeNotifier: RelayWakeNotifier = .darwin) -> RelayCliResult {
    guard let command = arguments.first else {
        return RelayCliResult(stdout: relayCliUsage, stderr: "", exitCode: 0)
    }

    switch command {
    case "--version", "version":
        return RelayCliResult(stdout: "relay \(version)", stderr: "", exitCode: 0)
    case "help", "--help", "-h":
        return RelayCliResult(stdout: relayCliUsage, stderr: "", exitCode: 0)
    case "list":
        return withRelayCliStore { store in
            let state = try store.state()
            let relays = try store.list()
            let lines = ["mode=\(state.mode) muted=\(state.muted)"] + relays.map {
                "#\($0.id) [\($0.status)] [\($0.priority)] \($0.line): \($0.message)"
            }
            return RelayCliResult(stdout: lines.joined(separator: "\n"), stderr: "", exitCode: 0)
        }
    case "status":
        return withRelayCliStore { store in
            let status = try store.statusJSON()
            return RelayCliResult(stdout: status, stderr: "", exitCode: 0)
        }
    case "state":
        return withRelayCliStore { store in
            let state = try store.state()
            let muted = state.muted ? ", muted" : ""
            return RelayCliResult(
                stdout: "\(state.mode)\(muted), active-line=\(state.activeLine ?? "none"), inactive-line-combiner=\(state.inactiveLineCombiner)",
                stderr: "",
                exitCode: 0
            )
        }
    case "ready":
        return withRelayCliStore { store in
            let state = try store.setMode("ready")
            wakeNotifier.post()
            return RelayCliResult(stdout: state.muted ? "release queued, but muted is on" : "ready to release one relay", stderr: "", exitCode: 0)
        }
    case "live":
        return withRelayCliStore { store in
            let state = try store.setMode("live")
            wakeNotifier.post()
            return RelayCliResult(stdout: state.muted ? "live mode on, but muted is on" : "live mode on", stderr: "", exitCode: 0)
        }
    case "focus":
        return withRelayCliStore { store in
            _ = try store.setMode("focus")
            wakeNotifier.post()
            return RelayCliResult(stdout: "focus mode on", stderr: "", exitCode: 0)
        }
    case "mute":
        return withRelayCliStore { store in
            try store.setMuted(true)
            wakeNotifier.post()
            return RelayCliResult(stdout: "muted", stderr: "", exitCode: 0)
        }
    case "unmute":
        return withRelayCliStore { store in
            try store.setMuted(false)
            wakeNotifier.post()
            return RelayCliResult(stdout: "unmuted", stderr: "", exitCode: 0)
        }
    case "clear":
        return withRelayCliStore { store in
            let count = try store.clear()
            if count > 0 {
                wakeNotifier.post()
            }
            return RelayCliResult(stdout: "cleared \(count) relays", stderr: "", exitCode: 0)
        }
    case "clear-line":
        return runLineRequiredCommand(Array(arguments.dropFirst())) { store, line in
            let count = try store.clearQueued(line: line)
            if count > 0 {
                wakeNotifier.post()
            }
            return RelayCliResult(stdout: "cleared \(count) queued relays from \(line)", stderr: "", exitCode: 0)
        }
    case "clear-delivered", "clear-heard":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            let count = try store.clearHeard(line: line)
            if count > 0 {
                wakeNotifier.post()
            }
            return RelayCliResult(stdout: "cleared \(count) delivered relays", stderr: "", exitCode: 0)
        }
    case "skip-next":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let skipped = try store.skipNextQueued(line: line) {
                wakeNotifier.post()
                return RelayCliResult(stdout: "skipped relay #\(skipped.id)", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no queued relay to skip", stderr: "", exitCode: 0)
        }
    case "acknowledge", "mark-handled":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let handled = try store.markLatestHeardHandled(line: line) {
                wakeNotifier.post()
                return RelayCliResult(stdout: "handled relay #\(handled.id)", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no delivered relay to mark handled", stderr: "", exitCode: 0)
        }
    case "replay-last":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let replayed = try store.replayLatestHeard(line: line) {
                wakeNotifier.post()
                return RelayCliResult(stdout: "queued relay #\(replayed.id) for replay", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no delivered relay to replay", stderr: "", exitCode: 0)
        }
    case "line":
        return runLineCommand(Array(arguments.dropFirst()), wakeNotifier: wakeNotifier)
    case "combiner":
        return runCombinerCommand(Array(arguments.dropFirst()), wakeNotifier: wakeNotifier)
    case "config":
        return runConfigCommand(Array(arguments.dropFirst()), wakeNotifier: wakeNotifier)
    case "first-start":
        return runFirstStartCommand(Array(arguments.dropFirst()), wakeNotifier: wakeNotifier)
    case "app-claim-next":
        return runAppClaimNextCommand(Array(arguments.dropFirst()))
    case "app-mark-heard":
        return runAppMarkStatusCommand(Array(arguments.dropFirst()), status: "heard", recordSpoken: true)
    case "app-mark-failed":
        return runAppMarkStatusCommand(Array(arguments.dropFirst()), status: "failed", recordSpoken: false)
    case "cli-status":
        return runCliStatusCommand(Array(arguments.dropFirst()))
    case "install-cli":
        return runInstallCliCommand(Array(arguments.dropFirst()))
    case "debug":
        return runDebugCommand(Array(arguments.dropFirst()), wakeNotifier: wakeNotifier)
    case "normalize":
        return runNormalizeCommand(Array(arguments.dropFirst()))
    default:
        if command.hasPrefix("--") || command == "enqueue" {
            return runEnqueueCommand(command == "enqueue" ? Array(arguments.dropFirst()) : arguments, wakeNotifier: wakeNotifier)
        }

        return RelayCliResult(stdout: "", stderr: "unknown command: \(command)\n\(relayCliUsage)", exitCode: 1)
    }
}

private func withRelayCliStore(_ action: (RelayCliStore) throws -> RelayCliResult) -> RelayCliResult {
    do {
        let store = try RelayCliStore(path: relayCliDatabasePath())
        defer {
            store.close()
        }
        return try action(store)
    } catch let error as RelayValidationError {
        return RelayCliResult(stdout: "", stderr: error.errorDescription ?? "invalid relay", exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runEnqueueCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
    let flags: [String: String]

    do {
        flags = try parseRelayFlags(arguments)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }

    return withRelayCliStore { store in
        let outcome = try store.enqueue(NewRelayInput(
            line: flags["line"],
            message: flags["message"] ?? "",
            type: flags["type"],
            priority: flags["priority"],
            session: flags["session"],
            app: flags["app"],
            cwd: flags["cwd"],
            url: flags["url"]
        ))

        guard let relay = outcome.relay else {
            return RelayCliResult(stdout: "inactive relay dropped", stderr: "", exitCode: 0)
        }

        wakeNotifier.post()
        return RelayCliResult(stdout: "queued relay #\(relay.id) \(relay.line): \(relay.message)", stderr: "", exitCode: 0)
    }
}

private func runCliStatusCommand(_ arguments: [String]) -> RelayCliResult {
    do {
        let flags = try parseRelayFlags(arguments, knownFlags: relayCliInstallFlags)
        return RelayCliResult(stdout: try cliInstallStatus(sourcePath: flags["source"], targetPath: flags["target"]).json(), stderr: "", exitCode: 0)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runInstallCliCommand(_ arguments: [String]) -> RelayCliResult {
    do {
        let flags = try parseRelayFlags(arguments, knownFlags: relayCliInstallFlags)
        let status = try installRelayCli(sourcePath: flags["source"], targetPath: flags["target"])
        return RelayCliResult(stdout: try status.json(), stderr: "", exitCode: 0)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runOptionalLineCommand(_ arguments: [String], action: (RelayCliStore, String?) throws -> RelayCliResult) -> RelayCliResult {
        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
            return withRelayCliStore { store in
                try action(store, flags["line"])
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runLineRequiredCommand(_ arguments: [String], action: (RelayCliStore, String) throws -> RelayCliResult) -> RelayCliResult {
        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
            guard let line = flags["line"] else {
                return RelayCliResult(stdout: "", stderr: "line is required", exitCode: 1)
            }
            return withRelayCliStore { store in
                try action(store, line)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runLineCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
        if arguments.isEmpty {
            return withRelayCliStore { store in
                RelayCliResult(stdout: try store.state().activeLine ?? "none", stderr: "", exitCode: 0)
            }
        }

        do {
            let line: String
            if arguments.first == "--line" {
                let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
                guard let requested = flags["line"] else {
                    return RelayCliResult(stdout: "", stderr: "line is required", exitCode: 1)
                }
                line = requested
            } else {
                line = arguments[0]
            }

            return withRelayCliStore { store in
                let state = try store.setActiveLine(line)
                wakeNotifier.post()
                return RelayCliResult(stdout: "active line set to \(state.activeLine ?? line)", stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runCombinerCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
        if arguments.isEmpty {
            return withRelayCliStore { store in
                RelayCliResult(stdout: try store.inactiveLineCombinerCommand(), stderr: "", exitCode: 0)
            }
        }

        return RelayCliResult(stdout: "", stderr: "combiner is read-only; use config set --combiner-command", exitCode: 1)
}

private func runConfigCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
    let action = arguments.first ?? "show"

    if action == "set" {
        do {
            let flags = try parseRelayFlags(Array(arguments.dropFirst()), knownFlags: ["combiner-command", "voice-command", "cleanup-retention-minutes"])
            guard !flags.isEmpty else {
                return RelayCliResult(stdout: "", stderr: "config set requires at least one flag", exitCode: 1)
            }
            return withRelayCliStore { store in
                let config = try store.setAdvancedConfig(
                    voiceCommand: flags["voice-command"],
                    combinerCommand: flags["combiner-command"],
                    cleanupRetentionMinutes: flags["cleanup-retention-minutes"]
                )
                wakeNotifier.post()
                return RelayCliResult(stdout: config.tomlString(), stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    guard arguments.count <= 1 else {
        return RelayCliResult(stdout: "", stderr: "config accepts one action: path, show, validate, reload, or set", exitCode: 1)
    }

    if action == "path" {
        return RelayCliResult(stdout: relayConfigPath(), stderr: "", exitCode: 0)
    }

    guard ["show", "validate", "reload"].contains(action) else {
        return RelayCliResult(stdout: "", stderr: "config action must be path, show, validate, reload, or set", exitCode: 1)
    }

    return withRelayCliStore { store in
        let path = relayConfigPath()
        let config = try RelayConfig.loadExisting(path: path)
        switch action {
        case "show":
            return RelayCliResult(stdout: config.tomlString(), stderr: "", exitCode: 0)
        case "validate":
            return RelayCliResult(stdout: "config valid: \(path)", stderr: "", exitCode: 0)
        default:
            wakeNotifier.post()
            return RelayCliResult(stdout: "config valid; reload requested", stderr: "", exitCode: 0)
        }
    }
}

private func runFirstStartCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
    let action = arguments.first ?? "status"

    if action == "dev-reset-database" {
        guard arguments == ["dev-reset-database", "--confirm"] else {
            return RelayCliResult(stdout: "", stderr: "dev-reset-database requires --confirm and clears all local relay data", exitCode: 1)
        }

        do {
            try resetRelayDatabaseForFirstStartDevelopment()
            return withRelayCliStore { store in
                wakeNotifier.post()
                return RelayCliResult(stdout: try store.firstStartSetupComplete() ? "fresh database recreated, first-start complete" : "fresh database recreated, first-start needs-setup", stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliStoreError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    guard arguments.count <= 1 else {
        return RelayCliResult(stdout: "", stderr: "first-start accepts one action, except dev-reset-database --confirm", exitCode: 1)
    }

    return withRelayCliStore { store in
        switch action {
        case "status":
            return RelayCliResult(stdout: try store.firstStartSetupComplete() ? "complete" : "needs-setup", stderr: "", exitCode: 0)
        case "reset":
            try store.setFirstStartSetupComplete(false)
            wakeNotifier.post()
            return RelayCliResult(stdout: "first-start setup reset to needs-setup", stderr: "", exitCode: 0)
        case "complete":
            try store.setFirstStartSetupComplete(true)
            wakeNotifier.post()
            return RelayCliResult(stdout: "first-start setup marked complete", stderr: "", exitCode: 0)
        default:
            return RelayCliResult(stdout: "", stderr: "first-start action must be status, reset, or complete", exitCode: 1)
        }
    }
}

private func runDebugCommand(_ arguments: [String], wakeNotifier: RelayWakeNotifier) -> RelayCliResult {
    guard let action = arguments.first else {
        return RelayCliResult(stdout: "", stderr: "debug action must be wake, open-settings, or settings-roundtrip", exitCode: 1)
    }

    if action == "wake" {
        guard arguments.count == 1 else {
            return RelayCliResult(stdout: "", stderr: "debug wake does not accept arguments", exitCode: 1)
        }
        wakeNotifier.post()
        return RelayCliResult(stdout: "posted queue wake notification", stderr: "", exitCode: 0)
    }

    if action == "open-settings" {
        do {
            let flags = try parseRelayFlags(Array(arguments.dropFirst()), knownFlags: ["panel"])
            let panel = flags["panel"]
            if let panel, !relayDebugOpenSettingsPanels.contains(panel) {
                return RelayCliResult(stdout: "", stderr: "settings panel must be setup, voice, secondary, or advanced", exitCode: 1)
            }
            let result = withRelayCliStore { store in
                try store.setDebugOpenSettingsPanel(panel ?? "__default__")
                return RelayCliResult(stdout: "", stderr: "", exitCode: 0)
            }
            if result.exitCode != 0 {
                return result
            }
            wakeNotifier.post()
            postRelayDebugOpenSettingsNotification(panel: panel)
            let suffix = panel.map { " for \($0)" } ?? ""
            return RelayCliResult(stdout: "posted settings open notification\(suffix)", stderr: "", exitCode: 0)
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    if action == "settings-roundtrip" {
        do {
            let flags = try parseRelayFlags(Array(arguments.dropFirst()), knownFlags: ["voice-command", "combiner-command", "cleanup-retention-minutes"])
            guard let voiceCommand = flags["voice-command"], let combinerCommand = flags["combiner-command"], let retentionMinutes = flags["cleanup-retention-minutes"] else {
                return RelayCliResult(stdout: "", stderr: "settings-roundtrip requires --voice-command, --combiner-command, and --cleanup-retention-minutes", exitCode: 1)
            }
            guard Int(retentionMinutes) != nil else {
                return RelayCliResult(stdout: "", stderr: "cleanup-retention-minutes must be an integer", exitCode: 1)
            }
            let result = withRelayCliStore { store in
                try store.setDebugSettingsRoundtrip(voiceCommand: voiceCommand, combinerCommand: combinerCommand, cleanupRetentionMinutes: retentionMinutes)
                return RelayCliResult(stdout: "", stderr: "", exitCode: 0)
            }
            if result.exitCode != 0 {
                return result
            }
            wakeNotifier.post()
            postRelayDebugOpenSettingsNotification(panel: "voice")
            return RelayCliResult(stdout: "posted settings roundtrip request", stderr: "", exitCode: 0)
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    return RelayCliResult(stdout: "", stderr: "debug action must be wake, open-settings, or settings-roundtrip", exitCode: 1)
}

private func resetRelayDatabaseForFirstStartDevelopment() throws {
    let databasePath = relayCliDatabasePath()
    let manager = FileManager.default

    for path in [databasePath, "\(databasePath)-wal", "\(databasePath)-shm"] {
        if manager.fileExists(atPath: path) {
            do {
                try manager.removeItem(atPath: path)
            } catch {
                throw RelayCliStoreError(message: "could not remove \(path): \(error.localizedDescription)")
            }
        }
    }
}

private func runAppClaimNextCommand(_ arguments: [String]) -> RelayCliResult {
    guard processorIsAppAuthorized() else {
        return RelayCliResult(stdout: "", stderr: "app helper commands require TSRS app authorization", exitCode: 1)
    }

    do {
        let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
        return withRelayCliStore { store in
            _ = try store.failStaleSpeaking()
            let activeLine = try store.state().activeLine

            let relay: RelayCliStoredRelay?
            if let line = flags["line"] {
                relay = try store.claimNextForLine(line)
            } else if let activeLine, try store.queuedCountForLine(activeLine) > 0, try store.state().mode != "live" {
                relay = try store.claimNextForLine(activeLine)
            } else {
                relay = try store.claimNextForSpeech()
            }

            guard let relay else {
                return RelayCliResult(stdout: "null", stderr: "", exitCode: 0)
            }

            let includeLine = try store.shouldPrefixSpokenLine(relay.line)
            let text = spokenRelayText(line: relay.line, type: relay.type, message: relay.message, includeLine: includeLine)
            let json = try jsonString([
                "id": relay.id,
                "text": text,
                "line": relay.line,
            ])
            return RelayCliResult(stdout: json, stderr: "", exitCode: 0)
        }
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runAppMarkStatusCommand(_ arguments: [String], status: String, recordSpoken: Bool) -> RelayCliResult {
    guard processorIsAppAuthorized() else {
        return RelayCliResult(stdout: "", stderr: "app helper commands require TSRS app authorization", exitCode: 1)
    }

    do {
        let flags = try parseRelayFlags(arguments, knownFlags: ["id"])
        guard let idText = flags["id"], let id = Int(idText) else {
            return RelayCliResult(stdout: "", stderr: "id is required", exitCode: 1)
        }
        return withRelayCliStore { store in
            let relay = try store.markStatus(id: id, status: status)
            if recordSpoken {
                let includeLine = try store.shouldPrefixSpokenLine(relay.line)
                let text = spokenRelayText(line: relay.line, type: relay.type, message: relay.message, includeLine: includeLine)
                try store.recordSpokenUsage(
                    line: relay.line,
                    provider: defaultSpeechUsageProvider,
                    model: defaultSpeechUsageModel,
                    voiceIdentifier: defaultSpeechUsageVoiceIdentifier,
                    characterCount: text.count
                )
                try store.recordSpokenLine(relay.line)
            }
            return RelayCliResult(stdout: "\(status) #\(relay.id)", stderr: "", exitCode: 0)
        }
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runNormalizeCommand(_ arguments: [String]) -> RelayCliResult {
    let flags: [String: String]

    do {
        flags = try parseRelayFlags(arguments)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }

    let input = NewRelayInput(
        line: flags["line"],
        message: flags["message"] ?? "",
        type: flags["type"],
        priority: flags["priority"],
        session: flags["session"],
        app: flags["app"],
        cwd: flags["cwd"],
        url: flags["url"]
    )

    do {
        let relay = try normalizeRelay(input)
        let stdout = "normalized \(relay.line): \(relay.message) (type=\(relay.type) priority=\(relay.priority))"
        return RelayCliResult(stdout: stdout, stderr: "", exitCode: 0)
    } catch let error as RelayValidationError {
        return RelayCliResult(stdout: "", stderr: error.errorDescription ?? "invalid relay", exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private struct RelayCliFlagError: Error {
    let message: String
}

private let relayCliKnownFlags: Set<String> = [
    "line", "message", "type", "priority", "session", "app", "cwd", "url",
]
private let relayCliInstallFlags: Set<String> = ["source", "target"]

private func parseRelayFlags(_ arguments: [String]) throws -> [String: String] {
    try parseRelayFlags(arguments, knownFlags: relayCliKnownFlags)
}

private func parseRelayFlags(_ arguments: [String], knownFlags: Set<String>) throws -> [String: String] {
    var flags: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let token = arguments[index]

        guard token.hasPrefix("--") else {
            throw RelayCliFlagError(message: "unexpected argument: \(token)")
        }

        let name = String(token.dropFirst(2))

        guard knownFlags.contains(name) else {
            throw RelayCliFlagError(message: "unknown flag: \(token)")
        }

        guard index + 1 < arguments.count else {
            throw RelayCliFlagError(message: "missing value for \(token)")
        }

        flags[name] = arguments[index + 1]
        index += 2
    }

    return flags
}

// MARK: - SQLite queue store

struct RelayCliStoredRelay {
    let id: Int
    let line: String
    let message: String
    let type: String
    let priority: String
    let status: String
}

struct RelayCliQueueState {
    let mode: String
    let muted: Bool
    let inactiveLineCombiner: String
    let activeLine: String?
}

private struct RelayCliStoreError: Error {
    let message: String
}

private final class RelayCliStore {
    private let database: OpaquePointer

    init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            throw RelayCliStoreError(message: "could not open relay database")
        }

        database = opened
        sqlite3_busy_timeout(database, 2_000)
        try migrate()
    }

    func close() {
        sqlite3_close(database)
    }

    func enqueue(_ input: NewRelayInput) throws -> RelayEnqueueOutcome {
        let relay = try normalizeRelay(input)
        let state = try state()

        if state.mode != "live", let activeLine = state.activeLine, relay.line != activeLine {
            let combined = try combineInactiveRelay(
                activeLine: activeLine,
                incoming: relay,
                existing: latestQueuedRelay(line: relay.line),
                command: inactiveLineCombinerCommand()
            )
            guard let combinedRelay = combined.relay else {
                return RelayEnqueueOutcome(relay: nil)
            }

            _ = try clearQueued(line: relay.line)
            return RelayEnqueueOutcome(relay: try insertRelay(combinedRelay))
        }

        let inserted = try insertRelay(relay)
        try setSettingIfMissing(key: "active_line", value: inserted.line)
        return RelayEnqueueOutcome(relay: inserted)
    }

    private func insertRelay(_ relay: NormalizedRelay) throws -> RelayCliStoredRelay {
        let now = nowString()
        return try returningRelay("""
            INSERT INTO relays (
              line, message, type, priority, session, app, cwd, url, status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
            RETURNING id, line, message, type, priority, status
        """, [
            relay.line,
            relay.message,
            relay.type,
            relay.priority,
            relay.session,
            relay.app,
            relay.cwd,
            relay.url,
            now,
            now,
        ])
    }

    private func latestQueuedRelay(line: String) throws -> RelayCliStoredRelay? {
        try optionalReturningRelay("""
            SELECT id, line, message, type, priority, status
            FROM relays
            WHERE status = 'queued' AND line = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
        """, [line])
    }

    func queuedCountForLine(_ line: String) throws -> Int {
        var count = 0
        try query("""
            SELECT COUNT(*) AS count
            FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line]) { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        return count
    }

    func list(limit: Int = 20) throws -> [RelayCliStoredRelay] {
        var relays: [RelayCliStoredRelay] = []
        try query("""
            SELECT id, line, message, type, priority, status
            FROM relays
            ORDER BY
              CASE status
                WHEN 'speaking' THEN 0
                WHEN 'queued' THEN 1
                WHEN 'heard' THEN 2
                ELSE 3
              END,
              created_at ASC
            LIMIT ?
        """, [String(limit)]) { statement in
            relays.append(mapRelay(statement))
        }
        return relays
    }

    func state() throws -> RelayCliQueueState {
        let settings = try rawSettings()
        let config = try validConfigIfAvailable()
        return RelayCliQueueState(
            mode: playbackMode(settings["mode"]),
            muted: settings["muted"] == "true" || config == nil,
            inactiveLineCombiner: config.map { commandIsEnabled($0.combinerCommand) ? "custom" : "none" } ?? "none",
            activeLine: settings["active_line"]
        )
    }

    func statusJSON() throws -> String {
        _ = try expireStaleRelays()
        let state = try state()
        let config = try validConfigIfAvailable()
        let counts = try countsByStatus()
        let lines = try lineSummaries()
        var object: [String: Any] = [
            "profile": "direct",
            "mode": state.mode,
            "muted": state.muted,
            "configPath": relayConfigPath(),
            "configError": try configError() as Any,
            "inactiveLineCombiner": state.inactiveLineCombiner,
            "inactiveLineCombinerCommand": try inactiveLineCombinerCommand(),
            "speechCommand": try speechCommand(),
            "voiceCommand": try voiceCommand(),
            "voiceCommandLastError": try voiceCommandLastError() as Any,
            "cleanupRetentionMinutes": try cleanupRetentionMinutes(),
            "activeLine": state.activeLine as Any,
            "counts": counts,
            "queueCount": counts["queued"] ?? 0,
            "attentionCount": (counts["queued"] ?? 0) + (counts["heard"] ?? 0) + (counts["failed"] ?? 0),
            "overview": try queueOverview(),
            "lines": lines,
            "spokenUsage": try spokenUsageSummary(),
            "capabilities": directRelayCapabilities,
        ]

        if let config, let providerName = config.voiceProvider, let provider = config.voiceProviders[providerName] {
            object["voiceProvider"] = providerName
            object["voiceProviderDefaultVoiceId"] = provider.defaultVoiceId as Any
            object["voiceProviderAutoAssignLineVoices"] = provider.autoAssignLineVoices
            object["voiceProviderLineVoices"] = provider.lineVoices
        }

        let lineSources = try latestSourceContextsByLine()
        if !lineSources.isEmpty {
            var sources: [String: Any] = [:]
            for source in lineSources {
                if let line = source["line"] as? String {
                    sources[line] = source
                }
            }
            object["lineSources"] = sources
        }

        return try jsonString(object)
    }

    func setMode(_ mode: String) throws -> RelayCliQueueState {
        guard ["focus", "ready", "live"].contains(mode) else {
            throw RelayCliStoreError(message: "invalid mode: \(mode)")
        }
        try setSetting(key: "mode", value: mode)
        if mode != "live" {
            try clearLiveBatch()
        }
        return try state()
    }

    func setMuted(_ muted: Bool) throws {
        try setSetting(key: "muted", value: String(muted))
    }

    func setActiveLine(_ line: String) throws -> RelayCliQueueState {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            throw RelayCliStoreError(message: "line is required")
        }
        try setSetting(key: "active_line", value: normalized)
        return try state()
    }

    func setDebugOpenSettingsPanel(_ panel: String) throws {
        try setSetting(key: "debug_open_settings_panel", value: panel)
    }

    func setDebugSettingsRoundtrip(voiceCommand: String, combinerCommand: String, cleanupRetentionMinutes: String) throws {
        try setSetting(key: "debug_settings_roundtrip_voice_command", value: voiceCommand)
        try setSetting(key: "debug_settings_roundtrip_combiner_command", value: combinerCommand)
        try setSetting(key: "debug_settings_roundtrip_cleanup_retention_minutes", value: cleanupRetentionMinutes)
    }

    func inactiveLineCombinerCommand() throws -> String {
        try validConfigIfAvailable()?.combinerCommand ?? ""
    }

    func setInactiveLineCombinerCommand(_ command: String) throws -> RelayCliQueueState {
        let config = try updateRelayConfig { config in
            config.combinerCommand = resetBlankCommand(command, fallback: "")
        }
        try clearConfigError()
        try setSetting(key: "inactive_line_combiner_command", value: config.combinerCommand)
        return try state()
    }

    func speechCommand() throws -> String {
        try rawSettings()["speech_command"] ?? defaultSpeechCommand
    }

    func setSpeechCommand(_ command: String) throws {
        try setSetting(key: "speech_command", value: resetBlankCommand(command, fallback: defaultSpeechCommand))
    }

    func voiceCommand() throws -> String {
        try validConfigIfAvailable()?.voiceCommand ?? ""
    }

    func setVoiceCommand(_ command: String) throws {
        let normalized = command == "none" ? defaultVoiceCommand : resetBlankCommand(command, fallback: defaultVoiceCommand)
        guard enabledCommandLineCount(normalized) == 1 else {
            throw RelayCliStoreError(message: "voice command must have exactly one uncommented command")
        }
        let config = try updateRelayConfig { config in
            config.voiceCommand = firstEnabledCommandLine(normalized) ?? normalized
        }
        try clearConfigError()
        try setSetting(key: "voice_command", value: config.voiceCommand)
        try setSetting(key: "voice_command_last_error", value: "")
    }

    func voiceCommandLastError() throws -> String? {
        let value = try rawSettings()["voice_command_last_error"] ?? ""
        return value.isEmpty ? nil : value
    }

    func cleanupRetentionMinutes() throws -> Int {
        try validConfigIfAvailable()?.cleanupRetentionMinutes ?? defaultCleanupRetentionMinutes
    }

    func setCleanupRetentionMinutes(_ value: String) throws {
        guard let minutes = Int(value), (1...maxCleanupRetentionMinutes).contains(minutes) else {
            throw RelayCliStoreError(message: "cleanup retention minutes must be between 1 and \(maxCleanupRetentionMinutes)")
        }

        let config = try updateRelayConfig { config in
            config.cleanupRetentionMinutes = minutes
        }
        try clearConfigError()
        try setSetting(key: "cleanup_retention_minutes", value: String(minutes))
    }

    func setAdvancedConfig(voiceCommand: String?, combinerCommand: String?, cleanupRetentionMinutes: String?) throws -> RelayConfig {
        var voiceCommandForSettings: String?
        let normalizedVoiceCommand = voiceCommand.map { command -> String in
            command == "none" ? defaultVoiceCommand : resetBlankCommand(command, fallback: defaultVoiceCommand)
        }

        if let normalized = normalizedVoiceCommand {
            guard enabledCommandLineCount(normalized) == 1 else {
                throw RelayCliStoreError(message: "voice command must have exactly one uncommented command")
            }
            voiceCommandForSettings = normalized
        }

        let cleanupMinutes = try cleanupRetentionMinutes.map { value in
            guard let minutes = Int(value), (1...maxCleanupRetentionMinutes).contains(minutes) else {
                throw RelayCliStoreError(message: "cleanup retention minutes must be between 1 and \(maxCleanupRetentionMinutes)")
            }
            return minutes
        }

        let config = try updateRelayConfig { config in
            if let normalized = normalizedVoiceCommand {
                config.voiceCommand = firstEnabledCommandLine(normalized) ?? normalized
            }
            if let combinerCommand {
                config.combinerCommand = combinerCommand == "none" ? "" : resetBlankCommand(combinerCommand, fallback: "")
            }
            if let cleanupMinutes {
                config.cleanupRetentionMinutes = cleanupMinutes
            }
        }
        try clearConfigError()

        if let voiceCommandForSettings {
            try setSetting(key: "voice_command", value: config.voiceCommand)
            try setSetting(key: "voice_command_last_error", value: "")
        }
        if combinerCommand != nil {
            try setSetting(key: "inactive_line_combiner_command", value: config.combinerCommand)
        }
        if cleanupRetentionMinutes != nil {
            try setSetting(key: "cleanup_retention_minutes", value: String(config.cleanupRetentionMinutes))
        }

        return config
    }

    func config() throws -> RelayConfig {
        try RelayConfig.loadExisting()
    }

    private func validConfigIfAvailable() throws -> RelayConfig? {
        do {
            let config = try RelayConfig.loadExisting()
            try clearConfigError()
            return config
        } catch {
            try setConfigError(relayConfigErrorMessage(error))
            return nil
        }
    }

    func configError() throws -> String? {
        let value = try rawSettings()["config_last_error"] ?? ""
        return value.isEmpty ? nil : value
    }

    private func setConfigError(_ message: String) throws {
        if try rawSettings()["config_last_error"] != message {
            try setSetting(key: "config_last_error", value: message)
        }
    }

    private func clearConfigError() throws {
        if try rawSettings()["config_last_error"]?.isEmpty == false {
            try setSetting(key: "config_last_error", value: "")
        }
    }

    func firstStartSetupComplete() throws -> Bool {
        try rawSettings()["first_start_setup_complete"] == "true"
    }

    func setFirstStartSetupComplete(_ complete: Bool) throws {
        try setSetting(key: "first_start_setup_complete", value: String(complete))
    }

    func clear() throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
        """)
    }

    func clearQueued(line: String) throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line])
    }

    func clearHeard(line: String?) throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status = 'heard' AND (? IS NULL OR line = ?)
        """, [line, line])
    }

    func pruneRetainedData() throws -> Int {
        let minutes = try cleanupRetentionMinutes()
        let cutoff = nowString(from: Date().addingTimeInterval(TimeInterval(-minutes * 60)))
        let dayCutoff = String(cutoff.prefix(10))
        let relaysDeleted = try changes("""
            DELETE FROM relays
            WHERE status IN ('expired', 'handled', 'skipped', 'failed')
              AND updated_at <= ?
        """, [cutoff])
        let usageDeleted = try changes("""
            DELETE FROM spoken_usage_daily
            WHERE day < ?
        """, [dayCutoff])
        return relaysDeleted + usageDeleted
    }

    func skipNextQueued(line: String?) throws -> RelayCliStoredRelay? {
        try markFirstMatchingStatus(from: "queued", to: "skipped", line: line)
    }

    func markLatestHeardHandled(line: String?) throws -> RelayCliStoredRelay? {
        try markLatestMatchingStatus(from: "heard", to: "handled", line: line)
    }

    func replayLatestHeard(line: String?) throws -> RelayCliStoredRelay? {
        try markLatestMatchingStatus(from: "heard", to: "queued", line: line)
    }

    func expireStaleRelays(ageMinutes: Int = 30) throws -> Int {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-ageMinutes * 60)))
        return try changes("""
            UPDATE relays
            SET status = 'expired', updated_at = ?
            WHERE (
              status IN ('heard', 'failed') AND updated_at <= ?
            ) OR (
              status = 'queued'
              AND priority != 'high'
              AND type IN ('update', 'complete')
              AND created_at <= ?
            )
        """, [nowString(from: now), staleBefore, staleBefore])
    }

    func failStaleSpeaking(ttlSeconds: Int = 60) throws -> Int {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-ttlSeconds)))
        return try changes("""
            UPDATE relays
            SET status = 'failed', updated_at = ?
            WHERE status = 'speaking' AND updated_at <= ?
        """, [nowString(from: now), staleBefore])
    }

    func claimNextForSpeech() throws -> RelayCliStoredRelay? {
        let state = try state()
        if state.muted {
            return nil
        }

        if state.mode == "live" {
            return try claimNextForLive()
        }

        if state.mode != "ready" {
            return nil
        }

        let claimed = try optionalReturningRelay("""
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued'
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [nowString()])

        if claimed == nil {
            return nil
        }

        _ = try setMode("focus")
        return claimed
    }

    func claimNextForLine(_ line: String, maxId: Int? = nil) throws -> RelayCliStoredRelay? {
        if try state().muted {
            return nil
        }

        return try optionalReturningRelay("""
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued' AND line = ? AND (? IS NULL OR id <= ?)
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [nowString(), line, maxId.map(String.init), maxId.map(String.init)])
    }

    private func claimNextForLive() throws -> RelayCliStoredRelay? {
        if let batch = try liveBatch(), let claimed = try claimNextForLine(batch.line, maxId: batch.maxId) {
            return claimed
        }

        try clearLiveBatch()

        guard let batch = try startNextLiveBatch() else {
            return nil
        }

        return try claimNextForLine(batch.line, maxId: batch.maxId)
    }

    private func liveBatch() throws -> (line: String, maxId: Int)? {
        let settings = try rawSettings()
        guard
            let line = settings["live_batch_line"],
            !line.isEmpty,
            let maxIdValue = settings["live_batch_max_id"],
            let maxId = Int(maxIdValue)
        else {
            return nil
        }
        return (line, maxId)
    }

    private func startNextLiveBatch() throws -> (line: String, maxId: Int)? {
        var batch: (line: String, maxId: Int)?
        try query("""
            SELECT line, MAX(id) AS max_id
            FROM relays
            WHERE status = 'queued'
              AND line = (
                SELECT line
                FROM relays
                WHERE status = 'queued'
                ORDER BY
                  CASE priority
                    WHEN 'high' THEN 0
                    WHEN 'normal' THEN 1
                    ELSE 2
                  END,
                  created_at ASC,
                  id ASC
                LIMIT 1
              )
            GROUP BY line
        """) { statement in
            if let line = columnString(statement, 0) {
                batch = (line, Int(sqlite3_column_int(statement, 1)))
            }
        }

        guard let batch else {
            return nil
        }

        try setSetting(key: "active_line", value: batch.line)
        try setSetting(key: "live_batch_line", value: batch.line)
        try setSetting(key: "live_batch_max_id", value: String(batch.maxId))
        return batch
    }

    private func clearLiveBatch() throws {
        try setSetting(key: "live_batch_line", value: "")
        try setSetting(key: "live_batch_max_id", value: "0")
    }

    func markStatus(id: Int, status: String) throws -> RelayCliStoredRelay {
        guard let relay = try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = ?
            RETURNING id, line, message, type, priority, status
        """, [status, nowString(), String(id)]) else {
            throw RelayCliStoreError(message: "relay \(id) not found")
        }
        return relay
    }

    func recordSpokenLine(_ line: String) throws {
        let payload = try jsonString(["line": line, "spokenAt": nowString()])
        try setSetting(key: "last_spoken_line", value: payload)
    }

    func recordSpokenUsage(line: String, provider: String, model: String, voiceIdentifier: String, characterCount: Int) throws {
        let day = String(nowString().prefix(10))
        try execute("""
            INSERT INTO spoken_usage_daily (
              day, provider, model, voice_identifier, line, relay_count, character_count, updated_at
            )
            VALUES (?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(day, provider, model, voice_identifier, line) DO UPDATE SET
              relay_count = relay_count + 1,
              character_count = character_count + excluded.character_count,
              updated_at = excluded.updated_at
        """, [day, provider, model, voiceIdentifier, line, String(characterCount), nowString()])
    }

    func spokenUsageSummary(days: Int = 30) throws -> [String: Any] {
        let since = String(nowString(from: Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))).prefix(10))
        var totalRelays = 0
        var totalCharacters = 0
        try query("""
            SELECT COALESCE(SUM(relay_count), 0), COALESCE(SUM(character_count), 0)
            FROM spoken_usage_daily
            WHERE day >= ?
        """, [since]) { statement in
            totalRelays = Int(sqlite3_column_int(statement, 0))
            totalCharacters = Int(sqlite3_column_int(statement, 1))
        }

        var byProvider: [[String: Any]] = []
        try query("""
            SELECT provider, model, SUM(relay_count), SUM(character_count)
            FROM spoken_usage_daily
            WHERE day >= ?
            GROUP BY provider, model
            ORDER BY SUM(character_count) DESC, provider ASC, model ASC
        """, [since]) { statement in
            byProvider.append([
                "provider": columnString(statement, 0) ?? "",
                "model": columnString(statement, 1) ?? "",
                "relays": Int(sqlite3_column_int(statement, 2)),
                "characters": Int(sqlite3_column_int(statement, 3)),
            ])
        }

        var byLine: [[String: Any]] = []
        try query("""
            SELECT line, SUM(relay_count), SUM(character_count)
            FROM spoken_usage_daily
            WHERE day >= ?
            GROUP BY line
            ORDER BY SUM(character_count) DESC, line ASC
            LIMIT 20
        """, [since]) { statement in
            byLine.append([
                "line": columnString(statement, 0) ?? "",
                "relays": Int(sqlite3_column_int(statement, 1)),
                "characters": Int(sqlite3_column_int(statement, 2)),
            ])
        }

        return [
            "days": days,
            "relays": totalRelays,
            "characters": totalCharacters,
            "byProvider": byProvider,
            "byLine": byLine,
        ]
    }

    func shouldPrefixSpokenLine(_ line: String, timeoutSeconds: Double = 60) throws -> Bool {
        guard let last = try lastSpokenLine(), last.line == line else {
            return true
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let spokenAt = formatter.date(from: last.spokenAt) else {
            return true
        }

        return Date().timeIntervalSince(spokenAt) >= timeoutSeconds
    }

    private func lastSpokenLine() throws -> (line: String, spokenAt: String)? {
        guard
            let value = try rawSettings()["last_spoken_line"],
            let data = value.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let line = parsed["line"] as? String,
            let spokenAt = parsed["spokenAt"] as? String
        else {
            return nil
        }
        return (line, spokenAt)
    }

    func queueOverview(staleBlockerAgeMinutes: Int = 15, limit: Int = 10) throws -> [String: Any] {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-staleBlockerAgeMinutes * 60)))

        var priorityCounts: [String: Int] = [:]
        try query("""
            SELECT priority, COUNT(*) AS count
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY priority
        """) { statement in
            if let priority = columnString(statement, 0) {
                priorityCounts[priority] = Int(sqlite3_column_int(statement, 1))
            }
        }

        var byPriority: [[String: Any]] = []
        for priority in relayPriorities.reversed() {
            if let count = priorityCounts[priority], count > 0 {
                byPriority.append(["priority": priority, "count": count])
            }
        }

        var byProducer: [[String: Any]] = []
        try query("""
            SELECT
              COALESCE(session, app, 'unknown') AS producer,
              COUNT(*) AS count
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY producer
            ORDER BY count DESC, producer ASC
            LIMIT ?
        """, [String(limit)]) { statement in
            if let producer = columnString(statement, 0) {
                byProducer.append(["producer": producer, "count": Int(sqlite3_column_int(statement, 1))])
            }
        }

        var staleCount = 0
        var oldestCreatedAt: String?
        try query("""
            SELECT COUNT(*) AS count, MIN(created_at) AS oldestCreatedAt
            FROM relays
            WHERE status IN ('queued', 'heard')
              AND priority = 'high'
              AND type IN ('blocked', 'needs-input')
              AND created_at <= ?
        """, [staleBefore]) { statement in
            staleCount = Int(sqlite3_column_int(statement, 0))
            oldestCreatedAt = columnString(statement, 1)
        }

        var staleBlockers: [String: Any] = [
            "count": staleCount,
            "thresholdMinutes": staleBlockerAgeMinutes,
        ]
        if staleCount > 0, let oldestCreatedAt {
            staleBlockers["oldestCreatedAt"] = oldestCreatedAt
        }

        return [
            "byPriority": byPriority,
            "byProducer": byProducer,
            "staleBlockers": staleBlockers,
        ]
    }

    func latestSourceContextsByLine() throws -> [[String: Any]] {
        var sources: [[String: Any]] = []
        try query("""
            SELECT id, line, session, app, cwd, url
            FROM (
              SELECT
                id,
                line,
                session,
                app,
                cwd,
                url,
                ROW_NUMBER() OVER (
                  PARTITION BY line
                  ORDER BY created_at DESC, id DESC
                ) AS source_rank
              FROM relays
              WHERE cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL
            )
            WHERE source_rank = 1
            ORDER BY line ASC
        """) { statement in
            var object: [String: Any] = [
                "id": Int(sqlite3_column_int(statement, 0)),
                "line": columnString(statement, 1) ?? "",
            ]
            if let session = columnString(statement, 2) { object["session"] = session }
            if let app = columnString(statement, 3) { object["app"] = app }
            if let cwd = columnString(statement, 4) { object["cwd"] = cwd }
            if let url = columnString(statement, 5) { object["url"] = url }
            sources.append(object)
        }
        return sources
    }

    private func migrate() throws {
        try executeBatch("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS relays (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              line TEXT NOT NULL,
              message TEXT NOT NULL,
              type TEXT NOT NULL,
              priority TEXT NOT NULL,
              session TEXT,
              app TEXT,
              cwd TEXT,
              url TEXT,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS relays_status_idx
              ON relays(status);
            CREATE INDEX IF NOT EXISTS relays_status_line_idx
              ON relays(status, line);
            CREATE INDEX IF NOT EXISTS relays_source_context_latest_idx
              ON relays(line, created_at DESC, id DESC)
              WHERE cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL;
            CREATE TABLE IF NOT EXISTS spoken_usage_daily (
              day TEXT NOT NULL,
              provider TEXT NOT NULL,
              model TEXT NOT NULL,
              voice_identifier TEXT NOT NULL,
              line TEXT NOT NULL,
              relay_count INTEGER NOT NULL DEFAULT 0,
              character_count INTEGER NOT NULL DEFAULT 0,
              updated_at TEXT NOT NULL,
              PRIMARY KEY(day, provider, model, voice_identifier, line)
            );
            CREATE INDEX IF NOT EXISTS spoken_usage_daily_day_idx
              ON spoken_usage_daily(day);
        """)

        try execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES (1)")
        try setSettingIfMissing(key: "mode", value: "focus")
        try setSettingIfMissing(key: "muted", value: "false")
        try setSettingIfMissing(key: "inactive_line_combiner", value: "none")
        try setSettingIfMissing(key: "inactive_line_combiner_command", value: defaultInactiveLineCombinerCommand)
        try setSettingIfMissing(key: "speech_command", value: defaultSpeechCommand)
        try setSettingIfMissing(key: "voice_command", value: defaultVoiceCommand)
        try migrateLegacyVoiceCommandSetting()
        try setSettingIfMissing(key: "cleanup_retention_minutes", value: String(defaultCleanupRetentionMinutes))
        try setSettingIfMissing(key: "first_start_setup_complete", value: defaultFirstStartSetupCompleteValue())
        do {
            let config = try RelayConfig.loadOrCreate(settings: rawSettings())
            try setSetting(key: "inactive_line_combiner_command", value: config.combinerCommand)
            try setSetting(key: "voice_command", value: config.voiceCommand)
            try setSetting(key: "cleanup_retention_minutes", value: String(config.cleanupRetentionMinutes))
            try clearConfigError()
        } catch {
            try setConfigError(relayConfigErrorMessage(error))
        }
    }

    private func migrateLegacyVoiceCommandSetting() throws {
        if shouldMigrateVoiceCommand(try rawSettings()["voice_command"]) {
            try setSetting(key: "voice_command", value: defaultVoiceCommand)
        }
    }

    private func rawSettings() throws -> [String: String] {
        var settings: [String: String] = [:]
        try query("SELECT key, value FROM settings") { statement in
            if let key = columnString(statement, 0), let value = columnString(statement, 1) {
                settings[key] = value
            }
        }
        return settings
    }

    private func cleanupRetentionMinutes(from settings: [String: String]) -> Int {
        guard let value = settings["cleanup_retention_minutes"], let minutes = Int(value), (1...maxCleanupRetentionMinutes).contains(minutes) else {
            return defaultCleanupRetentionMinutes
        }

        return minutes
    }

    private func defaultFirstStartSetupCompleteValue() throws -> String {
        try hasExistingSetupSignal() ? "true" : "false"
    }

    private func hasExistingSetupSignal() throws -> Bool {
        let settings = try rawSettings()
        let setupKeys = [
            "active_line",
            "command_palette_shortcut",
            "speech_voice_identifier",
            "last_spoken_line",
        ]

        if setupKeys.contains(where: { settings[$0] != nil }) {
            return true
        }

        return try relayCount() > 0
    }

    private func relayCount() throws -> Int {
        var count = 0
        try query("SELECT COUNT(*) FROM relays") { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        return count
    }

    private func countsByStatus() throws -> [String: Int] {
        var counts = [
            "queued": 0,
            "speaking": 0,
            "heard": 0,
            "handled": 0,
            "skipped": 0,
            "expired": 0,
            "failed": 0,
        ]
        try query("""
            SELECT status, COUNT(*) AS count
            FROM relays
            GROUP BY status
        """) { statement in
            if let status = columnString(statement, 0) {
                counts[status] = Int(sqlite3_column_int(statement, 1))
            }
        }
        return counts
    }

    private func lineSummaries() throws -> [[String: Any]] {
        var lines: [[String: Any]] = []
        try query("""
            SELECT
              line,
              SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
              SUM(CASE WHEN status = 'heard' THEN 1 ELSE 0 END) AS heard,
              SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY line
            HAVING queued > 0 OR heard > 0 OR failed > 0
            ORDER BY queued DESC, heard DESC, failed DESC, line ASC
        """) { statement in
            if let line = columnString(statement, 0) {
                lines.append([
                    "line": line,
                    "queued": Int(sqlite3_column_int(statement, 1)),
                    "heard": Int(sqlite3_column_int(statement, 2)),
                    "failed": Int(sqlite3_column_int(statement, 3)),
                ])
            }
        }
        return lines
    }

    private func setSetting(key: String, value: String) throws {
        try execute("""
            INSERT INTO settings (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, [key, value])
    }

    private func setSettingIfMissing(key: String, value: String) throws {
        try execute("""
            INSERT OR IGNORE INTO settings (key, value)
            VALUES (?, ?)
        """, [key, value])
    }

    private func returningRelay(_ sql: String, _ values: [String?]) throws -> RelayCliStoredRelay {
        var relay: RelayCliStoredRelay?
        try query(sql, values) { statement in
            relay = mapRelay(statement)
        }

        guard let relay else {
            throw RelayCliStoreError(message: "relay insert failed")
        }

        return relay
    }

    private func optionalReturningRelay(_ sql: String, _ values: [String?]) throws -> RelayCliStoredRelay? {
        var relay: RelayCliStoredRelay?
        try query(sql, values) { statement in
            relay = mapRelay(statement)
        }
        return relay
    }

    private func markFirstMatchingStatus(from: String, to: String, line: String?) throws -> RelayCliStoredRelay? {
        try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [to, nowString(), from, line, line])
    }

    private func markLatestMatchingStatus(from: String, to: String, line: String?) throws -> RelayCliStoredRelay? {
        try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY updated_at DESC, id DESC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [to, nowString(), from, line, line])
    }

    private func changes(_ sql: String, _ values: [String?] = []) throws -> Int {
        try execute(sql, values)
        return Int(sqlite3_changes(database))
    }

    private func execute(_ sql: String, _ values: [String?] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RelayCliStoreError(message: sqliteError(database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            throw RelayCliStoreError(message: sqliteError(database))
        }
    }

    private func executeBatch(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)

        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteError(database)
            sqlite3_free(error)
            throw RelayCliStoreError(message: message)
        }
    }

    private func query(_ sql: String, _ values: [String?] = [], row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RelayCliStoreError(message: sqliteError(database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }
}

func relayCliDatabasePath() -> String {
    let environment = ProcessInfo.processInfo.environment

    if let path = environment["TSRS_DB_PATH"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return path
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Tri-State Relay Service/relay.db"
}

private struct NativeRelayCliInstallStatus {
    let status: String
    let sourcePath: String
    let targetPath: String
    let sourceSignature: String?
    let targetSignature: String?
    let targetDirectoryOnPath: Bool
    let version: String
    let message: String

    func json() throws -> String {
        var object: [String: Any] = [
            "status": status,
            "sourcePath": sourcePath,
            "targetPath": targetPath,
            "targetDirectoryOnPath": targetDirectoryOnPath,
            "version": version,
            "message": message,
        ]
        if let sourceSignature {
            object["sourceSignature"] = sourceSignature
        }
        if let targetSignature {
            object["targetSignature"] = targetSignature
        }
        return try jsonString(object)
    }
}

private func cliInstallStatus(sourcePath: String?, targetPath: String?) throws -> NativeRelayCliInstallStatus {
    let sourcePath = sourcePath ?? currentRelayExecutable()
    let targetPath = targetPath ?? ProcessInfo.processInfo.environment["TSRS_RELAY_INSTALL_TARGET"] ?? defaultCliInstallTarget()
    let targetDirectoryOnPath = pathContainsDirectory(URL(fileURLWithPath: targetPath).deletingLastPathComponent().path)

    guard FileManager.default.fileExists(atPath: sourcePath) else {
        return NativeRelayCliInstallStatus(status: "source-missing", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: nil, targetSignature: nil, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay source is missing: \(sourcePath)")
    }

    let sourceSignature = try fileSignature(sourcePath)

    guard FileManager.default.fileExists(atPath: targetPath) else {
        return NativeRelayCliInstallStatus(status: "missing", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: nil, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI is not installed at \(targetPath)")
    }

    let targetSignature = try fileSignature(targetPath)

    if filesAreEqual(sourcePath, targetPath) {
        return NativeRelayCliInstallStatus(status: "current", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI is current at \(targetPath)")
    }

    if !targetLooksLikeRelay(targetPath) {
        return NativeRelayCliInstallStatus(status: "foreign", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "\(targetPath) exists but does not look like a TSRS relay CLI")
    }

    return NativeRelayCliInstallStatus(status: "stale", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI at \(targetPath) differs from bundled version \(relayCliVersion)")
}

private func installRelayCli(sourcePath: String?, targetPath: String?) throws -> NativeRelayCliInstallStatus {
    let status = try cliInstallStatus(sourcePath: sourcePath, targetPath: targetPath)

    if status.status == "current" {
        return status
    }

    if status.status == "source-missing" || status.status == "foreign" {
        throw RelayCliStoreError(message: status.message)
    }

    let targetDirectory = URL(fileURLWithPath: status.targetPath).deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: status.targetPath) {
        try FileManager.default.removeItem(atPath: status.targetPath)
    }
    try FileManager.default.copyItem(atPath: status.sourcePath, toPath: status.targetPath)
    let permissions = (try FileManager.default.attributesOfItem(atPath: status.sourcePath)[.posixPermissions] as? NSNumber)?.intValue ?? 0o755
    try FileManager.default.setAttributes([.posixPermissions: permissions | 0o755], ofItemAtPath: status.targetPath)
    return try cliInstallStatus(sourcePath: sourcePath, targetPath: targetPath)
}

private func defaultCliInstallTarget() -> String {
    return "/usr/local/bin/relay"
}

private func currentRelayExecutable() -> String {
    if let source = ProcessInfo.processInfo.environment["TSRS_RELAY_SOURCE"] {
        return source
    }

    return CommandLine.arguments.first ?? ProcessInfo.processInfo.arguments.first ?? ""
}

private func fileSignature(_ path: String) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(size):\(modified * 1000)"
}

private func filesAreEqual(_ left: String, _ right: String) -> Bool {
    guard
        let leftData = FileManager.default.contents(atPath: left),
        let rightData = FileManager.default.contents(atPath: right)
    else {
        return false
    }

    func enabledCommandLineCount(_ command: String?) -> Int {
        guard let command else {
            return 0
        }

        return command.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }.count
    }

    return leftData == rightData
}

private func targetLooksLikeRelay(_ path: String) -> Bool {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return process.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("relay ")
}

private func pathContainsDirectory(_ directory: String) -> Bool {
    (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .contains { String($0) == directory }
}

private func mapRelay(_ statement: OpaquePointer) -> RelayCliStoredRelay {
    RelayCliStoredRelay(
        id: Int(sqlite3_column_int(statement, 0)),
        line: columnString(statement, 1) ?? "",
        message: columnString(statement, 2) ?? "",
        type: columnString(statement, 3) ?? "update",
        priority: columnString(statement, 4) ?? "normal",
        status: columnString(statement, 5) ?? "queued"
    )
}

private func bind(_ values: [String?], to statement: OpaquePointer) {
    for (index, value) in values.enumerated() {
        let position = Int32(index + 1)

        if let value {
            sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, position)
        }
    }
}

func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: text)
}

func sqliteError(_ database: OpaquePointer) -> String {
    if let message = sqlite3_errmsg(database) {
        return String(cString: message)
    }

    return "unknown sqlite error"
}

private func nowString(from date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func jsonString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

func commandIsEnabled(_ command: String?) -> Bool {
    guard let command else {
        return false
    }

    for line in command.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            return true
        }
    }

    return false
}

func enabledCommandLineCount(_ command: String?) -> Int {
    guard let command else {
        return 0
    }

    return command.components(separatedBy: .newlines).filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }.count
}

func resetBlankCommand(_ command: String, fallback: String) -> String {
    commandIsEnabled(command) ? command : fallback
}

func playbackMode(_ value: String?) -> String {
    if value == "ready" || value == "live" {
        return value!
    }
    return "focus"
}

struct InactiveLineCombinerOutcome {
    let action: String
    let relay: NormalizedRelay?
}

func combineInactiveRelay(activeLine: String, incoming: NormalizedRelay, existing: RelayCliStoredRelay?, command: String) throws -> InactiveLineCombinerOutcome {
    guard let commandLine = firstEnabledCommandLine(command) else {
        return InactiveLineCombinerOutcome(action: "replace", relay: incoming)
    }

    let input: [String: Any] = [
        "activeLine": activeLine,
        "inactiveLine": incoming.line,
        "existingPendingMessage": existing?.message as Any? ?? NSNull(),
        "incoming": [[
            "type": incoming.type,
            "priority": incoming.priority,
            "message": incoming.message,
        ]],
    ]
    let inputJSON = try jsonString(input)
    let output = try runInactiveLineCombiner(commandLine: commandLine, inputJSON: inputJSON, systemPrompt: inactiveLineCombinerSystemPrompt)
    return try parseInactiveLineCombinerOutput(output, incoming: incoming)
}

func firstEnabledCommandLine(_ command: String?) -> String? {
    guard let command else {
        return nil
    }

    for line in command.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            return trimmed
        }
    }

    return nil
}

private func runInactiveLineCombiner(commandLine: String, inputJSON: String, systemPrompt: String) throws -> String {
    let parts = try splitCommandLine(commandLine)
    guard let executable = parts.first else {
        throw RelayCliStoreError(message: "inactive-line combiner command is empty")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: try resolveExecutablePath(executable))
    process.arguments = parts.dropFirst().map {
        expandCombinerArgument($0, inputJSON: inputJSON, systemPrompt: systemPrompt)
    }
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        semaphore.signal()
    }
    try process.run()
    let completed = semaphore.wait(timeout: .now() + 30) == .success
    if !completed {
        process.terminate()
        throw RelayCliStoreError(message: "inactive-line combiner timed out")
    }

    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw RelayCliStoreError(message: detail.isEmpty ? "inactive-line combiner failed" : "inactive-line combiner failed: \(detail)")
    }

    return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func splitCommandLine(_ commandLine: String) throws -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in commandLine {
        if escaping {
            current.append(character)
            escaping = false
            continue
        }

        if character == "\\" {
            escaping = true
            continue
        }

        if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            continue
        }

        if character == "\"" || character == "'" {
            quote = character
            continue
        }

        if character.isWhitespace {
            if !current.isEmpty {
                parts.append(current)
                current = ""
            }
            continue
        }

        current.append(character)
    }

    if escaping {
        current.append("\\")
    }

    if quote != nil {
        throw RelayCliStoreError(message: "inactive-line combiner command has an unterminated quote")
    }

    if !current.isEmpty {
        parts.append(current)
    }

    return parts
}

private func expandCombinerArgument(_ argument: String, inputJSON: String, systemPrompt: String) -> String {
    var expanded = ""
    var index = argument.startIndex

    while index < argument.endIndex {
        if argument[index...].hasPrefix("<input>") {
            expanded.append(inputJSON)
            index = argument.index(index, offsetBy: "<input>".count)
        } else if argument[index...].hasPrefix("<system>") {
            expanded.append(systemPrompt)
            index = argument.index(index, offsetBy: "<system>".count)
        } else {
            expanded.append(argument[index])
            index = argument.index(after: index)
        }
    }

    return expanded
}

private func resolveExecutablePath(_ executable: String) throws -> String {
    if executable.contains("/") {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RelayCliStoreError(message: "inactive-line combiner executable is not runnable: \(executable)")
        }
        return executable
    }

    for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }

    throw RelayCliStoreError(message: "inactive-line combiner executable not found on PATH: \(executable)")
}

private func parseInactiveLineCombinerOutput(_ output: String, incoming: NormalizedRelay) throws -> InactiveLineCombinerOutcome {
    guard let data = output.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RelayCliStoreError(message: "inactive-line combiner must return one JSON object")
    }

    guard let action = object["action"] as? String, ["drop", "replace", "promote"].contains(action) else {
        throw RelayCliStoreError(message: "inactive-line combiner action must be drop, replace, or promote")
    }

    if action == "drop" {
        return InactiveLineCombinerOutcome(action: action, relay: nil)
    }

    let relay = try normalizeRelay(NewRelayInput(
        line: incoming.line,
        message: object["message"] as? String ?? "",
        type: object["type"] as? String,
        priority: object["priority"] as? String,
        session: incoming.session,
        app: incoming.app,
        cwd: incoming.cwd,
        url: incoming.url
    ))
    return InactiveLineCombinerOutcome(action: action, relay: relay)
}

let inactiveLineCombinerSystemPrompt = """
You compose one useful relay from several short agent status updates.

The user is actively listening to one line. Messages from other lines should not become a noisy backlog. Your job is to decide what single relay, if any, a thoughtful agent would leave after waiting until the useful point.

Rules:
1. Return exactly one JSON object and no other text.
2. Output keys: action, type, priority, message.
3. action must be one of drop, replace, or promote.
4. type must be one of update, complete, blocked, or needs-input.
5. priority must be one of low, normal, or high.
6. message must be 160 characters or fewer.
7. Do not invent facts, names, decisions, errors, files, links, or outcomes.
8. Do not include code, logs, terminal output, secrets, raw file contents, or private data.
9. Preserve the most important human-actionable information.
10. Prefer calm, concise wording suitable for spoken playback.
11. Write like a human leaving one relay, not like a dashboard summary.
12. Do not count updates unless the count itself matters.

Decision policy:
- If the incoming messages are only routine progress with no user action, return replace with one natural progress relay.
- If the incoming messages repeat information already present in the existing pending message and add no important change, return drop.
- If any message is blocked, needs-input, or priority high, return promote.
- If any message is complete, preserve that completion unless a newer blocked or needs-input message is more important.
- If multiple routine updates arrive, compress the progress arc and end on the current useful point.
"""

let defaultInactiveLineCombinerCommand = """
# Inactive line combiner command.
# Leave this commented to use latest-only inactive-line behavior.
# The command must print a JSON object: {"action":"replace|promote|drop","type":"update|blocked|complete","priority":"low|normal|high","message":"short relay"}
# Placeholders are inserted as single argv values, not shell-expanded.
#
# llm CLI: https://github.com/simonw/llm
# llm prompt <input> --system <system> --no-stream --no-log
#
# apfel CLI: https://github.com/Arthur-Ficial/apfel
# apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>
"""

let defaultSpeechCommand = """
# Speech command.
# /usr/bin/say ships with macOS, so no extra install is required.
# Placeholders are inserted as single argv values, not shell-expanded.
/usr/bin/say <message>
"""

let defaultVoiceCommand = """
# Voice command.
# Direct-build command that writes audio for TSRS to play.
# It must not speak directly. Exactly one command should be uncommented.
# Supported placeholders are inserted as single argv values: <text-file>, <output-file>, <voice-id>, <app-bin>
/usr/bin/say -f <text-file> -o <output-file>
#
# Optional say example with a specific voice:
# /usr/bin/say -v Samantha -f <text-file> -o <output-file>
#
# Speechify example using the bundled speechify helper:
# 1. Store your API key in Keychain:
#    security add-generic-password -a "$USER" -s TSRS_SPEECHIFY_API_KEY -w "paste-api-key-here" -U
# 2. Set [voice] provider = "speechify", add [speechify] settings, then uncomment this command:
# <app-bin>/speechify --text-file <text-file> --output-file <output-file> --voice-id <voice-id> --keychain-service TSRS_SPEECHIFY_API_KEY
"""

let legacyCommentedVoiceCommand = """
# Voice command.
# Optional direct-build command that writes audio for TSRS to play.
# It must not speak directly. Leave this commented to use built-in /usr/bin/say playback.
# Supported placeholders are inserted as single argv values: <text-file>, <output-file>, <voice-id>
#
# /usr/bin/say -v <voice-id> -f <text-file> -o <output-file>
"""

func shouldMigrateVoiceCommand(_ command: String?) -> Bool {
    guard let command else {
        return false
    }

    return command == legacyCommentedVoiceCommand
        || command.contains("/usr/bin/say -v <voice-id> -f <text-file> -o <output-file>")
        || command.contains("scripts/speechify-voice-command")
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
