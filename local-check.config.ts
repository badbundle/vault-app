import type { ConfigFunction, Context } from "@badbundle/local-check";

// The checks `make validate` runs on a commit before it posts the green
// "Validate (local)" check. See README.md#validation.
export default (({ xcode }) => {
  const ios = xcode({
    version: "27.0",
    // The snapshot tests check the device name, so the throwaway simulator
    // has to use exactly this one.
    simulator: {
      name: "iPhone 18 Pro Max",
      deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max",
      runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
    },
  });

  return {
    // SwiftLint and swift-format build into Vault/.build; keeping it makes
    // lint incremental.
    worktree: { keep: ["Vault/.build"] },
    setup: [ios.setup],
    checks: [
      { name: "Lint", run: ["make", "-C", "Vault", "lint"] },
      {
        name: "Fastlane config",
        async skip(ctx) {
          const wanted = (await Bun.file(`${ctx.worktree}/.ruby-version`).text()).trim();
          const { stdout } = await ctx.capture(["ruby", "-e", "print RUBY_VERSION"], { env: await rubyEnv(ctx) });
          return stdout === wanted ? undefined : `Ruby ${wanted} from .ruby-version isn't installed`;
        },
        async run(ctx) {
          const env = await rubyEnv(ctx);
          await ctx.exec(["bundle", "install", "--quiet"], { env });
          await ctx.exec(["bundle", "exec", "ruby", "-c", "fastlane/Fastfile"], { env });
          await ctx.exec(["bundle", "exec", "fastlane", "lanes"], { env });
        },
      },
      ios.buildForTesting({
        name: "Build",
        workspace: "Vault.xcworkspace",
        scheme: "CI_iOS",
        testPlan: "iOSAllTests",
        flags: ["-skipMacroValidation", "-skipPackagePluginValidation"],
      }),
      ios.testWithoutBuilding(),
      // The UI tests are in the app's project, as a Swift package can't hold
      // them, so they have a scheme of their own. They build into the same
      // DerivedData, which by now has the package built and its dependencies
      // resolved. Each test step runs the newest .xctestrun, which every
      // build rewrites, so each build has to stay just before its tests.
      ios.buildForTesting({
        name: "Build UI tests",
        workspace: "Vault.xcworkspace",
        scheme: "VaultAppUITests",
        testPlan: "VaultAppUITests",
        flags: ["-skipMacroValidation", "-skipPackagePluginValidation", "-skipPackageUpdates"],
      }),
      ios.testWithoutBuilding({ name: "UI tests" }),
      {
        name: "iOS app entitlements",
        async run(ctx) {
          await checkIOSAppEntitlements(ctx, ios.derivedData(ctx), ios.destination);
        },
      },
      // The shared modules, built and tested for the Mac as well, so work on either platform can't break the other
      // (docs/mac-app.md). Last, so its .xctestrun is the newest when its tests run.
      ios.buildForTesting({
        name: "Build (macOS)",
        workspace: "Vault.xcworkspace",
        scheme: "CI_macOS",
        testPlan: "macOS_SupportedTests",
        destination: "platform=macOS",
        flags: ["-skipMacroValidation", "-skipPackagePluginValidation", "-skipPackageUpdates"],
      }),
      ios.testWithoutBuilding({ name: "Tests (macOS)", destination: "platform=macOS" }),
      // The Mac app, launched with its tests inside it: it starts, sandboxed, in its App Group.
      ios.buildForTesting({
        name: "Build Mac app tests",
        workspace: "Vault.xcworkspace",
        scheme: "VaultMacApp",
        testPlan: "VaultMacAppTests",
        destination: "platform=macOS",
        flags: ["-skipMacroValidation", "-skipPackagePluginValidation", "-skipPackageUpdates"],
      }),
      ios.testWithoutBuilding({ name: "Mac app tests", destination: "platform=macOS" }),
      {
        name: "Mac app entitlements",
        async run(ctx) {
          await checkMacAppEntitlements(ctx, ios.derivedData(ctx));
        },
      },
      // After both apps are built, as it reads their bundles.
      {
        name: "Versions",
        async run(ctx) {
          await checkVersions(ctx, ios.derivedData(ctx));
        },
      },
      // The Mac app's UI tests, in their own scheme as the iOS app's are. Each build stays just before its tests.
      {
        ...ios.buildForTesting({
          name: "Build Mac UI tests",
          workspace: "Vault.xcworkspace",
          scheme: "VaultMacAppUITests",
          testPlan: "VaultMacAppUITests",
          destination: "platform=macOS",
          flags: ["-skipMacroValidation", "-skipPackagePluginValidation", "-skipPackageUpdates"],
        }),
        skip: skipMacUITests,
      },
      { ...ios.testWithoutBuilding({ name: "Mac UI tests", destination: "platform=macOS" }), skip: skipMacUITests },
    ],
  };
}) satisfies ConfigFunction;

