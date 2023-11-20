#!/bin/bash

set -eux
set -o pipefail

# Prepare systemd source tree
#
# Note: the snippet below assumes that the target PR branch is always 'main'
#
# Relevant docs:
#   - https://packit.dev/docs/configuration/upstream/tests#optional-parameters
git clone "${PACKIT_TARGET_URL:-https://github.com/systemd/systemd}" systemd
cd systemd
# If we're running in a pull request job, merge the remote branch into the current main
if [[ -n "${PACKIT_SOURCE_URL:-}" ]]; then
    git remote add pr "${PACKIT_SOURCE_URL:?}"
    git fetch pr "${PACKIT_SOURCE_BRANCH:?}"
    git merge "pr/$PACKIT_SOURCE_BRANCH"
fi
git log -1

export ARTIFACT_DIRECTORY="${TMT_TEST_DATA:?}"
export TEST_SAVE_JOURNAL=fail
export TEST_SHOW_JOURNAL=warning
export TEST_REQUIRE_INSTALL_TESTS=0
export TEST_PREFER_NSPAWN=1
export NO_BUILD=1
export QEMU_TIMEOUT=1800
export NSPAWN_TIMEOUT=1200
# FIXME
export TEST_NO_QEMU=1

test/run-integration-tests.sh
