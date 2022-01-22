#!/bin/sh

set -ex

origdir="$(pwd -P)"
srcdir="$(dirname "$0")"
test -z "$srcdir" && srcdir=.

cd "$srcdir"
# Generate install-sh.
automake --add-missing --copy || true
autoconf

if test -z "$NOCONFIGURE"; then
    cd "$origdir"
    exec "$srcdir"/configure "$@"
fi
