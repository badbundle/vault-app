SHELL = /bin/sh

.PHONY: benchmark-keygen
benchmark-keygen:
	swift run -c release vault-keygen-speedtest

.PHONY: format
format:
	swift package plugin --allow-writing-to-package-directory swiftlint --fix --quiet ./Sources
	swift package --allow-writing-to-package-directory format --sources=./

.PHONY: lint
lint:
	swift package plugin --allow-writing-to-package-directory swiftlint --strict --quiet ./Sources
	swift package --allow-writing-to-package-directory format --lint --sources=./

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
