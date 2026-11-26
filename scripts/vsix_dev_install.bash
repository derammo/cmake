#!/usr/bin/env bash
# install the given VSIX into vscode under a unique timestamped version, so
# vscode treats every install as an update even when the version is unchanged;
# run from the extension directory holding the VSIX
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: vsix_dev_install.bash <vsix-file>" >&2
    exit 2
fi
VSIX_FILE="$1"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vsix_dev.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT
STAMPED="${STAGE_DIR}/$(basename "${VSIX_FILE}" .vsix).$(date +%s).vsix"
cp "${VSIX_FILE}" "${STAMPED}"

# installing a VSIX makes vscode query the Marketplace for the extension id;
# routing the CLI through an unreachable proxy keeps private extension ids
# from leaving the machine
HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
    code --install-extension "${STAMPED}" --force
