import Foundation

/// Defines supported MCP protocol versions and version-specific features
public enum MCPVersion {
    /// Current version of the protocol
    public static let currentVersion = "2025-03-26"

    /// All versions this implementation supports, in descending order
    public static let supportedVersions = ["2025-03-26", "2024-11-05"]

    /// Features supported by different protocol versions.
    /// Each feature defines its minimum required version.
    public enum Feature: CaseIterable {
        case completions
        case audioContent
        case toolAnnotations
        case batchRequests

        var minimumVersion: String {
            switch self {
            case .completions, .audioContent, .toolAnnotations, .batchRequests:
                return "2025-03-26"
            }
        }
    }

    /// Handles version negotiation between client and server
    public struct VersionNegotiation {
        public let preferredVersion: String
        public let supportedVersions: [String]

        public init(
            preferredVersion: String = MCPVersion.currentVersion,
            supportedVersions: [String] = MCPVersion.supportedVersions
        ) {
            self.preferredVersion = preferredVersion
            self.supportedVersions = supportedVersions
        }

        public func negotiate(serverVersion: String) -> String? {
            if !MCPVersion.isValidFormat(serverVersion) {
                return nil
            }

            // Try to find highest mutually supported version
            return
                supportedVersions
                .filter { MCPVersion.isSupported($0) }
                .sorted(by: { MCPVersion.compare($0, $1) == .orderedDescending })
                .first
        }
    }

    /// Represents the set of features supported by a specific version
    public struct FeatureSet: Equatable {
        public let version: String
        public let features: Set<MCPVersion.Feature>

        public init(version: String) {
            self.version = version
            self.features = Set(
                MCPVersion.Feature.allCases.filter {
                    MCPVersion.supportsFeature($0, version: version)
                })
        }

        public func supports(_ feature: MCPVersion.Feature) -> Bool {
            features.contains(feature)
        }

        public static func commonFeatures(_ v1: String, _ v2: String) -> Set<Feature> {
            let set1 = FeatureSet(version: v1)
            let set2 = FeatureSet(version: v2)
            return set1.features.intersection(set2.features)
        }
    }

    /// Check if a given version is supported
    public static func isSupported(_ version: String) -> Bool {
        guard isValidFormat(version) else { return false }
        return supportedVersions.contains(version)
    }

    /// Validate version string format (YYYY-MM-DD)
    public static func isValidFormat(_ version: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Check format matches exactly YYYY-MM-DD
        let pattern = "^\\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\\d|3[01])$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
            regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)) != nil
        else {
            return false
        }

        // Validate it's a real date
        guard let date = dateFormatter.date(from: version) else {
            return false
        }

        // Verify the formatted date matches the input exactly
        // This catches invalid dates that might parse (like 2025-02-31)
        return dateFormatter.string(from: date) == version
    }

    /// Compare two version strings
    public static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        guard isValidFormat(v1) && isValidFormat(v2) else {
            return .orderedSame  // Invalid formats are considered equal
        }
        return v1.compare(v2)
    }

    /// Check if a feature is supported in a given version
    public static func supportsFeature(_ feature: Feature, version: String) -> Bool {
        guard isSupported(version) else { return false }
        return compare(version, feature.minimumVersion) != .orderedAscending
    }
}
