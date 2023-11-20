#!/bin/bash

set -eux
set -o pipefail

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
