"""Regenerate the self-contained Xcode project, including unit/UI test targets."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(name, value):
    objects[ident(name)] = value
    return ident(name)
def q(value): return json.dumps(str(value))
def arr(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def settings(values): return '{ ' + ' '.join(f'{k} = {q(v)};' for k, v in values.items()) + ' }'

appfiles = ['PersonalStylistApp.swift', 'ContentView.swift'] + [str(p.relative_to(root)) for d in ['Core', 'Services', 'Views'] for p in sorted((root / d).glob('*.swift'))]
resources = ['Assets.xcassets', 'LocalConfig.plist']
testfiles = [str(p.relative_to(root)) for p in sorted((root / 'Tests').glob('*.swift'))]
uifiles = [str(p.relative_to(root)) for p in sorted((root / 'UITests').glob('*.swift'))]
refs = []
def file(path, kind):
    key = obj('file:' + path, f'{{isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = SOURCE_ROOT; }}')
    refs.append(key)
    return key
for path in appfiles + testfiles + uifiles: file(path, 'sourcecode.swift')
for path in resources: file(path, 'folder.assetcatalog' if path.endswith('xcassets') else 'text.plist.xml')
for path in ['Config/Info.plist', 'Config/PersonalStylist.entitlements']: file(path, 'text.plist.xml')
for path in ['README.md', 'docs/setup.md']: file(path, 'net.daringfireball.markdown')
for path in ['LocalConfig.example.plist']: file(path, 'text.plist.xml')
for path in ['docs/backend.local.env.example', 'docs/backend.live.env.example']: file(path, 'text')
products = []
def phase(name, kind, paths):
    builds = [obj('build:' + name + ':' + p, f'{{isa = PBXBuildFile; fileRef = {ident("file:" + p)}; }}') for p in paths]
    return obj(name, f'{{isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0; }}')
def configs(name, values):
    configs = []
    for mode in ['Debug', 'Release']:
        v = dict(values)
        v.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if mode == 'Debug' else ''})
        configs.append(obj(name + ':' + mode, f'{{isa = XCBuildConfiguration; buildSettings = {settings(v)}; name = {mode}; }}'))
    return obj(name + ':configs', f'{{isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
common = {'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0', 'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'TARGETED_DEVICE_FAMILY': '1', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_TESTABILITY': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'targeted', 'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_NAME': '$(TARGET_NAME)', 'SWIFT_EMIT_LOC_STRINGS': 'YES'}
targets = []
for name, paths, kind in [('PersonalStylist', appfiles, 'application'), ('PersonalStylistTests', testfiles, 'bundle.unit-test'), ('PersonalStylistUITests', uifiles, 'bundle.ui-testing')]:
    product = name + ('.app' if name == 'PersonalStylist' else '.xctest')
    products.append(obj('product:' + name, f'{{isa = PBXFileReference; explicitFileType = {"wrapper.application" if name == "PersonalStylist" else "wrapper.cfbundle"}; path = {q(product)}; sourceTree = BUILT_PRODUCTS_DIR; }}'))
    v = dict(common, PRODUCT_BUNDLE_IDENTIFIER='com.personalstylist.beta' + ('' if name == 'PersonalStylist' else '.' + name), LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @loader_path/Frameworks')
    dependencies = []
    if name == 'PersonalStylist': v.update({'INFOPLIST_FILE': 'Config/Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Config/PersonalStylist.entitlements', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '0.1.0', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon'})
    else:
        proxy = obj('proxy:' + name, f'{{isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target:PersonalStylist")}; remoteInfo = PersonalStylist; }}')
        dependencies = [obj('dependency:' + name, f'{{isa = PBXTargetDependency; target = {ident("target:PersonalStylist")}; targetProxy = {proxy}; }}')]
        if name == 'PersonalStylistTests': v.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/PersonalStylist.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PersonalStylist', 'BUNDLE_LOADER': '$(TEST_HOST)'})
        else: v['TEST_TARGET_NAME'] = 'PersonalStylist'
    phases = [phase(name + ':sources', 'Sources', paths), phase(name + ':frameworks', 'Frameworks', []), phase(name + ':resources', 'Resources', resources if name == 'PersonalStylist' else [])]
    target = obj('target:' + name, f'{{isa = PBXNativeTarget; buildConfigurationList = {configs(name, v)}; buildPhases = {arr(phases)}; buildRules = (); dependencies = {arr(dependencies)}; name = {name}; productName = {name}; productReference = {products[-1]}; productType = {q("com.apple.product-type." + kind)}; }}')
    targets.append(target)
productgroup = obj('products', f'{{isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>"; }}')
maingroup = obj('main', f'{{isa = PBXGroup; children = {arr(refs + [productgroup])}; sourceTree = "<group>"; }}')
project = obj('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }}; buildConfigurationList = {configs("project", common)}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {maingroup}; productRefGroup = {productgroup}; projectDirPath = ""; projectRoot = ""; targets = {arr(targets)}; }}')
projectdir = root / 'Personal Stylist.xcodeproj'
projectdir.mkdir(exist_ok=True)
(projectdir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(k + ' = ' + v + ';' for k,v in objects.items()) + '\n}; rootObject = ' + project + '; }\n')
schemes = projectdir / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
def ref(name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:" + name)}" BuildableName="{name}{".app" if name == "PersonalStylist" else ".xctest"}" BlueprintName="{name}" ReferencedContainer="container:Personal Stylist.xcodeproj"/>'
(schemes / 'Personal Stylist.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('PersonalStylist')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref('PersonalStylistTests')}</TestableReference><TestableReference skipped="NO">{ref('PersonalStylistUITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('PersonalStylist')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref('PersonalStylist')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Personal Stylist app and test targets.')
