#!/usr/bin/env bash
set -euo pipefail
#
# Resolves the latest available version for each DNF package in the Containerfile
# and prints an updated DNF_PACKAGES block you can paste in.
#
# Usage: Run inside the container (or any Fedora system matching the base image):
#   bash scripts/update-dnf-versions.sh
#

PACKAGES=(
  curl
  dnf5
  dnf5-plugins
  eza
  findutils
  fzf
  gettext-envsubst
  gh
  git
  gnutls
  jq
  libdnf5
  libdnf5-cli
  libssh
  libtasn1
  nodejs
  podman
  procps-ng
  python3
  python3-pip
  sudo
  systemd-standalone-sysusers
  tar
  tox
  unzip
  uv
  vim-enhanced
  zoxide
  zsh
)

# shellcheck disable=SC1003
echo 'ARG DNF_PACKAGES="\'
for pkg in "${PACKAGES[@]}"; do
  resolved=$(dnf repoquery --latest-limit=1 --qf '%{name}-%{epoch}:%{version}-%{release}' "$pkg" 2>/dev/null | head -1)
  # Strip "0:" epoch prefix (dnf convention for epoch=0)
  resolved="${resolved//-0:/-}"
  if [ -z "$resolved" ]; then
    echo "    # WARNING: could not resolve $pkg" >&2
    echo "    $pkg \\"
  else
    echo "    ${resolved} \\"
  fi
done
echo '"'
echo ""
echo "# Paste the above block into the Containerfile, replacing the existing DNF_PACKAGES ARG."