/**
 * Skips the Mac app's UI tests when `VAULT_SKIP_MAC_UI_TESTS=1` is set, for a Mac whose screen is locked, where every
 * one of them fails to activate the app. The run's output and stored result name both checks as skipped.
 */
function skipMacUITests(): string | undefined {
  return process.env.VAULT_SKIP_MAC_UI_TESTS === "1" ? "VAULT_SKIP_MAC_UI_TESTS is set" : undefined;
}

/**
 * The entitlements the Mac app may have, from docs/mac-app.md's "App Sandbox" table, and the two its provisioning
 * profile adds, which name the app and its team. A development build also lets the debugger attach
 * (`get-task-allow`), which an App Store build doesn't.
 */
const macAppEntitlements = [
  "com.apple.application-identifier",
  "com.apple.developer.team-identifier",
  "com.apple.security.app-sandbox",
  "com.apple.security.application-groups",
  "com.apple.security.device.camera",
  "com.apple.security.files.bookmarks.app-scope",
  "com.apple.security.files.user-selected.read-write",
  "com.apple.security.get-task-allow",
  "com.apple.security.print",
  "keychain-access-groups",
];

/** The entitlements the Mac app's AutoFill extension may have: the same table's, and its profile's. */
const macAutofillEntitlements = [
  "com.apple.application-identifier",
  "com.apple.developer.authentication-services.autofill-credential-provider",
  "com.apple.developer.team-identifier",
  "com.apple.security.app-sandbox",
  "com.apple.security.application-groups",
  "com.apple.security.get-task-allow",
  "keychain-access-groups",
];

/**
 * The entitlements the Mac app's widget extension may have: the same table's, and its profile's. No App Group, which
 * would also make it a member of the App Group's keychain access group, and no keychain access group but the widgets'
 * own: not the one the app shares with its AutoFill extension.
 */
const macWidgetsEntitlements = [
  "com.apple.application-identifier",
  "com.apple.developer.team-identifier",
  "com.apple.security.app-sandbox",
  "com.apple.security.get-task-allow",
  "keychain-access-groups",
];

const appGroup = "442P244AFS.com.badbundle.vault";

/**
 * The keychain access group the app shares with its AutoFill extension, and nothing else, on iOS and the Mac. It holds
 * the attempt counter, the wrap stamp and the Mac's app lock settings (VAULT-129).
 */
const sharedKeychainGroup = "442P244AFS.com.badbundle.vault.shared";

/**
 * Builds the Mac app as it runs, rather than for testing, which adds entitlements of Xcode's own, and fails unless
 * the app and its AutoFill and widget extensions are each signed with the hardened runtime and sandboxed, with only
 * their own keychain access groups, and with no entitlement the design doesn't list. The app and its AutoFill
 * extension are in the App Group; the widget extension isn't, as an App Group is also a keychain access group. The
 * app's own group is neither extension's, so neither can read the app's keychain items; the shared group, which holds
 * the attempt counter, is only the AutoFill extension's and the app's; and the widgets' group, which holds the codes
 * the app hands them, is only the widget extension's and the app's.
 */
