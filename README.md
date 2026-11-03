# PatchKit starter

SwiftUI prototype for replacing files only inside folders explicitly selected by the user through the iOS Files picker. The main view is split into smaller computed view sections to reduce SwiftUI type-checking complexity.

## Build an unsigned IPA
1. Create a GitHub repository and upload this folder's contents to its root.
2. Push to `main`, or run **Build unsigned iOS IPA** from the Actions tab.
3. Download the `PatchKit-unsigned-ipa` artifact from the completed workflow.

GitHub Actions uses a macOS runner, Xcode and XcodeGen to build and package the app.

## Important limitations
- The app can only access folders that iOS grants through the document picker/file provider. It cannot access another app's private container or App Group just because a folder is selected.
- Backup mapping is currently kept in memory; closing the app loses the current session's restore mapping. Persistent recovery is a next development step.
- Test only with copies of files you own or are authorized to modify.
- Bundle ID is `app.patchkit.ios` in `project.yml`.
