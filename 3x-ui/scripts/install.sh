#!/usr/bin/env bash
# One-click 3x-ui install + restore preset DB (clients only need to change IP)
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/thm1472581-dotcom/public/master/3x-ui/scripts/install.sh)"

set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

OFFICIAL_INSTALL_URL="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh"
BACKUP_URL="https://raw.githubusercontent.com/thm1472581-dotcom/public/master/3x-ui/db/3x-ui-backup.tar.gz"

TMP_ARCHIVE="/tmp/3x-ui-backup.tar.gz"
TMP_DIR="/tmp/3x-ui"
DB_PATH="/etc/x-ui/x-ui.db"
OFFICIAL_INSTALL_TMP="/tmp/3x-ui-official-install.sh"

run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

info() { echo -e "${green}[INFO]${plain} $*"; }
warn() { echo -e "${yellow}[WARN]${plain} $*"; }
err()  { echo -e "${red}[ERROR]${plain} $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "missing command: $1"
    exit 1
  }
}

xui_ctl() {
  local action="$1"
  if command -v x-ui >/dev/null 2>&1; then
    run x-ui "${action}" && return 0
  fi
  if command -v xui >/dev/null 2>&1; then
    run xui "${action}" && return 0
  fi
  case "${action}" in
    stop)  run systemctl stop x-ui ;;
    start) run systemctl start x-ui ;;
    *)     return 1 ;;
  esac
}

need_cmd curl
need_cmd tar
if [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  err "run as root, or install sudo"
  exit 1
fi

echo "=========================================="
echo "  3x-ui install + DB restore"
echo "=========================================="

# 1) Install official 3x-ui (non-interactive; panel creds overwritten by backup DB)
info "Installing official 3x-ui ..."
curl -fsSL "${OFFICIAL_INSTALL_URL}" -o "${OFFICIAL_INSTALL_TMP}"
run env XUI_NONINTERACTIVE=1 bash "${OFFICIAL_INSTALL_TMP}"
run rm -f "${OFFICIAL_INSTALL_TMP}"

# 2) Stop service before replacing DB
info "Stopping x-ui ..."
xui_ctl stop || warn "failed to stop service, still trying to replace DB"

# 3) Download backup and extract to /tmp/3x-ui
info "Downloading DB backup ..."
curl -fsSL "${BACKUP_URL}" -o "${TMP_ARCHIVE}"
run rm -rf "${TMP_DIR}"
run mkdir -p "${TMP_DIR}"
info "Extracting to ${TMP_DIR} ..."
run tar -xzf "${TMP_ARCHIVE}" -C "${TMP_DIR}"

if [[ ! -f "${TMP_DIR}/x-ui.db" ]]; then
  err "${TMP_DIR}/x-ui.db not found after extract; check backup archive"
  exit 1
fi

# 4) Remove old DB then copy new one
info "Replacing database ${DB_PATH} ..."
run mkdir -p /etc/x-ui
run rm -f "${DB_PATH}"
run cp "${TMP_DIR}/x-ui.db" "${DB_PATH}"
run chmod 644 "${DB_PATH}"

# 5) Cleanup
info "Cleaning temp files ..."
run rm -rf "${TMP_ARCHIVE}" "${TMP_DIR}"

# 6) Start service
info "Starting x-ui ..."
xui_ctl start

echo "=========================================="
echo -e "${green}Done.${plain} Point clients to this server IP."
echo "Panel: use port/user from the backup DB (x-ui settings)"
echo "=========================================="