async function checkMacAppEntitlements(ctx: Context, derivedData: string): Promise<void> {
  await ctx.exec([
    "xcodebuild",
    "build",
    "-workspace",
    "Vault.xcworkspace",
    "-scheme",
    "VaultMacApp",
    "-destination",
    "platform=macOS",
    "-derivedDataPath",
    derivedData,
    "-skipMacroValidation",
    "-skipPackagePluginValidation",
    "-skipPackageUpdates",
  ]);
  const app = `${derivedData}/Build/Products/Debug/Vault.app`;
  await checkSignedEntitlements(ctx, app, "Vault.app", macAppEntitlements, [
    `${appGroup}.private`,
    appGroup,
    sharedKeychainGroup,
    `${appGroup}.widgets`,
  ]);
  await checkSignedEntitlements(
    ctx,
    `${app}/Contents/PlugIns/VaultMacAutofill.appex`,
    "VaultMacAutofill.appex",
    macAutofillEntitlements,
    [appGroup, sharedKeychainGroup],
  );
  await checkSignedEntitlements(
    ctx,
    `${app}/Contents/PlugIns/VaultMacWidgets.appex`,
    "VaultMacWidgets.appex",
    macWidgetsEntitlements,
    [`${appGroup}.widgets`],
    [],
  );
}

/**
 * Fails unless `bundle` is signed with the hardened runtime and sandboxed, has no entitlement but those `allowed`, and
 * has exactly these App Groups (none, if empty) and keychain access groups.
 */
async function checkSignedEntitlements(
  ctx: Context,
  bundle: string,
  name: string,
  allowed: string[],
  keychainGroups: string[],
  appGroups: string[] = [appGroup],
): Promise<void> {
  const signature = await ctx.capture(["codesign", "--display", "--verbose", bundle]);
  if (!/flags=0x[0-9a-f]+\(runtime\)/.test(signature.stderr)) {
    throw new Error(`${name} isn't signed with the hardened runtime:\n${signature.stderr}`);
  }
  const plist = `${ctx.cacheDir}/${name}-entitlements.plist`;
  await ctx.exec(["codesign", "--display", "--xml", "--entitlements", plist, bundle]);
  const { stdout } = await ctx.capture(["plutil", "-convert", "json", "-o", "-", plist]);
  const entitlements = JSON.parse(stdout) as Record<string, unknown>;
  const unlisted = Object.keys(entitlements).filter((key) => !allowed.includes(key));
  if (unlisted.length > 0) {
    throw new Error(`${name} has entitlements docs/mac-app.md doesn't list: ${unlisted.join(", ")}`);
  }
  const groups = JSON.stringify(entitlements["com.apple.security.application-groups"] ?? []);
  if (entitlements["com.apple.security.app-sandbox"] !== true || groups !== JSON.stringify(appGroups)) {
    const expected = JSON.stringify(appGroups);
    throw new Error(`${name} isn't sandboxed with App Groups ${expected}: ${JSON.stringify(entitlements)}`);
  }
  const keychain = JSON.stringify(entitlements["keychain-access-groups"]);
  if (keychain !== JSON.stringify(keychainGroups)) {
    throw new Error(`${name}'s keychain access groups aren't ${JSON.stringify(keychainGroups)}: ${keychain}`);
  }
  ctx.log(`${name}'s entitlements: ${Object.keys(entitlements).join(", ")}`);
}

/** The iOS app's App Group, which every iOS target shares, as the widget extension reads the vault from it. */
const iosAppGroup = "group.com.badbundle.vault-group";

/** The entitlements the iOS app may have, from its entitlements file, and the identifier its signing adds. */
const iosAppEntitlements = [
  "application-identifier",
  "com.apple.developer.authentication-services.autofill-credential-provider",
  "com.apple.developer.default-data-protection",
  "com.apple.security.application-groups",
  "keychain-access-groups",
];

