import Foundation

/// The built-in rule set for security scanning.
public enum SecurityScanRules {
    public static let defaults: [SecurityScanRule] = [
        // High severity
        SecurityScanRule(
            id: "risky-rm-rf",
            description: "Destructive recursive delete (rm -rf)",
            severity: .high,
            pattern: #"rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r"#
        ),
        SecurityScanRule(
            id: "risky-curl-exec",
            description: "Remote code execution via curl/wget pipe to shell",
            severity: .high,
            pattern: #"(curl|wget)\s+.*\|\s*(ba)?sh"#
        ),
        SecurityScanRule(
            id: "risky-sudo",
            description: "Elevated privileges via sudo",
            severity: .high,
            pattern: #"\bsudo\b"#
        ),
        SecurityScanRule(
            id: "risky-eval",
            description: "Dynamic code evaluation (eval)",
            severity: .high,
            pattern: #"\beval\b"#
        ),
        // Medium severity
        SecurityScanRule(
            id: "risky-chmod-777",
            description: "World-writable permissions (chmod 777 or a+rwx)",
            severity: .medium,
            pattern: #"chmod\s+(777|a\+rwx|0777)"#
        ),
        SecurityScanRule(
            id: "risky-env-override",
            description: "Overriding PATH or other critical environment variables",
            severity: .medium,
            pattern: #"export\s+(PATH|LD_PRELOAD|LD_LIBRARY_PATH)\s*="#
        ),
        SecurityScanRule(
            id: "risky-secrets-hardcoded",
            description: "Possible hardcoded secret (API key or password assignment)",
            severity: .medium,
            pattern: #"(?i)(api_?key|password|secret|token)\s*=\s*['\"][^'"]{8,}"#
        ),
        // Low severity
        SecurityScanRule(
            id: "risky-network-call",
            description: "Outbound network call (curl/wget/nc)",
            severity: .low,
            pattern: #"\b(curl|wget|nc|netcat)\b"#
        ),
        SecurityScanRule(
            id: "risky-unknown-origin",
            description: "Script references an external URL",
            severity: .low,
            pattern: #"https?://"#
        ),
    ]
}
