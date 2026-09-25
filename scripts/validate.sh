#!/bin/bash
# Validates a commit on this Mac in place of hosted CI, and posts the result to
# GitHub as the "Validate (local)" commit status, which main requires before a
# PR can merge. See README.md#validation.
#
# It runs lint, the Fastlane config check, and a build and full run of the
# iOSAllTests test plan on the exact commit, in a separate worktree with its own
# DerivedData and a throwaway simulator, so uncommitted changes and your usual
# build folders and simulator can't affect the result.
#
# Usage:
#   scripts/validate.sh [--clean] [<commit>]   validate <commit> (default: HEAD);
#                                              --clean rebuilds from scratch
#   scripts/validate.sh --post <commit>        post a stored result once the
#                                              commit is on GitHub (used by
#                                              .githooks/pre-push)

set -euo pipefail

CONTEXT="Validate (local)"
XCODE_VERSION="27.0"
# The snapshot tests check the device name, so the throwaway simulator has to
# use exactly this one.
SIMULATOR_NAME="iPhone 18 Pro Max"
SIMULATOR_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max"
SIMULATOR_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

repo_root=$(git rev-parse --show-toplevel)
state_dir="$(cd "$repo_root" && cd "$(git rev-parse --git-common-dir)" && pwd)/validate"
results_dir="$state_dir/results"
logs_dir="$state_dir/logs"
work_dir="$HOME/Library/Caches/vault-validate"
worktree="$work_dir/worktree"
derived_data="$work_dir/DerivedData"
repo=$(cd "$repo_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)

on_github() {
  gh api --silent "repos/$repo/commits/$1" >/dev/null 2>&1
}

post_status() { # <sha> <state> <description>
  gh api --silent -X POST "repos/$repo/statuses/$1" \
    -f state="$2" -f context="$CONTEXT" -f description="$3"
}

if [ "${1:-}" = "--post" ]; then
  sha=$(git rev-parse "${2:?usage: validate.sh --post <commit>}^{commit}")
  [ -f "$results_dir/$sha" ] || exit 0
  IFS=$'\t' read -r state description <"$results_dir/$sha"
  # The pre-push hook runs this just before the push lands, so wait for GitHub
  # to have the commit.
  for _ in $(seq 1 60); do
    if on_github "$sha"; then
      post_status "$sha" "$state" "$description"
      exit 0
    fi
    sleep 2
  done
  echo "validate: gave up waiting for $sha to reach GitHub; run scripts/validate.sh --post $sha" >&2
  exit 1
fi

clean=false
if [ "${1:-}" = "--clean" ]; then
  clean=true
  shift
fi
sha=$(git rev-parse "${1:-HEAD}^{commit}")
short=$(git rev-parse --short "$sha")

export DEVELOPER_DIR="/Applications/Xcode_$XCODE_VERSION.app/Contents/Developer"
if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Xcode $XCODE_VERSION isn't installed at /Applications/Xcode_$XCODE_VERSION.app." >&2
  exit 1
fi

if [ -n "$(git -C "$repo_root" status --porcelain)" ]; then
  echo "Note: you have uncommitted changes. Only the commit $short is validated."
fi

mkdir -p "$results_dir" "$logs_dir" "$work_dir"
log="$logs_dir/$sha.log"
: >"$log"

posted_pending=false
finished=false
udid=""
simulator_file="$state_dir/simulator"

delete_simulator() { # <udid>
  xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  xcrun simctl delete "$1" >/dev/null 2>&1 || true
  rm -f "$simulator_file"
}

on_exit() {
  if [ -n "$udid" ]; then
    delete_simulator "$udid"
  fi
  if ! $finished && $posted_pending; then
    post_status "$sha" error "Validation was interrupted" || true
  fi
}
trap on_exit EXIT

finish() { # <state> <description>
  printf '%s\t%s\n' "$1" "$2" >"$results_dir/$sha"
  finished=true
  if on_github "$sha"; then
    post_status "$sha" "$1" "$2"
    echo "Posted \"$CONTEXT: $1\" to $short on GitHub."
  else
    echo "$short isn't on GitHub yet; the pre-push hook will post the result when you push it."
  fi
  if [ "$1" = success ]; then
    exit 0
  fi
  exit 1
}

step() { # <name> <command...>
  local name="$1" started
  shift
  started=$(date +%s)
  printf '%s... ' "$name"
  echo "=== $name" >>"$log"
  if (cd "$worktree" && "$@") >>"$log" 2>&1; then
    echo "done ($(($(date +%s) - started))s)"
  else
    echo "FAILED"
    echo
    tail -n 40 "$log"
    echo
    echo "Full log: $log"
    finish failure "$name failed"
  fi
}

if on_github "$sha"; then
  post_status "$sha" pending "Validating..."
  posted_pending=true
fi

echo "Validating $short ($(git log -1 --format=%s "$sha"))"
validation_started=$(date +%s)

# A persistent worktree and DerivedData keep repeat runs incremental, like a
# CI cache; --clean starts both from scratch.
git -C "$repo_root" worktree prune
if [ ! -d "$worktree" ]; then
  git -C "$repo_root" worktree add --quiet --detach "$worktree" "$sha"
fi
git -C "$worktree" checkout --quiet --detach --force "$sha"
if $clean; then
  rm -rf "$derived_data"
  git -C "$worktree" clean -ffdxq
else
  git -C "$worktree" clean -ffdxq -e Vault/.build
fi

# A throwaway simulator for this run, deleted when it ends, so tests start from
# a clean state and never touch the one you develop with. It's addressed by
# UDID, since it shares its name with yours.
if [ -f "$simulator_file" ]; then
  delete_simulator "$(cat "$simulator_file")" # left behind by a killed run
fi
udid=$(xcrun simctl create "$SIMULATOR_NAME" "$SIMULATOR_TYPE" "$SIMULATOR_RUNTIME")
echo "$udid" >"$simulator_file"
destination="id=$udid"

step "Lint" make -C Vault lint

fastlane_note=""
# Shells that haven't run `rbenv init` (non-interactive ones, like an agent's)
# would otherwise find the system Ruby and skip this check.
if command -v rbenv >/dev/null; then
  PATH="$(rbenv root)/shims:$PATH"
fi
ruby_version=$(cat "$worktree/.ruby-version")
if [ "$(cd "$worktree" && ruby -e 'print RUBY_VERSION' 2>/dev/null)" = "$ruby_version" ]; then
  step "Fastlane config" /bin/bash -c \
    'bundle install --quiet && bundle exec ruby -c fastlane/Fastfile && bundle exec fastlane lanes'
else
  echo "Fastlane config... SKIPPED (Ruby $ruby_version from .ruby-version isn't installed)"
  fastlane_note="; Fastlane check skipped (no Ruby $ruby_version)"
fi

step "Build" xcodebuild build-for-testing \
  -workspace Vault.xcworkspace \
  -scheme CI_iOS \
  -testPlan iOSAllTests \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -skipMacroValidation \
  -skipPackagePluginValidation

xctestrun=$(ls -t "$derived_data"/Build/Products/*.xctestrun 2>/dev/null | head -1)
if [ -z "$xctestrun" ]; then
  echo "No .xctestrun file found in the build products."
  finish failure "Build produced no test run"
fi

# Skipping diagnostics collection keeps a failing run from hanging for up to
# 10 minutes while xcodebuild gathers them from the simulator.
step "Tests" xcodebuild test-without-building \
  -xctestrun "$xctestrun" \
  -destination "$destination" \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never

elapsed=$(($(date +%s) - validation_started))
finish success "Lint, build and all tests passed in $((elapsed / 60))m$((elapsed % 60))s$fastlane_note"
