#!/bin/bash

set -eux
set -o pipefail

WORKDIR="$(mktemp -d)"
pushd "$WORKDIR"

# Workaround for https://gitlab.com/testing-farm/oculus/-/issues/19
# shellcheck disable=SC2064
trap "chmod -R o+rX $TMT_TEST_DATA" EXIT

# Switch SELinux to permissive, since the tests don't set proper contexts
setenforce 0

# Prepare systemd source tree
if [[ -n "${PACKIT_TARGET_URL:-}" ]]; then
    # Install systemd's build dependencies, as some of the integration tests setup stuff
    # requires pkg-config files
    dnf builddep --allowerasing -y systemd
    git clone "$PACKIT_TARGET_URL" systemd
    cd systemd
    git checkout "$PACKIT_TARGET_BRANCH"
    # If we're running in a pull request job, merge the remote branch into the current main
    if [[ -n "${PACKIT_SOURCE_URL:-}" ]]; then
        git remote add pr "${PACKIT_SOURCE_URL:?}"
        git fetch pr "${PACKIT_SOURCE_BRANCH:?}"
        git merge "pr/$PACKIT_SOURCE_BRANCH"
    fi
    git log --oneline -5
else
    # If we're running outside of Packit, download SRPM for the currently installed build
    if ! dnf download --source "$(rpm -q systemd)"; then
        # If the build is recent enough it might not be on the mirrors yet, so try koji as well
        koji download-build --arch=src "$(rpm -q systemd --qf "%{sourcerpm}")"
    fi
    dnf builddep --allowerasing -y ./systemd-*.src.rpm
    rpmbuild --nodeps --define="_topdir $PWD" -rp ./systemd-*.src.rpm
    # Little hack to get to the correct directory without having to figure out
    # the exact name
    cd BUILD/*/test/../

    # NO_BUILD=1 support for Fedora was introduced in v255
    if ! grep -q "LOOKS_LIKE_FEDORA" test/test-functions; then
        # Try to apply necessary patches before giving up completely
        if ! curl -Ls https://github.com/systemd/systemd/commit/b54bc139ae91b417996ddc85585710ebf3324237.patch | git apply ||
           ! curl -Ls https://github.com/systemd/systemd/commit/8ddbd9e07811e434fb24bc0d04812aae24fa78be.patch | git apply; then
            echo "Source tree doesn't support NO_BUILD=1 on Fedora, skipping the tests"
            exit 0
        fi
    fi
fi

# Temporarily build custom initrd with libkmod installed explicitly, as it became
# a dlopen() dep
# See: https://github.com/systemd/systemd/pull/31131
export INITRD="$(mktemp /var/tmp/ci-XXX.initrd)"
cp -fv "/boot/initramfs-$(uname -r).img" "$INITRD"
dracut -f -v -a crypt --install /usr/lib64/libkmod.so.2 --rebuild "$INITRD"

# Work around https://github.com/util-linux/util-linux/issues/2824
if grep -q "losetup --find" /usr/lib/systemd/tests/testdata/units/testsuite-72.sh; then
    patch /usr/lib/systemd/tests/testdata/units/testsuite-72.sh <<\EOF
diff --git a/test/units/testsuite-72.sh b/test/units/testsuite-72.sh
index 953f2a16bf..312a53def1 100755
--- a/test/units/testsuite-72.sh
+++ b/test/units/testsuite-72.sh
@@ -22,7 +22,7 @@ fi
 # change the sector size of a file, and we want to test both 512 and 4096 byte
 # sectors. If loopback devices are not supported, we can only test one sector
 # size, and the underlying device is likely to have a sector size of 512 bytes.
-if ! losetup --find >/dev/null 2>&1; then
+if [[ ! -e /dev/loop-control ]] then
     echo "No loopback device support"
     SECTOR_SIZES="512"
 fi
@@ -108,7 +108,7 @@ for sector_size in $SECTOR_SIZES ; do
     rm -f "$BACKING_FILE"
     truncate -s "$disk_size" "$BACKING_FILE"
 
-    if losetup --find >/dev/null 2>&1; then
+    if [[ -e /dev/loop-control ]]; then
         # shellcheck disable=SC2086
         blockdev="$(losetup --find --show --sector-size $sector_size $BACKING_FILE)"
     else
EOF
fi

export DENY_LIST_MARKERS=fedora-skip
# Skip TEST-64-UDEV-STORAGE for now, as it takes a really long time without KVM
touch test/TEST-64-UDEV-STORAGE/fedora-skip

export ARTIFACT_DIRECTORY="${TMT_TEST_DATA:?}"
export SPLIT_TEST_LOGS=1
export TEST_SAVE_JOURNAL=fail
export TEST_SHOW_JOURNAL=warning
export TEST_REQUIRE_INSTALL_TESTS=0
export TEST_PREFER_NSPAWN=1
export TEST_NESTED_KVM=1
export NO_BUILD=1
export QEMU_TIMEOUT=1800
export NSPAWN_TIMEOUT=1200

test/run-integration-tests.sh

popd
rm -rf "$WORKDIR"
