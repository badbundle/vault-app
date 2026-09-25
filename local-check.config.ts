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
    ],
  };
}) satisfies ConfigFunction;

/**
 * Puts rbenv's shims first on PATH. Shells that haven't run `rbenv init`
 * (non-interactive ones, like an agent's) would otherwise find the system Ruby
 * and skip the Fastlane check.
 */
async function rubyEnv(ctx: Context): Promise<Record<string, string>> {
  const { exitCode, stdout } = await ctx.capture(["rbenv", "root"]);
  return exitCode === 0 ? { PATH: `${stdout.trim()}/shims:${process.env.PATH}` } : {};
}
