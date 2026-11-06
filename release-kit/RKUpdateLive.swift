import AppKit

extension UpdateController.Environment {
    /// Wires the updater to the running app. Only the test fixture passes a different bundle name.
    @MainActor
    static func live(bundle: Bundle = .main, support: URL, archiveBundleName: String? = nil, configuration: ReleaseConfiguration = .clipEdge,
                     isBusy: @escaping () -> Bool, saveBeforeQuit: @escaping () -> Bool,
                     quit: @escaping () -> Void) -> UpdateController.Environment {
        let target = bundle.bundleURL
        let identifier = bundle.bundleIdentifier ?? configuration.bundleIdentifier
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init) ?? AppVersion("0")!
        let availability = UpdateAvailability.resolve(
            bundle: target, feedText: Self.feedText(info: bundle.infoDictionary ?? [:], configuration: configuration),
            isAdHoc: { UpdateVerifier.isAdHoc(appAt: target) },
            folderWritable: { FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) },
            preservesMaintainerBuild: configuration.preservesMaintainerBuild(info: bundle.infoDictionary ?? [:]))
        let session = UpdateFetcher.session()
        let verify: (URL) throws -> Void = { candidate in
            try UpdateVerifier.check(candidate, satisfies: UpdateVerifier.requirementOfRunningApp())
            if configuration.stableArchiveTemplate != nil { try UpdateVerifier.requireSupportedMac(candidate) }
        }
        return UpdateController.Environment(
            productName: configuration.productName, runningVersion: version, availability: availability, support: support,
            fetchRelease: { feed in
                try await UpdateFetcher.release(feed: feed, runningVersion: version.description, session: session, productName: configuration.productName, stableArchiveTemplate: configuration.stableArchiveTemplate)
            },
            fetchApp: { release, folder in
                try await UpdateFetcher.app(for: release, bundleName: archiveBundleName ?? configuration.archiveBundleName, runningVersion: version.description,
                                            in: folder, session: session, productName: configuration.productName)
            },
            verify: verify,
            installedVersion: UpdateVerifier.version(ofAppAt:),
            install: { staged, receipts in
                try UpdateInstaller.install(staged, over: target, identifier: identifier, receipts: receipts, configuration: configuration, verify: verify)
            },
            goBack: { receipt in try UpdateInstaller.goBack(using: receipt, identifier: identifier, expectedTarget: target, configuration: configuration) },
            canGoBack: { receipt in UpdateInstaller.canGoBack(using: receipt, expectedTarget: target, configuration: configuration) },
            isBusy: isBusy,
            secondsSinceInput: {
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            },
            saveBeforeQuit: saveBeforeQuit,
            reopenAndQuit: {
                UpdateInstaller.reopenAfterExit(target)
                quit()
            })
    }

    /// Protected maintainer copies and source releases remain inert. Only a permitted, validated maintainer
    /// capability can add its separate, fixed GitHub feed without hiding Publish.
    static func feedText(info: [String: Any], configuration: ReleaseConfiguration = .clipEdge,
                         fileExists: (String) -> Bool = FileManager.default.isReadableFile) -> String? {
        guard !configuration.preservesMaintainerBuild(info: info) else { return nil }
        if let release = info[configuration.infoPrefix + "UpdateFeed"] as? String { return release }
        guard PublishCapability.resolve(info: info, configuration: configuration, fileExists: fileExists) != nil,
              configuration.releasePage.host == "github.com",
              let feed = info[configuration.infoPrefix + "MaintainerUpdateFeed"] as? String,
              feed == "https://api.github.com/repos" + configuration.releasePage.path + (configuration.stableArchiveTemplate == nil ? "" : UpdateFeed.listQuery) else { return nil }
        return feed
    }

    /// Beside the clipboard history, outside the app, so it survives each update.
    static var defaultSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipEdge/Updates", isDirectory: true)
    }
}
