#!/bin/sh
# Container side, runs as root: recreate what a fresh VM looks like (an
# unprivileged user with sudo and a distro-default .bashrc), then hand over to
# assert.sh as that user.
set -eu

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq sudo
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q sudo
else
    echo "error: unsupported distro for this test" >&2
    exit 2
fi

useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/tester
chmod 0440 /etc/sudoers.d/tester

cp -R /src /home/tester/dotfiles
chown -R tester:tester /home/tester/dotfiles

exec su tester -c 'sh /home/tester/dotfiles/tests/assert.sh'
