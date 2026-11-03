import SwiftUI
import UniformTypeIdentifiers

struct PatchFile: Identifiable {
    let id = UUID()
    let relativePath: String
    let source: URL
    let target: URL?
    var active = false
}

struct ContentView: View {
    @State private var sourceFolder: URL?
    @State private var targetFolder: URL?
    @State private var pickingSource = false
    @State private var pickingTarget = false
    @State private var files: [PatchFile] = []
    @State private var backups: [String: URL] = [:]
    @State private var logs = ["PatchKit ready."]
    @State private var alertText: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            mainScrollView
                .background(Color(red: 0.055, green: 0.065, blue: 0.09))
                .toolbar(.hidden, for: .navigationBar)
                .fileImporter(
                    isPresented: $pickingSource,
                    allowedContentTypes: [.folder]
                ) { result in
                    handleFolderImport(result, isSource: true)
                }
                .fileImporter(
                    isPresented: $pickingTarget,
                    allowedContentTypes: [.folder]
                ) { result in
                    handleFolderImport(result, isSource: false)
                }
                .alert(
                    "PatchKit",
                    isPresented: alertIsPresented,
                    actions: {
                        Button("OK", role: .cancel) {
                            alertText = nil
                        }
                    },
                    message: {
                        Text(alertText ?? "")
                    }
                )
        }
    }

    // MARK: - Main layout

    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                folderSelectionSection
                statisticsSection
                actionButtonsSection
                patchFilesSection
                activityLogSection
                accessNotice
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PATCHKIT")
                .font(.caption.bold())
                .tracking(3)
                .foregroundStyle(.cyan)

            Text("File Patch Manager")
                .font(.largeTitle.bold())

            Text("Replace, track, and restore files.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderSelectionSection: some View {
        VStack(spacing: 12) {
            folderButton(
                "Patch Source",
                url: sourceFolder,
                icon: "shippingbox"
            ) {
                pickingSource = true
            }

            folderButton(
                "Target Folder",
                url: targetFolder,
                icon: "folder"
            ) {
                pickingTarget = true
            }
        }
    }

    private var statisticsSection: some View {
        HStack(spacing: 10) {
            stat("FILES", value: "\(files.count)")
            stat("MATCHED", value: "\(matchedFileCount)")
            stat("ACTIVE", value: "\(activeFileCount)")
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: scan) {
                Label("Scan Source", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(sourceFolder == nil || targetFolder == nil || busy)

            Button(action: patchAll) {
                Label("Patch All", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(busy || !hasFilesReadyToPatch)
        }
        .frame(maxWidth: .infinity)
    }

    private var patchFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PATCH FILES")

            if files.isEmpty {
                emptyFilesView
            } else {
                ForEach(files.indices, id: \.self) { index in
                    patchFileRow(files[index], at: index)
                }
            }
        }
    }

    private var emptyFilesView: some View {
        Text("Choose both folders, then scan.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var activityLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ACTIVITY LOG")

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(logs.prefix(8).enumerated()), id: \.offset) { entry in
                    Text("•  " + entry.element)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var accessNotice: some View {
        Text("Only folders explicitly selected through Files are accessible. This app does not bypass iOS sandbox restrictions.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Reusable views

    private func folderButton(
        _ title: String,
        url: URL?,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 42)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(url?.lastPathComponent ?? "Tap to choose a folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func patchFileRow(_ file: PatchFile, at index: Int) -> some View {
        HStack(spacing: 10) {
            fileStatusIcon(for: file)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: file.relativePath).lastPathComponent)
                    .font(.subheadline.bold())

                Text(file.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text(fileStatusText(for: file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if file.target != nil {
                fileActionButton(for: file, at: index)
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func fileStatusIcon(for file: PatchFile) -> some View {
        if file.active {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if file.target == nil {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.cyan)
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.cyan)
        }
    }

    private func fileStatusText(for file: PatchFile) -> String {
        if file.active { return "Patched" }
        if file.target == nil { return "No matching target" }
        return "Ready"
    }

    @ViewBuilder
    private func fileActionButton(for file: PatchFile, at index: Int) -> some View {
        if file.active {
            Button("Restore") {
                restore(index)
            }
            .font(.caption.bold())
            .disabled(busy)
        } else {
            Button("Patch") {
                patch(index)
            }
            .font(.caption.bold())
            .disabled(busy)
        }
    }

    // MARK: - Derived state

    private var matchedFileCount: Int {
        files.filter { $0.target != nil }.count
    }

    private var activeFileCount: Int {
        files.filter(\.active).count
    }

    private var hasFilesReadyToPatch: Bool {
        files.contains { $0.target != nil && !$0.active }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { alertText != nil },
            set: { isPresented in
                if !isPresented {
                    alertText = nil
                }
            }
        )
    }

    // MARK: - Folder import

    private func handleFolderImport(_ result: Result<URL, Error>, isSource: Bool) {
        switch result {
        case .success(let url):
            if isSource {
                sourceFolder = url
            } else {
                targetFolder = url
            }

            let folderName = url.lastPathComponent
            let folderType = isSource ? "Source" : "Target"
            logs.insert("\(folderType) selected: \(folderName)", at: 0)

        case .failure(let error):
            alertText = error.localizedDescription
        }
    }

    // MARK: - File scanning

    private func listFiles(_ root: URL) throws -> [(String, URL)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var output: [(String, URL)] = []

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let relativePath = String(url.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            output.append((relativePath, url))
        }

        return output
    }

    private func scan() {
        guard let sourceRoot = sourceFolder,
              let targetRoot = targetFolder else {
            return
        }

        let sourceAccess = sourceRoot.startAccessingSecurityScopedResource()
        let targetAccess = targetRoot.startAccessingSecurityScopedResource()

        defer {
            if sourceAccess {
                sourceRoot.stopAccessingSecurityScopedResource()
            }
            if targetAccess {
                targetRoot.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let targetEntries = try listFiles(targetRoot)
            var targetMap: [String: URL] = [:]

            for (relativePath, url) in targetEntries {
                targetMap[relativePath] = url
            }

            let sourceEntries = try listFiles(sourceRoot)
            files = sourceEntries.map { entry in
                PatchFile(
                    relativePath: entry.0,
                    source: entry.1,
                    target: targetMap[entry.0]
                )
            }

            logs.insert(
                "Scan: \(files.count) source files; \(matchedFileCount) matches.",
                at: 0
            )
        } catch {
            alertText = "Scan failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Backup and patching

    private func backupRoot() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let backupDirectory = documents.appendingPathComponent(
            "PatchKitBackups",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        return backupDirectory
    }

    private func patch(_ index: Int) {
        guard files.indices.contains(index),
              let targetURL = files[index].target,
              let sourceRoot = sourceFolder,
              let targetRoot = targetFolder else {
            return
        }

        let sourceAccess = sourceRoot.startAccessingSecurityScopedResource()
        let targetAccess = targetRoot.startAccessingSecurityScopedResource()

        defer {
            if sourceAccess {
                sourceRoot.stopAccessingSecurityScopedResource()
            }
            if targetAccess {
                targetRoot.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let sourceData = try Data(contentsOf: files[index].source)
            let backupURL = try backupRoot()
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("bak")

            try FileManager.default.copyItem(at: targetURL, to: backupURL)
            try sourceData.write(to: targetURL, options: .atomic)

            backups[files[index].relativePath] = backupURL
            files[index].active = true
            logs.insert("Patched: \(files[index].relativePath)", at: 0)
        } catch {
            alertText = "Patch failed: \(error.localizedDescription)"
        }
    }

    private func patchAll() {
        guard !busy else { return }

        busy = true
        defer { busy = false }

        for index in files.indices {
            guard files[index].target != nil, !files[index].active else {
                continue
            }
            patch(index)
        }
    }

    // MARK: - Restore

    private func restore(_ index: Int) {
        guard files.indices.contains(index),
              let targetURL = files[index].target,
              let backupURL = backups[files[index].relativePath],
              let targetRoot = targetFolder else {
            alertText = "No backup mapping found for this session."
            return
        }

        let targetAccess = targetRoot.startAccessingSecurityScopedResource()

        defer {
            if targetAccess {
                targetRoot.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let originalData = try Data(contentsOf: backupURL)
            try originalData.write(to: targetURL, options: .atomic)
            try FileManager.default.removeItem(at: backupURL)

            backups.removeValue(forKey: files[index].relativePath)
            files[index].active = false
            logs.insert("Restored: \(files[index].relativePath)", at: 0)
        } catch {
            alertText = "Restore failed: \(error.localizedDescription)"
        }
    }
}
