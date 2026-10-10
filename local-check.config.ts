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

const appGroup = "442P244AFS.com.badbundle.vault";

/**
 * Builds the Mac app as it runs, rather than for testing, which adds entitlements of Xcode's own, and fails unless
 * the app and its AutoFill extension are each signed with the hardened runtime, sandboxed in the App Group, with only
 * their own keychain access groups, and with no entitlement the design doesn't list. The app's own group isn't the
 * extension's, so the extension can't read the app's keychain items.
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
  await checkSignedEntitlements(ctx, app, "Vault.app", macAppEntitlements, [`${appGroup}.private`, appGroup]);
  await checkSignedEntitlements(
    ctx,
    `${app}/Contents/PlugIns/VaultMacAutofill.appex`,
    "VaultMacAutofill.appex",
    macAutofillEntitlements,
    [appGroup],
  );
}

async function checkSignedEntitlements(
  ctx: Context,
  bundle: string,
  name: string,
  allowed: string[],
  keychainGroups: string[],
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
  const groups = JSON.stringify(entitlements["com.apple.security.application-groups"]);
  if (entitlements["com.apple.security.app-sandbox"] !== true || groups !== JSON.stringify([appGroup])) {
    throw new Error(`${name} isn't sandboxed in its App Group: ${JSON.stringify(entitlements)}`);
  }
  const keychain = JSON.stringify(entitlements["keychain-access-groups"]);
  if (keychain !== JSON.stringify(keychainGroups)) {
    throw new Error(`${name}'s keychain access groups aren't ${JSON.stringify(keychainGroups)}: ${keychain}`);
  }
  ctx.log(`${name}'s entitlements: ${Object.keys(entitlements).join(", ")}`);
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