/** The entitlements the iOS AutoFill extension may have: its file's, and the identifier its signing adds. */
const iosAutofillEntitlements = [
  "application-identifier",
  "com.apple.developer.authentication-services.autofill-credential-provider",
  "com.apple.security.application-groups",
  "keychain-access-groups",
];

/**
 * The entitlements the iOS widget extension may have: the App Group, which it reads the vault from, and the identifier
 * its signing adds. No keychain access group of its own, so its keychain is only its own and the App Group's, which
 * holds the device key it opens the vault with while the App Lock Password is off.
 */
const iosWidgetsEntitlements = ["application-identifier", "com.apple.security.application-groups"];

/**
 * Builds the iOS app for the simulator as it runs, rather than for testing, and fails unless the app and its AutoFill
 * and widget extensions each have only the App Group, only their own keychain access groups, and no entitlement their
 * lists don't have. The shared group, which holds the attempt counter and the wrap stamp, is only the app's and the
 * AutoFill extension's: the widget extension has the App Group, which is also a keychain access group, and no other
 * (VAULT-129). A simulator build is signed ad hoc, with its entitlements in its executable, which the simulator keeps
 * to as a device keeps to a signature's.
 */
async function checkIOSAppEntitlements(ctx: Context, derivedData: string, destination: string): Promise<void> {
  await ctx.exec([
    "xcodebuild",
    "build",
    "-workspace",
    "Vault.xcworkspace",
    "-scheme",
    "VaultApp",
    "-destination",
    destination,
    "-derivedDataPath",
    derivedData,
    "-skipMacroValidation",
    "-skipPackagePluginValidation",
    "-skipPackageUpdates",
  ]);
  const app = `${derivedData}/Build/Products/Debug-iphonesimulator/VaultApp.app`;
  await checkSimulatorEntitlements(ctx, `${app}/VaultApp`, "VaultApp.app", iosAppEntitlements, [
    "442P244AFS.com.badbundle.vault",
    sharedKeychainGroup,
  ]);
  await checkSimulatorEntitlements(
    ctx,
    `${app}/PlugIns/VaultAppAutofill.appex/VaultAppAutofill`,
    "VaultAppAutofill.appex",
    iosAutofillEntitlements,
    ["442P244AFS.com.badbundle.vault.VaultAutofill", sharedKeychainGroup],
  );
  await checkSimulatorEntitlements(
    ctx,
    `${app}/PlugIns/VaultWidgetsExtension.appex/VaultWidgetsExtension`,
    "VaultWidgetsExtension.appex",
    iosWidgetsEntitlements,
    undefined,
  );
}

/**
 * Fails unless the simulator build's `executable` has no entitlement but those `allowed`, exactly the iOS App Group,
 * and exactly these keychain access groups (none, if `undefined`).
 */
async function checkSimulatorEntitlements(
  ctx: Context,
  executable: string,
  name: string,
  allowed: string[],
  keychainGroups: string[] | undefined,
): Promise<void> {
  const plist = `${ctx.cacheDir}/${name}-simulator-entitlements.plist`;
  await ctx.exec(["xcrun", "segedit", executable, "-extract", "__TEXT", "__entitlements", plist]);
  const { stdout } = await ctx.capture(["plutil", "-convert", "json", "-o", "-", plist]);
  const entitlements = JSON.parse(stdout) as Record<string, unknown>;
  const unlisted = Object.keys(entitlements).filter((key) => !allowed.includes(key));
  if (unlisted.length > 0) {
    throw new Error(`${name} has entitlements it shouldn't: ${unlisted.join(", ")}`);
  }
  const groups = JSON.stringify(entitlements["com.apple.security.application-groups"] ?? []);
  if (groups !== JSON.stringify([iosAppGroup])) {
    throw new Error(`${name}'s App Groups aren't ${JSON.stringify([iosAppGroup])}: ${groups}`);
  }
  const keychain = JSON.stringify(entitlements["keychain-access-groups"]);
  if (keychain !== JSON.stringify(keychainGroups)) {
    throw new Error(`${name}'s keychain access groups aren't ${JSON.stringify(keychainGroups)}: ${keychain}`);
  }
  ctx.log(`${name}'s entitlements: ${Object.keys(entitlements).join(", ")}`);
}

