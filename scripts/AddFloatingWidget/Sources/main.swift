import Foundation
import PathKit
import XcodeProj

// MARK: - Entry point
//
// Takes one argument: the focus-ios directory (where Blockzilla.xcodeproj lives).
// Reads TEAM_ID and APP_NAME from environment variables set by the calling script.
//
// Handles (replaces bash sed steps 3b/3c, 4, 5, 6 + widget file registration):
//   · DEVELOPMENT_TEAM set on all build configs (blank FocusEnterprise + leftovers)
//   · Platform-conditional DEVELOPMENT_TEAM[sdk=iphoneos*] removed
//   · All PROVISIONING_PROFILE_SPECIFIER variants and PROVISIONING_PROFILE removed
//   · CODE_SIGN_IDENTITY[sdk=iphoneos*] overrides removed
//   · CODE_SIGN_STYLE = Automatic forced on all configurations
//   · DISPLAY_NAME / PRODUCT_NAME renamed from Firefox variants to APP_NAME
//   · FloatingWidget source files registered in the Blockzilla target

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: AddFloatingWidget <path/to/focus-ios/>\n", stderr)
    exit(1)
}

let focusDir    = Path(CommandLine.arguments[1])
let projectPath = focusDir + "Blockzilla.xcodeproj"
let widgetDir   = (focusDir + "Blockzilla" + "FloatingWidget").string

let env     = ProcessInfo.processInfo.environment
guard let teamID = env["TEAM_ID"], !teamID.isEmpty else {
    fputs("ERROR: TEAM_ID environment variable is not set or empty.\n", stderr)
    fputs("       Run via apply-focus-enterprise.sh or set: export TEAM_ID=<your-10-char-id>\n", stderr)
    exit(1)
}
guard let appName = env["APP_NAME"], !appName.isEmpty else {
    fputs("ERROR: APP_NAME environment variable is not set or empty.\n", stderr)
    fputs("       Run via apply-focus-enterprise.sh or set: export APP_NAME=<your-app-name>\n", stderr)
    exit(1)
}

// MARK: - Open project

let xcodeproj: XcodeProj
do {
    xcodeproj = try XcodeProj(path: projectPath)
} catch {
    fputs("ERROR: Could not open \(projectPath): \(error)\n", stderr)
    exit(1)
}

let pbxproj = xcodeproj.pbxproj

// MARK: - Remove non-English localizations
if let root = pbxproj.rootObject {
    root.knownRegions = ["en", "Base"]
}

for variantGroup in pbxproj.variantGroups {
    let childrenToRemove = variantGroup.children.filter { fileRef in
        if let name = fileRef.name {
            return name != "en" && name != "Base"
        }
        return false
    }
    
    for child in childrenToRemove {
        variantGroup.children.removeAll(where: { $0 === child })
        pbxproj.delete(object: child)
    }
}

// MARK: - Build settings patch

let firefoxNames: Set<String> = ["Firefox Focus", "Firefox Klar"]

// Exact keys to unconditionally remove from every build configuration.
let exactKeysToRemove: Set<String> = [
    "DEVELOPMENT_TEAM[sdk=iphoneos*]",
    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]",
    "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
    "PROVISIONING_PROFILE",
]

// Key prefixes — removes any conditional variant (e.g. KEY[sdk=...]).
let prefixKeysToRemove: [String] = ["PROVISIONING_PROFILE_SPECIFIER"]

for config in pbxproj.buildConfigurations {
    var s = config.buildSettings

    s["DEVELOPMENT_TEAM"] = teamID
    s["CODE_SIGN_STYLE"] = "Automatic"

    for key in exactKeysToRemove { s.removeValue(forKey: key) }
    s = s.filter { key, _ in
        !prefixKeysToRemove.contains(where: { key.hasPrefix($0) })
    }

    if let dn = s["DISPLAY_NAME"] as? String, firefoxNames.contains(dn) { s["DISPLAY_NAME"] = appName }
    if let pn = s["PRODUCT_NAME"] as? String, firefoxNames.contains(pn) { s["PRODUCT_NAME"] = appName }

    config.buildSettings = s
}

// MARK: - FloatingWidget group + file registration

func findGroup(named name: String, in group: PBXGroup) -> PBXGroup? {
    group.children
        .compactMap { $0 as? PBXGroup }
        .first { ($0.name == name) || ($0.path == name) }
}

guard let mainGroup = pbxproj.rootObject?.mainGroup else {
    fputs("ERROR: No main group in project\n", stderr)
    exit(1)
}

guard let blockzillaGroup = findGroup(named: "Blockzilla", in: mainGroup) else {
    fputs("ERROR: 'Blockzilla' group not found in project navigator\n", stderr)
    exit(1)
}

guard let target = pbxproj.nativeTargets.first(where: { $0.name == "Blockzilla" }) else {
    fputs("ERROR: 'Blockzilla' target not found\n", stderr)
    exit(1)
}

for config in target.buildConfigurationList?.buildConfigurations ?? [] {
    config.buildSettings["CODE_SIGN_ENTITLEMENTS"] = "Blockzilla/Focus.entitlements"
}

if findGroup(named: "FloatingWidget", in: blockzillaGroup) != nil {
    print("FloatingWidget group already present — skipping file registration.")
} else {
    let sourcesBuildPhase: PBXSourcesBuildPhase
    do {
        guard let phase = try target.sourcesBuildPhase() else {
            fputs("ERROR: No Sources build phase on 'Blockzilla' target\n", stderr)
            exit(1)
        }
        sourcesBuildPhase = phase
    } catch {
        fputs("ERROR: \(error)\n", stderr)
        exit(1)
    }

    let widgetGroup = PBXGroup(
        children: [], sourceTree: .group, name: "FloatingWidget", path: "FloatingWidget"
    )
    pbxproj.add(object: widgetGroup)
    blockzillaGroup.children.append(widgetGroup)

    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(atPath: widgetDir)
    var sourceFiles: [String] = []
    while let file = enumerator?.nextObject() as? String {
        if file.hasSuffix(".swift") || file.hasSuffix(".m") {
            sourceFiles.append(file)
        }
    }

    for fileName in sourceFiles {
        let srcPath = (widgetDir as NSString).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: srcPath) else {
            fputs("ERROR: source file not found: \(srcPath)\n", stderr)
            exit(1)
        }

        let type = fileName.hasSuffix(".swift") ? "sourcecode.swift" : "sourcecode.c.objc"
        let fileRef = PBXFileReference(
            sourceTree: .group,
            name: (fileName as NSString).lastPathComponent,
            lastKnownFileType: type,
            path: fileName
        )
        pbxproj.add(object: fileRef)
        widgetGroup.children.append(fileRef)

        let buildFile = PBXBuildFile(file: fileRef)
        pbxproj.add(object: buildFile)
        sourcesBuildPhase.files = (sourcesBuildPhase.files ?? []) + [buildFile]
    }
}

// MARK: - Save

do {
    try xcodeproj.write(path: projectPath)
    print("OK: project.pbxproj updated (build settings + FloatingWidget files).")
} catch {
    fputs("ERROR: Could not write project: \(error)\n", stderr)
    exit(1)
}
