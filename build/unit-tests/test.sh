#!/bin/bash

set -eux
set -o pipefail

if ! rpm -q systemd-tests; then
    echo >&2 "Missing package 'systemd-tests'"
    exit 1
fi

/usr/lib/systemd/tests/run-unit-tests.py --unsafe