/**
 * Fails unless every app and extension Vault ships, on iOS and the Mac, has the version in VaultApp/Version.xcconfig and
 * one build number, as they always ship together (RELEASE.md). The project's configurations are based on that file, so
 * no target may set either setting itself, and each bundle the build steps made must say the same.
 */
async function checkVersions(ctx: Context, derivedData: string): Promise<void> {
  const xcconfig = await Bun.file(`${ctx.worktree}/VaultApp/Version.xcconfig`).text();
  const version = /^MARKETING_VERSION = (\S+)$/m.exec(xcconfig)?.[1];
  if (!version) {
    throw new Error("VaultApp/Version.xcconfig doesn't set MARKETING_VERSION");
  }
  const project = await Bun.file(`${ctx.worktree}/VaultApp/VaultApp.xcodeproj/project.pbxproj`).text();
  const overrides = (project.match(/^\s*(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = .*$/gm) ?? []).map((line) =>
    line.trim(),
  );
  if (overrides.length > 0) {
    throw new Error(
      `VaultApp.xcodeproj sets versions of its own, which belong in VaultApp/Version.xcconfig:\n${overrides.join("\n")}`,
    );
  }
  const ios = `${derivedData}/Build/Products/Debug-iphonesimulator/VaultApp.app`;
  const mac = `${derivedData}/Build/Products/Debug/Vault.app/Contents`;
  const bundles: Record<string, string> = {
    "VaultApp.app": `${ios}/Info.plist`,
    "VaultAppAutofill.appex": `${ios}/PlugIns/VaultAppAutofill.appex/Info.plist`,
    "VaultWidgetsExtension.appex": `${ios}/PlugIns/VaultWidgetsExtension.appex/Info.plist`,
    "Vault.app (Mac)": `${mac}/Info.plist`,
    "VaultMacAutofill.appex": `${mac}/PlugIns/VaultMacAutofill.appex/Contents/Info.plist`,
    "VaultMacWidgets.appex": `${mac}/PlugIns/VaultMacWidgets.appex/Contents/Info.plist`,
  };
  const found: { name: string; version: unknown; build: unknown }[] = [];
  for (const [name, plist] of Object.entries(bundles)) {
    const { exitCode, stdout, stderr } = await ctx.capture(["plutil", "-convert", "json", "-o", "-", plist]);
    if (exitCode !== 0) {
      throw new Error(`Can't read ${name}'s Info.plist at ${plist}: ${stderr}`);
    }
    const info = JSON.parse(stdout) as Record<string, unknown>;
    found.push({ name, version: info.CFBundleShortVersionString, build: info.CFBundleVersion });
  }
  const listed = found.map((bundle) => `${bundle.name}: ${String(bundle.version)} (${String(bundle.build)})`).join("\n");
  const builds = new Set(found.map((bundle) => bundle.build));
  if (found.some((bundle) => bundle.version !== version) || builds.size !== 1) {
    throw new Error(`Not every bundle has version ${version} and one build number:\n${listed}`);
  }
  ctx.log(`Every app and extension is version ${version}:\n${listed}`);
}

/**
 * Puts rbenv's shims first on PATH. Shells that haven't run `rbenv init`
 * (non-interactive ones, like an agent's) would otherwise find the system Ruby
 * and skip the Fastlane check.
 */
async function rubyEnv(ctx: Context): Promise<Record<string, string>> {
  const { exitCode, stdout } = await ctx.capture(["rbenv", "root"]);
  return exitCode === 0 ? { PATH: `${stdout.trim()}/shims:${process.env.PATH}` } : {};
}
