# Talky: common dev tasks.
#
#   make run       Build build/Talky.app and launch it
#   make build     Build build/Talky.app
#   make test      Run the unit tests
#   make install   Build, copy to /Applications and launch (scripts/install.sh)
#   make dry-run   Build, sign and notarize a release into dist/web-preview; publish nothing
#
# A real release goes through /release (.claude/skills/release), which runs scripts/release.sh.

APP := build/Talky.app

.PHONY: run build test install dry-run

run: build
	pkill -x Talky || true
	open "$(APP)"

build:
	scripts/build-app.sh

test:
	swift test

install:
	scripts/install.sh

dry-run:
	scripts/release.sh --dry-run
