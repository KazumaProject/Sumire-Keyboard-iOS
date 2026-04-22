import Foundation

struct KanaKanjiBundleResources {
    private let bundle: Bundle
    private let fileManager: FileManager

    init(
        bundle: Bundle = Bundle(for: KeyboardViewController.self),
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func sharedPOSTableURL() -> URL? {
        guard let resourcesDirectory = resourcesDirectory() else {
            return nil
        }
        let url = resourcesDirectory.appendingPathComponent(MozcDictionary.posTableFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func mainArtifactsDirectory() -> URL? {
        if let directory = artifactsDirectory(named: "main") {
            return directory
        }
        return legacyMainArtifactsDirectory()
    }

    func artifactsDirectory(named name: String) -> URL? {
        guard let resourcesDirectory = resourcesDirectory() else {
            return nil
        }

        let directory = resourcesDirectory.appendingPathComponent(name, isDirectory: true)
        return MozcArtifactIO.containsDictionaryArtifacts(at: directory) ? directory : nil
    }

    func availableSupplementalArtifactDirectories() -> [SupplementalDictionaryKind: URL] {
        var directories: [SupplementalDictionaryKind: URL] = [:]
        for kind in SupplementalDictionaryKind.allCases {
            if let directory = artifactsDirectory(named: kind.resourceDirectoryName) {
                directories[kind] = directory
            }
        }
        return directories
    }

    func englishArtifactsDirectory() -> URL? {
        guard let resourcesDirectory = resourcesDirectory() else {
            return nil
        }

        let directory = resourcesDirectory.appendingPathComponent("english", isDirectory: true)
        return EnglishArtifactIO.containsArtifacts(at: directory) ? directory : nil
    }

    func connectionMatrixURL(forMainArtifactsDirectory mainArtifactsDirectory: URL) -> URL? {
        let localURL = mainArtifactsDirectory.appendingPathComponent(MozcDictionary.connectionMatrixFileName)
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }

        guard mainArtifactsDirectory.lastPathComponent == "main",
              let resourcesDirectory = resourcesDirectory() else {
            return nil
        }

        let legacyURL = resourcesDirectory.appendingPathComponent(MozcDictionary.connectionMatrixFileName)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : nil
    }

    private func resourcesDirectory() -> URL? {
        if let url = bundle.url(forResource: "KanaKanjiResources", withExtension: nil),
           isDirectory(url) {
            return url
        }

        if bundle.bundleIdentifier != Bundle.main.bundleIdentifier,
           let url = Bundle.main.url(forResource: "KanaKanjiResources", withExtension: nil),
           isDirectory(url) {
            return url
        }

        if let resourceURL = bundle.resourceURL {
            let url = resourceURL.appendingPathComponent("KanaKanjiResources", isDirectory: true)
            if isDirectory(url) {
                return url
            }
        }

        if bundle.bundleIdentifier != Bundle.main.bundleIdentifier,
           let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("KanaKanjiResources", isDirectory: true)
            if isDirectory(url) {
                return url
            }
        }

        return nil
    }

    private func legacyMainArtifactsDirectory() -> URL? {
        guard let resourcesDirectory = resourcesDirectory(),
              MozcArtifactIO.containsDictionaryArtifacts(at: resourcesDirectory) else {
            return nil
        }
        return resourcesDirectory
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
