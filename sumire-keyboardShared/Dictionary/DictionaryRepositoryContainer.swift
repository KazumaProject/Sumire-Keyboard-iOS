import Foundation

enum DictionaryRepositoryContainer {
    static func makeDefault() throws -> DictionaryRepositories {
        try DictionaryRepositories(store: SQLiteDictionaryStore(databaseURL: sharedDatabaseURL()))
    }

    static func sharedDatabaseURL() -> URL {
        sharedDictionaryDirectoryURL().appendingPathComponent("sumire-dictionaries.sqlite")
    }

    static func sharedDictionaryDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSettings.appGroupIdentifier
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        return baseURL
            .appendingPathComponent("Dictionary", isDirectory: true)
    }
}
