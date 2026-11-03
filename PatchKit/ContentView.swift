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
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PATCHKIT").font(.caption.bold()).tracking(3).foregroundStyle(.cyan)
                        Text("File Patch Manager").font(.largeTitle.bold())
                        Text("Replace, track, and restore files.")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    folderButton("Patch Source", url: sourceFolder, icon: "shippingbox") { pickingSource = true }
                    folderButton("Target Folder", url: targetFolder, icon: "folder") { pickingTarget = true }

                    HStack {
                        stat("FILES", "\(files.count)")
                        stat("MATCHED", "\(files.filter { $0.target != nil }.count)")
                        stat("ACTIVE", "\(files.filter(\.active).count)")
                    }

                    HStack {
                        Button("Scan Source", systemImage: "magnifyingglass") { scan() }
                            .buttonStyle(.borderedProminent).tint(.cyan)
                            .disabled(sourceFolder == nil || targetFolder == nil || busy)
                        Button("Patch All", systemImage: "arrow.triangle.2.circlepath") { patchAll() }
                            .buttonStyle(.bordered).disabled(busy || !files.contains { $0.target != nil && !$0.active })
                    }.frame(maxWidth: .infinity)

                    sectionTitle("PATCH FILES")
                    if files.isEmpty {
                        Text("Choose both folders, then scan.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }
                    ForEach(files.indices, id: \.self) { index in
                        let file = files[index]
                        HStack {
                            Image(systemName: file.active ? "checkmark.circle.fill" : (file.target == nil ? "exclamationmark.circle" : "doc"))
                                .foregroundStyle(file.active ? .green : .cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: file.relativePath).lastPathComponent).font(.subheadline.bold())
                                Text(file.relativePath).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Text(file.active ? "Patched" : (file.target == nil ? "No matching target" : "Ready"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if file.target != nil {
                                Button(file.active ? "Restore" : "Patch") {
                                    file.active ? restore(index) : patch(index)
                                }.font(.caption.bold()).disabled(busy)
                            }
                        }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                    }

                    sectionTitle("ACTIVITY LOG")
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(logs.prefix(8).enumerated()), id: \.offset) { _, item in
                            Text("•  " + item).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

                    Text("Only folders explicitly selected through Files are accessible. This app does not bypass iOS sandbox restrictions.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.09))
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $pickingSource, allowedContentTypes: [.folder]) { handle($0, source: true) }
            .fileImporter(isPresented: $pickingTarget, allowedContentTypes: [.folder]) { handle($0, source: false) }
            .alert("PatchKit", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button("OK", role: .cancel) { alertText = nil }
            } message: { Text(alertText ?? "") }
        }
    }

    private func folderButton(_ title: String, url: URL?, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.title2).foregroundStyle(.cyan).frame(width: 42)
                VStack(alignment: .leading) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(url?.lastPathComponent ?? "Tap to choose a folder")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handle(_ result: Result<[URL], Error>, source: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if source { sourceFolder = url } else { targetFolder = url }
            logs.insert("\(source ? "Source" : "Target") selected: \(url.lastPathComponent)", at: 0)
        case .failure(let error): alertText = error.localizedDescription
        }
    }

    private func listFiles(_ root: URL) throws -> [(String, URL)] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var output: [(String, URL)] = []
        for case let url as URL in e {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                output.append((relative, url))
            }
        }
        return output
    }

    private func scan() {
        guard let src = sourceFolder, let dst = targetFolder else { return }
        let a = src.startAccessingSecurityScopedResource()
        let b = dst.startAccessingSecurityScopedResource()
        defer { if a { src.stopAccessingSecurityScopedResource() }; if b { dst.stopAccessingSecurityScopedResource() } }
        do {
            let targets = try Dictionary(uniqueKeysWithValues: listFiles(dst).map { ($0.0, $0.1) })
            files = try listFiles(src).map { PatchFile(relativePath: $0.0, source: $0.1, target: targets[$0.0]) }
            logs.insert("Scan: \(files.count) source files; \(files.filter { $0.target != nil }.count) matches.", at: 0)
        } catch { alertText = "Scan failed: \(error.localizedDescription)" }
    }

    private func backupRoot() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("PatchKitBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func patch(_ index: Int) {
        guard let target = files[index].target, let root = targetFolder else { return }
        let a = root.startAccessingSecurityScopedResource()
        let b = files[index].source.startAccessingSecurityScopedResource()
        defer { if a { root.stopAccessingSecurityScopedResource() }; if b { files[index].source.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try backupRoot().appendingPathComponent(UUID().uuidString + ".bak")
            try FileManager.default.copyItem(at: target, to: backup)
            let data = try Data(contentsOf: files[index].source)
            try data.write(to: target, options: .atomic)
            backups[files[index].relativePath] = backup
            files[index].active = true
            logs.insert("Patched: \(files[index].relativePath)", at: 0)
        } catch { alertText = "Patch failed: \(error.localizedDescription)" }
    }

    private func patchAll() {
        for i in files.indices where files[i].target != nil && !files[i].active { patch(i) }
    }

    private func restore(_ index: Int) {
        let file = files[index]
        guard let target = file.target, let backup = backups[file.relativePath], let root = targetFolder else {
            alertText = "No backup mapping found for this session."; return
        }
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        do {
            try Data(contentsOf: backup).write(to: target, options: .atomic)
            try? FileManager.default.removeItem(at: backup)
            backups.removeValue(forKey: file.relativePath)
            files[index].active = false
            logs.insert("Restored: \(file.relativePath)", at: 0)
        } catch { alertText = "Restore failed: \(error.localizedDescription)" }
    }
}
