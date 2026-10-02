#!/usr/bin/env python3
"""Generates MeasureMe.xcodeproj from the files under MeasureMe/.

Run from the repository root after adding or removing source files:

    python3 scripts/generate_xcodeproj.py

Object IDs are derived from file paths, so the output is deterministic.
(Alternatively, `xcodegen generate` with project.yml produces an equivalent project.)
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "MeasureMe"
PROJECT = "MeasureMe.xcodeproj"
PACKAGE_DIR = "MeasureMeKit"
PACKAGE_PRODUCT = "MeasureMeCore"
BUNDLE_ID = "com.example.MeasureMe"
DEPLOYMENT_TARGET = "17.0"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(s):
    """Quote a pbxproj string when needed."""
    if s and all(c.isalnum() or c in "._/$" for c in s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".xcassets": "folder.assetcatalog",
    ".xcprivacy": "text.xml",
    ".json": "text.json",
}


def collect():
    """Returns {relative dir: [entries]} for the app folder, treating .xcassets as leaf files."""
    files = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, APP_DIR)):
        rel_dir = os.path.relpath(dirpath, ROOT)
        keep = []
        for d in sorted(dirnames):
            if d.endswith(".xcassets"):
                files.append(os.path.join(rel_dir, d))
            else:
                keep.append(d)
        dirnames[:] = keep
        for f in sorted(filenames):
            if f.startswith("."):
                continue
            files.append(os.path.join(rel_dir, f))
    return sorted(files)


def main():
    files = collect()
    swift = [f for f in files if f.endswith(".swift")]
    resources = [f for f in files if f.endswith(".xcassets") or f.endswith(".xcprivacy")]

    project_id = oid("project")
    main_group = oid("group", "main")
    products_group = oid("group", "products")
    frameworks_group = oid("group", "frameworks")
    app_target = oid("target", "app")
    app_product = oid("product", "app")
    sources_phase = oid("phase", "sources")
    resources_phase = oid("phase", "resources")
    frameworks_phase = oid("phase", "frameworks")
    project_config_list = oid("configlist", "project")
    target_config_list = oid("configlist", "target")
    proj_debug, proj_release = oid("config", "project", "Debug"), oid("config", "project", "Release")
    tgt_debug, tgt_release = oid("config", "target", "Debug"), oid("config", "target", "Release")
    package_ref = oid("package", PACKAGE_DIR)
    package_file_ref = oid("fileref", PACKAGE_DIR)
    product_dep = oid("productdep", PACKAGE_PRODUCT)
    product_build_file = oid("buildfile", "product", PACKAGE_PRODUCT)

    # Groups mirror folders.
    groups = {}  # path -> (id, [child ids])

    def group_for(path):
        if path not in groups:
            groups[path] = (oid("group", path), [])
            parent = os.path.dirname(path)
            if parent and parent != path:
                group_for(parent)[1].append(groups[path][0])
        return groups[path]

    file_refs = {}
    for f in files:
        file_refs[f] = oid("fileref", f)
        group_for(os.path.dirname(f))[1].append(file_refs[f])

    out = []
    w = out.append
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 60;")
    w("\tobjects = {")
    w("")
    w("/* Begin PBXBuildFile section */")
    for f in swift:
        w(f"\t\t{oid('buildfile', f)} /* {os.path.basename(f)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {os.path.basename(f)} */; }};")
    for f in resources:
        w(f"\t\t{oid('buildfile', f)} /* {os.path.basename(f)} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {os.path.basename(f)} */; }};")
    w(f"\t\t{product_build_file} /* {PACKAGE_PRODUCT} in Frameworks */ = {{isa = PBXBuildFile; productRef = {product_dep} /* {PACKAGE_PRODUCT} */; }};")
    w("/* End PBXBuildFile section */")
    w("")
    w("/* Begin PBXFileReference section */")
    w(f"\t\t{app_product} /* MeasureMe.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MeasureMe.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{package_file_ref} /* {PACKAGE_DIR} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; path = {PACKAGE_DIR}; sourceTree = \"<group>\"; }};")
    for f in files:
        ext = os.path.splitext(f)[1]
        ftype = FILE_TYPES.get(ext, "text")
        name = os.path.basename(f)
        w(f"\t\t{file_refs[f]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {q(name)}; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")
    w("")
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{product_build_file} /* {PACKAGE_PRODUCT} in Frameworks */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")
    w("/* Begin PBXGroup section */")
    w(f"\t\t{main_group} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{package_file_ref} /* {PACKAGE_DIR} */,")
    w(f"\t\t\t\t{groups[APP_DIR][0]} /* {APP_DIR} */,")
    w(f"\t\t\t\t{frameworks_group} /* Frameworks */,")
    w(f"\t\t\t\t{products_group} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{products_group} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{app_product} /* MeasureMe.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{frameworks_group} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t);")
    w("\t\t\tname = Frameworks;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    for path in sorted(groups):
        gid, children = groups[path]
        name = os.path.basename(path)
        w(f"\t\t{gid} /* {name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for c in children:
            w(f"\t\t\t\t{c},")
        w("\t\t\t);")
        w(f"\t\t\tpath = {q(name)};")
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")
    w("/* End PBXGroup section */")
    w("")
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{app_target} /* MeasureMe */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"MeasureMe\" */;")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{sources_phase} /* Sources */,")
    w(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = MeasureMe;")
    w("\t\t\tpackageProductDependencies = (")
    w(f"\t\t\t\t{product_dep} /* {PACKAGE_PRODUCT} */,")
    w("\t\t\t);")
    w("\t\t\tproductName = MeasureMe;")
    w(f"\t\t\tproductReference = {app_product} /* MeasureMe.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")
    w("/* Begin PBXProject section */")
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t\tTargetAttributes = {")
    w(f"\t\t\t\t\t{app_target} = {{")
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"MeasureMe\" */;")
    w("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {main_group};")
    w("\t\t\tpackageReferences = (")
    w(f"\t\t\t\t{package_ref} /* XCLocalSwiftPackageReference \"{PACKAGE_DIR}\" */,")
    w("\t\t\t);")
    w(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{app_target} /* MeasureMe */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for f in resources:
        w(f"\t\t\t\t{oid('buildfile', f)} /* {os.path.basename(f)} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")
    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{sources_phase} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for f in swift:
        w(f"\t\t\t\t{oid('buildfile', f)} /* {os.path.basename(f)} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
    }
    debug_project = dict(common_project, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    release_project = dict(common_project, **{
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    })
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": '"Measure Me"',
        "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.lifestyle"',
        "INFOPLIST_KEY_NSCameraUsageDescription": q("Measure Me uses the camera to estimate your body measurements on this iPhone. Photos are processed on-device and are not uploaded."),
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }

    def config(cid, name, settings, comment):
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for k in sorted(settings):
            w(f"\t\t\t\t{k} = {settings[k]};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    w("/* Begin XCBuildConfiguration section */")
    config(proj_debug, "Debug", debug_project, "project")
    config(proj_release, "Release", release_project, "project")
    config(tgt_debug, "Debug", target_settings, "target")
    config(tgt_release, "Release", target_settings, "target")
    w("/* End XCBuildConfiguration section */")
    w("")
    w("/* Begin XCConfigurationList section */")
    for lid, debug, release, label in [
        (project_config_list, proj_debug, proj_release, 'PBXProject "MeasureMe"'),
        (target_config_list, tgt_debug, tgt_release, 'PBXNativeTarget "MeasureMe"'),
    ]:
        w(f"\t\t{lid} /* Build configuration list for {label} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w(f"\t\t\t\t{debug} /* Debug */,")
        w(f"\t\t\t\t{release} /* Release */,")
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("")
    w("/* Begin XCLocalSwiftPackageReference section */")
    w(f"\t\t{package_ref} /* XCLocalSwiftPackageReference \"{PACKAGE_DIR}\" */ = {{")
    w("\t\t\tisa = XCLocalSwiftPackageReference;")
    w(f"\t\t\trelativePath = {PACKAGE_DIR};")
    w("\t\t};")
    w("/* End XCLocalSwiftPackageReference section */")
    w("")
    w("/* Begin XCSwiftPackageProductDependency section */")
    w(f"\t\t{product_dep} /* {PACKAGE_PRODUCT} */ = {{")
    w("\t\t\tisa = XCSwiftPackageProductDependency;")
    w(f"\t\t\tpackage = {package_ref} /* XCLocalSwiftPackageReference \"{PACKAGE_DIR}\" */;")
    w(f"\t\t\tproductName = {PACKAGE_PRODUCT};")
    w("\t\t};")
    w("/* End XCSwiftPackageProductDependency section */")
    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")

    proj_dir = os.path.join(ROOT, PROJECT)
    os.makedirs(os.path.join(proj_dir, "project.xcworkspace", "xcshareddata"), exist_ok=True)
    os.makedirs(os.path.join(proj_dir, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as fh:
        fh.write("\n".join(out) + "\n")
    with open(os.path.join(proj_dir, "project.xcworkspace", "contents.xcworkspacedata"), "w") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
    with open(os.path.join(proj_dir, "project.xcworkspace", "xcshareddata", "IDEWorkspaceChecks.plist"), "w") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>IDEDidComputeMac32BitWarning</key>\n\t<true/>\n</dict>\n</plist>\n')
    app_ref = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "MeasureMe.app"
               BlueprintName = "MeasureMe"
               ReferencedContainer = "container:{PROJECT}">
            </BuildableReference>'''
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "MeasureMeCoreTests"
               BuildableName = "MeasureMeCoreTests"
               BlueprintName = "MeasureMeCoreTests"
               ReferencedContainer = "container:{PACKAGE_DIR}">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
    with open(os.path.join(proj_dir, "xcshareddata", "xcschemes", "MeasureMe.xcscheme"), "w") as fh:
        fh.write(scheme)
    print(f"Wrote {PROJECT} with {len(swift)} Swift files and {len(resources)} resources.")


if __name__ == "__main__":
    main()
