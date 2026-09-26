SHELL = /bin/sh

.PHONY: benchmark-keygen
benchmark-keygen:
	swift run -c release vault-keygen-speedtest

# Calibrates the app lock key derivation (Argon2id) for this machine, as the
# app does on the device when it creates an encrypted vault.
.PHONY: calibrate-app-lock
calibrate-app-lock:
	swift run -c release vault-keygen-speedtest --app-lock

# App icon: renders Sources/VaultAppIcon into the app's asset catalog as the
# light, dark and tinted 1024px PNGs plus Contents.json. Commit the output.
.PHONY: app-icon
app-icon:
	swift run -c release vault-app-icon-generator

.PHONY: format
format:
	swift package plugin --allow-writing-to-package-directory swiftlint --fix --quiet ./Sources
	swift package --allow-writing-to-package-directory format --sources=./

.PHONY: lint
lint:
	swift package plugin --allow-writing-to-package-directory swiftlint --strict --quiet ./Sources
	swift package --allow-writing-to-package-directory format --lint --sources=./

# Validation: runs the checks in ../local-check.config.ts on the current commit,
# in a clean worktree, then posts the green "Validate (local)" check to GitHub.
# Installing first keeps local-check at the version package.json pins.
# See ../README.md#validation.
.PHONY: validate
validate:
	cd .. && bun install --frozen-lockfile --silent && bun run --silent validate

# Marketing screenshots: capture raw shots of the app on throwaway simulators,
# then put them in device frames with titles. See Screenshots/README.md.
.PHONY: screenshots
screenshots: screenshots-capture screenshots-frame

.PHONY: screenshots-capture
screenshots-capture:
	Screenshots/capture.sh

.PHONY: screenshots-frame
screenshots-frame:
	swift run -c release framer render --config Screenshots/iphone.json
	swift run -c release framer render --config Screenshots/ipad.json

.PHONY: clean
clean:
	swift package clean
	rm -rf .build
