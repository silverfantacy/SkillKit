import Foundation

struct StoreSkillItem: Identifiable, Hashable {
    let id: String
    let providerId: String
    let providerDisplayName: String
    let name: String
    let summary: String
    let version: String?
    let tags: [String]
    let installSlug: String
}

protocol StoreCatalogAdapter {
    var providerId: String { get }
    var providerDisplayName: String { get }

    func fetchCatalogItems() -> [StoreSkillItem]
}

struct StoreCatalogService {
    let adapters: [any StoreCatalogAdapter]

    func listItems() -> [StoreSkillItem] {
        adapters
            .flatMap { $0.fetchCatalogItems() }
            .sorted {
                if $0.providerDisplayName == $1.providerDisplayName {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.providerDisplayName.localizedCaseInsensitiveCompare($1.providerDisplayName) == .orderedAscending
            }
    }
}

struct MockSkillStoreAdapter: StoreCatalogAdapter {
    let providerId = "mock.local"
    let providerDisplayName = "Mock Catalog"

    func fetchCatalogItems() -> [StoreSkillItem] {
        [
            StoreSkillItem(
                id: "mock.local.git-commit-review",
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                name: "Git Commit Review",
                summary: "Review commit messages and changed files before merge.",
                version: "1.0.0",
                tags: ["git", "review"],
                installSlug: "git-commit-review"
            ),
            StoreSkillItem(
                id: "mock.local.release-checklist",
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                name: "Release Checklist",
                summary: "Run repeatable release checks and summarize blockers.",
                version: "0.9.3",
                tags: ["release", "qa"],
                installSlug: "release-checklist"
            )
        ]
    }
}
