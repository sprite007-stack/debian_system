#!/usr/bin/env bash
set -u
set -o pipefail

###############################################################################
# LMDE / Ubuntu Interactive Workstation Setup Script
# - Supports LMDE 6/7 and Ubuntu
# - Live progress for package operations
# - Automatic dpkg recovery
# - APT IPv4 fallback
# - Persistent colored menu status
# - Corrected package install handling
# - Corrected Docker repo setup handling
# - Vendor apps + Flatpak apps
# - Fonts, Nemo, Zsh, desktop prefs
# - WinBoat prerequisites + install
# - Validation report
# - VS Code setup and GitHub integration
###############################################################################

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${HOME}/workstation_setup.log"
REPORT_FILE="${HOME}/workstation_setup_report.txt"
FAILED_FILE="${HOME}/workstation_failed_items.txt"
STATUS_FILE="${HOME}/.workstation_setup_status"
DOWNLOAD_DIR="${HOME}/Downloads"
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  STARTING_USER="$SUDO_USER"
elif logname >/dev/null 2>&1 && [[ "$(logname 2>/dev/null)" != "root" ]]; then
  STARTING_USER="$(logname 2>/dev/null)"
else
  STARTING_USER="$USER"
fi

STARTING_HOME="$(getent passwd "$STARTING_USER" | cut -d: -f6 2>/dev/null)"
STARTING_HOME="${STARTING_HOME:-$HOME}"

if [[ "$STARTING_USER" == "root" ]]; then
  printf "${YELLOW}[WARN]${NC} Desktop app and user-settings sections are running with STARTING_USER=root.\n"
  printf "${YELLOW}[WARN]${NC} For desktop apps and per-user settings, launch this script with sudo from your normal user session.\n"
fi

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Globals ----------
OS_PRETTY_NAME=""
OS_ID=""
OS_NAME=""
OS_VERSION_ID=""
OS_VERSION_CODENAME=""
DEBIAN_CODENAME=""
APT_CODENAME=""
DOCKER_DISTRO=""
ARCH=""
PKG_MGR="apt-get"
IS_LMDE=false
IS_UBUNTU=false
IS_SUPPORTED_OS=false
JAVA_PKG="default-jre"

declare -A SECTION_STATUS

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
: > "$FAILED_FILE"

# ---------- Logging ----------
log() {
  local level="$1"
  shift
  local msg="$*"
  printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$msg" | tee -a "$LOG_FILE" >/dev/null
}

info()    { log "INFO" "$*";  printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
success() { log "OK" "$*";    printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn()    { log "WARN" "$*";  printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error()   { log "ERROR" "$*"; printf "${RED}[ERROR]${NC} %s\n" "$*"; }

record_failure() {
  local item="$1"
  echo "$item" >> "$FAILED_FILE"
}

# ---------- Section Status ----------
init_section_status() {
  local i
  for i in {0..22}; do
    SECTION_STATUS[$i]="pending"
  done
}

load_section_status() {
  if [[ -f "$STATUS_FILE" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[0-9]+$ ]] || continue
      SECTION_STATUS["$key"]="$value"
    done < "$STATUS_FILE"
  fi
}

save_section_status() {
  : > "$STATUS_FILE"
  local i
  for i in {0..22}; do
    echo "${i}=${SECTION_STATUS[$i]:-pending}" >> "$STATUS_FILE"
  done
}

format_menu_item() {
  local number="$1"
  local label="$2"
  local status="${SECTION_STATUS[$number]:-pending}"

  case "$status" in
    complete)
      printf "${GREEN}%3s) %s${NC}\n" "$number" "$label"
      ;;
    failed)
      printf "${RED}%3s) %s${NC}\n" "$number" "$label"
      ;;
    running)
      printf "${YELLOW}%3s) %s${NC}\n" "$number" "$label"
      ;;
    *)
      printf "%3s) %s\n" "$number" "$label"
      ;;
  esac
}

run_section() {
  local section_number="$1"
  local function_name="$2"

  SECTION_STATUS["$section_number"]="running"
  save_section_status

  if "$function_name"; then
    SECTION_STATUS["$section_number"]="complete"
  else
    SECTION_STATUS["$section_number"]="failed"
  fi

  save_section_status
}

# ---------- Core Helpers ----------
require_sudo() {
  if ! sudo -v; then
    error "Sudo authentication failed."
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
  mkdir -p "$1"
}

run_as_user() {
  local uid
  uid="$(id -u "$STARTING_USER")"
  sudo -u "$STARTING_USER" \
    env \
      HOME="$STARTING_HOME" \
      USER="$STARTING_USER" \
      LOGNAME="$STARTING_USER" \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    "$@"
}

run_as_user_shell() {
  local uid
  uid="$(id -u "$STARTING_USER")"
  sudo -u "$STARTING_USER" \
    env \
      HOME="$STARTING_HOME" \
      USER="$STARTING_USER" \
      LOGNAME="$STARTING_USER" \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    bash -lc "$*"
}

press_enter() {
  read -r -p "Press Enter to continue..."
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer

  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "$prompt [y/N]: " answer
    answer="${answer:-N}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

show_section_header() {
  echo
  printf "${BOLD}${CYAN}============================================================${NC}\n"
  printf "${BOLD}${CYAN}%s${NC}\n" "$1"
  printf "${BOLD}${CYAN}============================================================${NC}\n"
}

run_cmd() {
  local desc="$1"
  shift
  info "$desc"
  if "$@" >>"$LOG_FILE" 2>&1; then
    success "$desc"
    return 0
  else
    error "$desc"
    return 1
  fi
}

sudo_run() {
  local desc="$1"
  shift
  info "$desc"
  if sudo "$@" >>"$LOG_FILE" 2>&1; then
    success "$desc"
    return 0
  else
    error "$desc"
    return 1
  fi
}

run_cmd_live() {
  local desc="$1"
  shift

  info "$desc"
  echo "------------------------------------------------------------"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo "------------------------------------------------------------"
    success "$desc"
    return 0
  else
    echo "------------------------------------------------------------"
    error "$desc"
    return 1
  fi
}

sudo_run_live() {
  local desc="$1"
  shift

  case "$1" in
    apt|apt-get|nala|dpkg)
      wait_for_apt_lock || return 1
      ;;
  esac

  info "$desc"
  echo "------------------------------------------------------------"
  if sudo "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo "------------------------------------------------------------"
    success "$desc"
    return 0
  else
    echo "------------------------------------------------------------"
    error "$desc"
    return 1
  fi
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

wait_for_apt_lock() {
  local timeout="${1:-600}"
  local waited=0
  local lock_pids=""

  info "Checking for active apt/dpkg locks..."

  while true; do
    lock_pids="$(sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null | xargs -r echo)"

    if [[ -z "$lock_pids" ]]; then
      success "No active apt/dpkg lock detected."
      return 0
    fi

    warn "apt/dpkg lock in use by PID(s): $lock_pids - waiting..."
    sleep 5
    waited=$((waited + 5))

    if (( waited >= timeout )); then
      error "Timed out waiting for apt/dpkg lock after ${timeout} seconds."
      return 1
    fi
  done
}

fix_user_file_ownership() {
  local file="$1"
  if [[ -e "$file" ]]; then
    sudo chown "$STARTING_USER:$STARTING_USER" "$file" >>"$LOG_FILE" 2>&1 || true
  fi
}

append_if_missing() {
  local file="$1"
  local line="$2"
  touch "$file"
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
  fix_user_file_ownership "$file"
}

replace_or_append() {
  local file="$1"
  local regex="$2"
  local newline="$3"

  touch "$file"
  if grep -Eq "$regex" "$file"; then
    sed -i -E "s|$regex|$newline|" "$file"
  else
    echo "$newline" >> "$file"
  fi
  fix_user_file_ownership "$file"
}

clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "$target_dir/.git" ]]; then
    run_as_user git -C "$target_dir" pull --ff-only >>"$LOG_FILE" 2>&1 \
      && success "Updated $(basename "$target_dir")" \
      || warn "Could not update $(basename "$target_dir")"
  else
    run_as_user git clone --depth 1 "$repo_url" "$target_dir" >>"$LOG_FILE" 2>&1 \
      && success "Cloned $(basename "$target_dir")" \
      || warn "Could not clone $(basename "$target_dir")"
  fi
}

# ---------- OS Detection ----------
detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "/etc/os-release not found."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  OS_PRETTY_NAME="${PRETTY_NAME:-unknown}"
  OS_ID="${ID:-unknown}"
  OS_NAME="${NAME:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
  DEBIAN_CODENAME="${DEBIAN_CODENAME:-}"
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  IS_LMDE=false
  IS_UBUNTU=false
  IS_SUPPORTED_OS=false
  JAVA_PKG="default-jre"

  if [[ "$OS_ID" == "linuxmint" ]] && [[ "$OS_NAME" == "LMDE" ]]; then
    IS_LMDE=true
  fi

  if [[ "$OS_ID" == "ubuntu" ]]; then
    IS_UBUNTU=true
  fi

  if $IS_LMDE; then
    IS_SUPPORTED_OS=true
    DOCKER_DISTRO="debian"
    APT_CODENAME="${DEBIAN_CODENAME:-bookworm}"

    case "$APT_CODENAME" in
      bookworm) JAVA_PKG="openjdk-17-jre" ;;
      trixie)   JAVA_PKG="openjdk-21-jre" ;;
      *)        JAVA_PKG="default-jre" ;;
    esac
  elif $IS_UBUNTU; then
    IS_SUPPORTED_OS=true
    DOCKER_DISTRO="ubuntu"
    APT_CODENAME="${OS_VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    JAVA_PKG="default-jre"
  else
    DOCKER_DISTRO="debian"
    APT_CODENAME="${DEBIAN_CODENAME:-${OS_VERSION_CODENAME:-bookworm}}"
    JAVA_PKG="default-jre"
  fi

  if command_exists nala; then
    PKG_MGR="nala"
  else
    PKG_MGR="apt-get"
  fi
}

print_detected_environment() {
  info "Detected OS           : $OS_PRETTY_NAME"
  info "Detected architecture : $ARCH"
  info "LMDE                  : $IS_LMDE"
  info "Ubuntu                : $IS_UBUNTU"
  info "Supported OS          : $IS_SUPPORTED_OS"
  info "APT codename          : $APT_CODENAME"
  info "Docker distro         : $DOCKER_DISTRO"
  info "Java package          : $JAVA_PKG"
  info "Preferred package mgr : $PKG_MGR"
}

# ---------- Package Manager Wrappers ----------
pkg_update() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo nala update 2>&1 | tee -a "$LOG_FILE"
  else
    sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_upgrade_full() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo nala upgrade -y 2>&1 | tee -a "$LOG_FILE"
  else
    sudo apt-get -y full-upgrade 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_install() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo nala install -y "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    sudo apt-get install -y "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_fix_broken() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo nala install -f -y 2>&1 | tee -a "$LOG_FILE" || true
    wait_for_apt_lock || return 1
    sudo nala --fix-broken install -y 2>&1 | tee -a "$LOG_FILE" || true
  else
    sudo apt-get install -f -y 2>&1 | tee -a "$LOG_FILE" || true
  fi
}


# ---------- GSettings Helpers ----------
gsettings_key_exists() {
  local schema="$1"
  local key="$2"
  run_as_user gsettings list-keys "$schema" 2>/dev/null | grep -Fxq "$key"
}

gsettings_key_writable() {
  local schema="$1"
  local key="$2"
  run_as_user gsettings writable "$schema" "$key" 2>/dev/null | grep -Fxq true
}

set_gsetting_if_supported() {
  local schema="$1"
  local key="$2"
  local value="$3"

  if ! gsettings_key_exists "$schema" "$key"; then
    info "Skipping unsupported gsettings key: $schema::$key"
    return 0
  fi

  if ! gsettings_key_writable "$schema" "$key"; then
    info "Skipping non-writable gsettings key: $schema::$key"
    return 0
  fi

  if run_as_user gsettings set "$schema" "$key" "$value" >>"$LOG_FILE" 2>&1; then
    success "Set $schema::$key to $value"
  else
    warn "Could not set $schema::$key"
  fi
}

get_gsetting_if_available() {
  local schema="$1"
  local key="$2"

  if gsettings_key_exists "$schema" "$key"; then
    run_as_user gsettings get "$schema" "$key" 2>/dev/null || echo "<read-failed>"
  else
    echo "<unavailable>"
  fi
}

# ---------- Repo Validation ----------
find_broken_docker_repo_entries() {
  grep -RniE 'download\.docker\.com/linux/ubuntu.*(faye|vanessa|vera|virginia|wilma|xia)|download\.docker\.com/linux/ubuntu[[:space:]]+faye|download\.docker\.com/linux/debian[[:space:]]+(jammy|noble|focal|oracular)' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
}

validate_repo_files() {
  show_section_header "Repo Validation"

  local broken
  broken="$(find_broken_docker_repo_entries)"

  if [[ -n "$broken" ]]; then
    warn "Potentially incorrect Docker repo entries were found:"
    echo "$broken"
  else
    success "No obviously incorrect Docker repo entries detected."
  fi

  if sudo apt-get update >>"$LOG_FILE" 2>&1; then
    success "apt repository metadata refresh succeeded."
  else
    warn "apt update reported errors. Review $LOG_FILE for details."
  fi
}

# ---------- Vendor Repo Helpers ----------
setup_1password_repo() {
  local repo_file="/etc/apt/sources.list.d/1password.list"
  local key_file="/usr/share/keyrings/1password-archive-keyring.gpg"

  if [[ -f "$repo_file" ]] && [[ -f "$key_file" ]]; then
    success "1Password repository already configured"
    return 0
  fi

  sudo install -m 0755 -d /usr/share/keyrings >>"$LOG_FILE" 2>&1 || true

  if sudo bash -c 'curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --yes -o /usr/share/keyrings/1password-archive-keyring.gpg' >>"$LOG_FILE" 2>&1; then
    success "Installed 1Password signing key"
  else
    error "Failed to install 1Password signing key"
    record_failure "1password-repo"
    return 1
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
    sudo tee "$repo_file" >/dev/null

  if pkg_update; then
    success "1Password repository configured"
  else
    warn "1Password repository configured, but package refresh reported errors"
  fi
}

install_brave_official() {
  if command_exists brave-browser || pkg_installed brave-browser; then
    success "Brave Browser is already installed"
    return 0
  fi

  info "Installing Brave Browser using Brave's official Linux installer..."
  if curl -fsS https://dl.brave.com/install.sh | sudo bash >>"$LOG_FILE" 2>&1; then
    success "Brave Browser installed"
    return 0
  else
    error "Failed to install Brave Browser"
    record_failure "brave-browser"
    return 1
  fi
}

# ---------- Flatpak Helpers ----------
ensure_flatpak_flathub() {
  if ! command_exists flatpak && ! pkg_installed flatpak; then
    info "Installing flatpak..."
    if pkg_install flatpak; then
      success "Installed flatpak"
    else
      error "Failed to install flatpak"
      record_failure "flatpak"
      return 1
    fi
  fi

  if ! sudo flatpak remote-list --system --columns=name 2>/dev/null | grep -Fxq flathub; then
    info "Adding Flathub system remote..."
    if sudo flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >>"$LOG_FILE" 2>&1; then
      success "Added Flathub remote"
    else
      error "Failed to add Flathub remote"
      record_failure "flathub-remote"
      return 1
    fi
  else
    success "Flathub remote already configured"
  fi
}

flatpak_app_installed() {
  local app_id="$1"
  sudo flatpak info --system "$app_id" >/dev/null 2>&1
}

install_flatpak_app() {
  local app_id="$1"
  local label="$2"

  if flatpak_app_installed "$app_id"; then
    success "Already installed (Flatpak): $label"
    return 0
  fi

  info "Installing Flatpak app: $label"
  if sudo flatpak install --system -y flathub "$app_id" >>"$LOG_FILE" 2>&1; then
    success "Installed (Flatpak): $label"
    return 0
  else
    error "Failed to install (Flatpak): $label"
    record_failure "$app_id"
    return 1
  fi
}

# ---------- Nemo Helpers ----------
nemo_available() {
  command_exists nemo || pkg_installed nemo
}

# ---------- WinBoat Helpers ----------
user_in_group() {
  local user="$1"
  local group="$2"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$group"
}

kvm_available() {
  [[ -e /dev/kvm ]]
}

install_latest_winboat_deb() {
  local api_url="https://api.github.com/repos/TibixDev/winboat/releases/latest"
  local tmp_json="/tmp/winboat_latest_release.json"
  local deb_url=""
  local deb_file=""

  info "Fetching latest WinBoat release metadata..."
  if ! curl -fsSL "$api_url" -o "$tmp_json" >>"$LOG_FILE" 2>&1; then
    error "Failed to query latest WinBoat release metadata"
    record_failure "winboat-release-metadata"
    return 1
  fi

  deb_url="$(grep -oE 'https://[^"]+winboat[-_][^"]+amd64\.deb' "$tmp_json" | head -n1)"

  if [[ -z "$deb_url" ]]; then
    error "Could not find a WinBoat amd64 .deb asset in the latest release metadata"
    record_failure "winboat-deb-url"
    return 1
  fi

  deb_file="${DOWNLOAD_DIR}/$(basename "$deb_url")"
  ensure_dir "$DOWNLOAD_DIR"

  info "Downloading WinBoat package..."
  if ! wget -O "$deb_file" "$deb_url" >>"$LOG_FILE" 2>&1; then
    error "Failed to download WinBoat package"
    record_failure "winboat-download"
    return 1
  fi

  if [[ ! -s "$deb_file" ]]; then
    error "Downloaded WinBoat package is missing or empty"
    record_failure "winboat-download-empty"
    return 1
  fi

  info "Installing WinBoat package..."
  if sudo dpkg -i "$deb_file" >>"$LOG_FILE" 2>&1; then
    success "Installed WinBoat package"
  else
    warn "dpkg reported dependency issues, attempting repair..."
    pkg_fix_broken
    if sudo dpkg -i "$deb_file" >>"$LOG_FILE" 2>&1; then
      success "Installed WinBoat package after dependency repair"
    else
      warn "WinBoat package install may require manual review"
      record_failure "winboat-install"
      return 1
    fi
  fi

  return 0
}

# ---------- Section 0 ----------
section_0_preflight() {
  show_section_header "Section 0 - Pre-Flight Checks"

  detect_os
  print_detected_environment

  local required_cmds=(sudo apt-get dpkg grep sed awk tee curl wget)
  local missing=()

  for cmd in "${required_cmds[@]}"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} > 0)); then
    error "Missing required commands: ${missing[*]}"
    return 1
  fi
  success "Required base commands are present."

  if ping -c 1 -W 2 1.1.1.1 >>"$LOG_FILE" 2>&1 || curl -I --max-time 5 https://deb.debian.org >>"$LOG_FILE" 2>&1; then
    success "Basic network connectivity looks good."
  else
    warn "Network connectivity test failed. Online install sections may fail."
  fi

  local free_mb
  free_mb="$(df -Pm "$HOME" | awk 'NR==2 {print $4}')"
  if [[ "${free_mb:-0}" -lt 4096 ]]; then
    warn "Less than 4 GB free in home filesystem. Large app installs may fail."
  else
    success "Disk space check passed (${free_mb} MB free)."
  fi

  ensure_dir "$DOWNLOAD_DIR"
  success "Download directory ready: $DOWNLOAD_DIR"

  validate_repo_files

  if pkg_installed default-jre || pkg_installed openjdk-17-jre || pkg_installed openjdk-21-jre; then
    success "A Java runtime is already installed."
  else
    warn "No Java runtime currently detected."
  fi

  if $IS_SUPPORTED_OS; then
    success "OS support check passed."
  else
    warn "This script is optimized for LMDE 6/7 and Ubuntu. Some steps may need manual adjustment."
  fi
}

# ---------- Section 1 ----------
section_1_system_update() {
  show_section_header "Section 1 - System Update & Upgrade"

  sudo_run "Allow apt release info version changes" bash -c     'echo '''Acquire::AllowReleaseInfoChange "true";''' > /etc/apt/apt.conf.d/99releaseinfo' || return 1

  info "Recovering package manager state if needed..."
  wait_for_apt_lock || return 1
  sudo dpkg --configure -a >>"$LOG_FILE" 2>&1 || true

  wait_for_apt_lock || return 1
  sudo apt-get --fix-broken install -y >>"$LOG_FILE" 2>&1 || true

  info "Forcing APT to use IPv4 for better repo reliability..."
  echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 >/dev/null

  sudo_run_live "Update apt package lists (allow release info version change)"     apt-get update -o Acquire::AllowReleaseInfoChange::Version=true || return 1

  sudo_run_live "Run apt full-upgrade" apt-get -y full-upgrade || return 1

  if ! command_exists nala; then
    sudo_run_live "Install nala" apt-get install -y nala || return 1
  else
    success "nala is already installed"
  fi

  if command_exists nala; then
    sudo_run_live "Update package lists with nala" nala update || return 1
    sudo_run_live "Upgrade packages with nala" nala upgrade -y || return 1
  else
    sudo_run_live "Update package lists with apt-get" apt-get update || return 1
    sudo_run_live "Upgrade packages with apt-get" apt-get -y full-upgrade || return 1
  fi
}


# ---------- Section 2 ----------
section_2_core_and_vendor_apps() {
  show_section_header "Section 2 - Core Packages and Vendor Apps"

  detect_os

  local apt_packages=(
    autofs
    curl
    ffmpeg
    ffmpegthumbnailer
    filezilla
    fonts-font-awesome
    fonts-noto-color-emoji
    gimp
    git
    gnome-font-viewer
    gnome-tweaks
    gufw
    htop
    btop
    ncdu
    neovim
    nfs-common
    "$JAVA_PKG"
    p7zip-full
    remmina
    remmina-plugin-rdp
    ripgrep
    shellcheck
    tmux
    tree
    xdotool
    zsh
    unzip
    ufw
    dconf-cli
    dbus-x11
    ca-certificates
    gnupg
    xdg-utils
    flatpak
    timeshift
    okular
    pdfarranger
  )

  local optional_packages=(
    numix-icon-theme
    preload
    tealdeer
    tlp
    tlp-rdw
    transmission
    fd-find
    bat
    vlc
    unrar
    kodi
    notepadqq
    zsh-autosuggestions
    zsh-syntax-highlighting
  )

  local installed_now=()
  local skipped=()
  local failed=()
  local optional_failed=()

  if pkg_update; then
    success "Package lists refreshed."
  else
    warn "Package update returned errors; some installs may fail."
  fi

  setup_1password_repo || true

  local pkg

  info "Installing core packages..."
  for pkg in "${apt_packages[@]}"; do
    if pkg_installed "$pkg"; then
      success "Already installed: $pkg"
      skipped+=("$pkg")
      continue
    fi

    info "Installing package: $pkg"
    if pkg_install "$pkg"; then
      success "Installed: $pkg"
      installed_now+=("$pkg")
    else
      warn "Failed to install: $pkg"
      failed+=("$pkg")
      record_failure "$pkg"
    fi
  done

  info "Installing optional packages..."
  for pkg in "${optional_packages[@]}"; do
    if pkg_installed "$pkg"; then
      success "Already installed: $pkg"
      skipped+=("$pkg")
      continue
    fi

    info "Installing optional package: $pkg"
    if pkg_install "$pkg"; then
      success "Installed: $pkg"
      installed_now+=("$pkg")
    else
      warn "Optional package not installed: $pkg"
      optional_failed+=("$pkg")
      record_failure "$pkg"
    fi
  done

  if command_exists systemctl && pkg_installed tlp; then
    sudo systemctl enable --now tlp >>"$LOG_FILE" 2>&1 || true
  fi

  if pkg_installed 1password; then
    success "Already installed: 1password"
    skipped+=("1password")
  else
    info "Installing package: 1password"
    if pkg_install 1password; then
      success "Installed: 1password"
      installed_now+=("1password")
    else
      warn "Failed to install 1password"
      failed+=("1password")
      record_failure "1password"
    fi
  fi

  if install_brave_official; then
    installed_now+=("brave-browser")
  else
    failed+=("brave-browser")
  fi

  echo
  info "Section 2 summary:"
  echo "  Installed now     : ${#installed_now[@]}"
  echo "  Already there     : ${#skipped[@]}"
  echo "  Core failed       : ${#failed[@]}"
  echo "  Optional skipped  : ${#optional_failed[@]}"

  if ((${#failed[@]} > 0)); then
    warn "Core package failures: ${failed[*]}"
  fi

  if ((${#optional_failed[@]} > 0)); then
    warn "Optional package failures: ${optional_failed[*]}"
  fi

  return 0
}

# ---------- Section 3 ----------
section_3_flatpak_apps() {
  show_section_header "Section 3 - Flatpak Applications"

  local failed=()
  local apps=(
    "org.angryip.ipscan|Angry IP Scanner"
    "io.freetubeapp.FreeTube|FreeTube"
    "com.github.iwalton3.jellyfin-media-player|Jellyfin Media Player"
    "tv.plex.PlexHTPC|Plex HTPC"
    "com.github.dail8859.NotepadNext|Notepad Next"
    "com.github.tchx84.Flatseal|Flatseal"
    "com.freerdp.FreeRDP|FreeRDP"
  )

  if ! ensure_flatpak_flathub; then
    warn "Flatpak/Flathub setup failed; skipping Flatpak applications."
    return 1
  fi

  local entry app_id label
  for entry in "${apps[@]}"; do
    IFS='|' read -r app_id label <<< "$entry"
    install_flatpak_app "$app_id" "$label" || failed+=("$label")
  done

  echo
  info "Section 3 summary:"
  echo "  Failed Flatpaks : ${#failed[@]}"
  if ((${#failed[@]} > 0)); then
    warn "Failed Flatpaks: ${failed[*]}"
  fi
}

# ---------- Section 4 ----------
section_4_docker_repo() {
  show_section_header "Section 4 - Docker Repo Setup / Validation"

  detect_os

  if [[ -z "$APT_CODENAME" ]]; then
    error "Could not determine package codename."
    record_failure "docker-codename"
    return 1
  fi

  if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" && "$ARCH" != "armhf" && "$ARCH" != "ppc64el" ]]; then
    warn "Architecture $ARCH may not be supported by Docker's official packages."
  fi

  sudo_run_live "Install Docker repo prerequisites" apt-get install -y ca-certificates curl gnupg

  local conflicting=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  local pkg
  for pkg in "${conflicting[@]}"; do
    if pkg_installed "$pkg"; then
      warn "Removing conflicting package: $pkg"
      sudo apt-get remove -y "$pkg" >>"$LOG_FILE" 2>&1 || true
    fi
  done

  if ! sudo_run "Create /etc/apt/keyrings" install -m 0755 -d /etc/apt/keyrings; then
    record_failure "docker-keyring-dir"
    return 1
  fi

  local docker_gpg="/etc/apt/keyrings/docker.asc"
  local docker_uri
  if [[ "$DOCKER_DISTRO" == "ubuntu" ]]; then
    docker_uri="https://download.docker.com/linux/ubuntu"
  else
    docker_uri="https://download.docker.com/linux/debian"
  fi

  sudo rm -f "$docker_gpg" >>"$LOG_FILE" 2>&1 || true

  if ! sudo_run "Download Docker GPG key" curl -fsSL "${docker_uri}/gpg" -o "$docker_gpg"; then
    error "Docker GPG key download failed. Repo setup cannot continue."
    record_failure "docker-gpg-download"
    return 1
  fi

  if [[ ! -s "$docker_gpg" ]]; then
    error "Docker GPG key file was not created or is empty: $docker_gpg"
    record_failure "docker-gpg-empty"
    return 1
  fi

  if ! sudo_run "Set Docker GPG key permissions" chmod a+r "$docker_gpg"; then
    record_failure "docker-gpg-perms"
    return 1
  fi

  info "Writing Docker repo source for ${DOCKER_DISTRO}:${APT_CODENAME}"
  sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: ${docker_uri}
Suites: ${APT_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: ${docker_gpg}
EOF

  if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
    sudo mv /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.list.disabled >>"$LOG_FILE" 2>&1 || true
    warn "Disabled legacy docker.list to avoid duplicate/conflicting entries."
  fi

  if ! sudo_run_live "Update package lists after Docker repo setup" apt-get update; then
    error "Docker repository metadata update failed."
    record_failure "docker-repo-update"
    return 1
  fi

  info "Docker repo file:"
  sudo cat /etc/apt/sources.list.d/docker.sources | tee -a "$LOG_FILE"

  info "Checking docker-ce package visibility..."
  local docker_madison
  docker_madison="$(apt-cache madison docker-ce 2>&1)"
  echo "$docker_madison" | tee -a "$LOG_FILE"

  if [[ -n "$docker_madison" ]]; then
    success "docker-ce package is visible from configured repositories."
  else
    error "docker-ce package is still not visible after repo setup."
    record_failure "docker-package-visible"
    return 1
  fi

  if confirm "Install Docker Engine packages now?" "N"; then
    if sudo_run_live "Install Docker Engine packages" \
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then

      sudo systemctl enable --now docker >>"$LOG_FILE" 2>&1 || true
      success "Docker service enabled/started (if supported)."

      if confirm "Add ${STARTING_USER} to the docker group?" "Y"; then
        sudo groupadd docker >>"$LOG_FILE" 2>&1 || true
        sudo usermod -aG docker "$STARTING_USER" >>"$LOG_FILE" 2>&1 || true
        warn "You may need to log out and back in for docker group membership to apply."
      fi

      if [[ -d "${STARTING_HOME}/.docker" ]]; then
        sudo chown "$STARTING_USER":"$STARTING_USER" "${STARTING_HOME}/.docker" -R >>"$LOG_FILE" 2>&1 || true
        sudo chmod g+rwx "${STARTING_HOME}/.docker" -R >>"$LOG_FILE" 2>&1 || true
      fi
    else
      error "Docker package installation failed."
      record_failure "docker-engine"
      return 1
    fi
  else
    warn "Skipped Docker package installation. Repo is configured."
  fi
}

# ---------- Section 5 ----------
section_5_install_fonts() {
  show_section_header "Section 5 - Fonts Installation"

  local zip_file="/tmp/Meslo.zip"
  local fonts_dir="/usr/local/share/fonts/MesloLGNerdFont"
  local meslo_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"

  info "Pre-accepting Microsoft core fonts EULA for automated install..."
  if command_exists debconf-set-selections; then
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
    echo "ttf-mscorefonts-installer msttcorefonts/present-mscorefonts-eula note" | sudo debconf-set-selections
  fi

  if pkg_installed ttf-mscorefonts-installer; then
    success "Already installed: ttf-mscorefonts-installer"
  else
    info "Installing Microsoft core fonts..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ttf-mscorefonts-installer 2>&1 | tee -a "$LOG_FILE"; then
      success "Installed: ttf-mscorefonts-installer"
    else
      warn "Failed to install ttf-mscorefonts-installer. On some systems this requires contrib/multiverse repositories."
      record_failure "ttf-mscorefonts-installer"
    fi
  fi

  info "Installing Meslo Nerd Font..."
  run_cmd "Download Meslo Nerd Font archive" wget -O "$zip_file" "$meslo_url" || {
    record_failure "Meslo Nerd Font"
    return 1
  }
  sudo_run "Create Meslo font directory" mkdir -p "$fonts_dir"
  sudo_run "Extract Meslo Nerd Font archive" unzip -o "$zip_file" -d "$fonts_dir"
  sudo_run "Refresh font cache" fc-cache -fv
  success "Fonts installation section completed."
}

# ---------- Section 6 ----------
section_6_set_monospace_font() {
  show_section_header "Section 6 - Set Monospace Font"

  local chosen_font=""
  local fc_meslo=""
  local actual_font=""

  info "Detecting installed Meslo font family..."

  fc_meslo="$(run_as_user fc-list 2>/dev/null | grep -i "Meslo" || true)"

  if [[ -z "$fc_meslo" ]]; then
    warn "Meslo font family was not detected by fontconfig."
    warn "Run Section 5 first, then retry."
    record_failure "meslo-font-detect"
    return 1
  fi

  printf '%s\n' "$fc_meslo" >>"$LOG_FILE"

  if grep -Fqi "MesloLGS Nerd Font Mono" <<< "$fc_meslo"; then
    chosen_font="MesloLGS Nerd Font Mono 14"
  elif grep -Fqi "MesloLGS Nerd Font" <<< "$fc_meslo"; then
    chosen_font="MesloLGS Nerd Font 14"
  else
    chosen_font="$(printf '%s\n' "$fc_meslo" | head -n1 | sed 's/.*: \(.*\):.*/\1/' | awk -F, '{print $1 " 14"}')"
  fi

  info "Using detected monospace font: $chosen_font"

  if ! gsettings_key_exists org.gnome.desktop.interface monospace-font-name; then
    error "GNOME monospace-font-name key is not available"
    record_failure "gnome-monospace-key"
    return 1
  fi

  if ! run_as_user gsettings set org.gnome.desktop.interface monospace-font-name "$chosen_font" >>"$LOG_FILE" 2>&1; then
    error "Could not set org.gnome.desktop.interface::monospace-font-name"
    record_failure "gnome-monospace-font"
    return 1
  fi

  actual_font="$(get_gsetting_if_available org.gnome.desktop.interface monospace-font-name)"

  echo
  info "Verification:"
  echo "  GNOME monospace   : $actual_font"

  echo
  info "Installed Meslo-related fonts detected by fontconfig:"
  printf '%s\n' "$fc_meslo" | tee -a "$LOG_FILE"

  if [[ "$actual_font" == "'$chosen_font'" ]]; then
    success "Verified org.gnome.desktop.interface::monospace-font-name = $chosen_font"
  else
    error "Font setting did not stick. Expected '$chosen_font' but found $actual_font"
    record_failure "gnome-monospace-font-verify"
    warn "Your terminal profile may also have its own font override."
    return 1
  fi

  warn "If your terminal profile overrides the system font, set the terminal profile font manually."
}

# ---------- Section 7 ----------
section_7_zsh_default_shell() {
  show_section_header "Section 7 - ZSH Setup"

  if ! command_exists zsh; then
    if pkg_install zsh; then
      success "Installed zsh"
    else
      error "Failed to install zsh"
      record_failure "zsh"
      return 1
    fi
  fi

  info "Detected zsh version:"
  zsh --version | tee -a "$LOG_FILE"

  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$STARTING_USER" | cut -d: -f7)"

  if [[ "$current_shell" == "$zsh_path" ]]; then
    success "Default shell is already zsh for $STARTING_USER."
  else
    info "Changing default shell for $STARTING_USER to $zsh_path"
    if chsh -s "$zsh_path" "$STARTING_USER" >>"$LOG_FILE" 2>&1; then
      success "Default shell changed to zsh."
    else
      warn "Could not change default shell automatically. You may need to run: chsh -s $zsh_path"
      record_failure "chsh-zsh"
      return 1
    fi
  fi

  local session_shell login_shell
  session_shell="$(run_as_user printenv SHELL 2>/dev/null || true)"
  login_shell="$(getent passwd "$STARTING_USER" | cut -d: -f7)"

  info "Current shell (this session): ${session_shell:-<unknown>}"
  info "Login shell (system): ${login_shell:-<unknown>}"

  if [[ -n "$session_shell" && "$session_shell" != "$login_shell" ]]; then
    warn "Current session is still using the old shell. Log out and back in or run: exec zsh -l"
  fi

  warn "If your terminal profile runs a custom command, set it to: /usr/bin/zsh -l"
}

# ---------- Section 8 ----------
section_8_oh_my_zsh_and_plugins() {
  show_section_header "Section 8 - Oh-My-Zsh, Powerlevel10k, and Plugins"

  local omz_dir="${STARTING_HOME}/.oh-my-zsh"
  local zsh_custom="${omz_dir}/custom"
  local zshrc="${STARTING_HOME}/.zshrc"
  local p10k_file="${STARTING_HOME}/.p10k.zsh"

  if [[ ! -d "$omz_dir" ]]; then
    info "Installing Oh-My-Zsh unattended..."
    run_as_user_shell \
      'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
      >>"$LOG_FILE" 2>&1 \
      && success "Installed Oh-My-Zsh" \
      || {
        error "Oh-My-Zsh installation failed"
        record_failure "oh-my-zsh"
        return 1
      }
  else
    success "Oh-My-Zsh is already installed"
  fi

  ensure_dir "${zsh_custom}/themes"
  ensure_dir "${zsh_custom}/plugins"

  clone_or_update_repo "https://github.com/romkatv/powerlevel10k.git" \
    "${zsh_custom}/themes/powerlevel10k"

  clone_or_update_repo "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "${zsh_custom}/plugins/zsh-autosuggestions"

  clone_or_update_repo "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
    "${zsh_custom}/plugins/zsh-syntax-highlighting"

  clone_or_update_repo "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" \
    "${zsh_custom}/plugins/fast-syntax-highlighting"

  clone_or_update_repo "https://github.com/marlonrichert/zsh-autocomplete.git" \
    "${zsh_custom}/plugins/zsh-autocomplete"

  touch "$zshrc"
  fix_user_file_ownership "$zshrc"

  replace_or_append "$zshrc" '^export ZSH=.*' 'export ZSH="$HOME/.oh-my-zsh"'
  replace_or_append "$zshrc" '^ZSH_THEME=.*' 'ZSH_THEME="powerlevel10k/powerlevel10k"'
  replace_or_append "$zshrc" '^plugins=\(.*\)' \
    'plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)'
  replace_or_append "$zshrc" '^source \$ZSH/oh-my-zsh\.sh$' 'source $ZSH/oh-my-zsh.sh'

  append_if_missing "$zshrc" ''
  append_if_missing "$zshrc" '# Added by workstation setup script'
  append_if_missing "$zshrc" '[[ -r "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"'
  append_if_missing "$zshrc" 'command -v batcat >/dev/null 2>&1 && alias bat=batcat'
  append_if_missing "$zshrc" 'command -v fdfind >/dev/null 2>&1 && alias fd=fdfind'

  success "Updated .zshrc"

  if [[ -f "$p10k_file" ]]; then
    success "Powerlevel10k config already exists: $p10k_file"
  else
    warn "Powerlevel10k config file does not exist yet: $p10k_file"
    warn "The wizard does not always auto-start in unattended/scripted installs."

    if confirm "Launch the Powerlevel10k configuration wizard now?" "Y"; then
      info "Starting Powerlevel10k wizard..."
      warn "If the wizard does not appear cleanly, run: exec zsh -l"
      if run_as_user_shell 'exec zsh -i -c "source ~/.zshrc >/dev/null 2>&1; type p10k >/dev/null 2>&1 && p10k configure"' ; then
        if [[ -f "$p10k_file" ]]; then
          success "Powerlevel10k wizard completed and created $p10k_file"
        else
          warn "Wizard exited, but $p10k_file was not created."
          record_failure "p10k-config"
        fi
      else
        warn "Powerlevel10k wizard did not complete successfully."
        warn "Run these manually in your terminal:"
        echo '  exec zsh -l'
        echo '  p10k configure'
        record_failure "p10k-config"
      fi
    else
      warn "Skipped Powerlevel10k wizard."
      warn "Run these manually later:"
      echo '  exec zsh -l'
      echo '  p10k configure'
    fi
  fi
}

# ---------- Section 9 ----------
section_9_date_time() {
  show_section_header "Section 9 - Date/Time and Privacy Preferences"

  info "Discovering supported Cinnamon/GNOME date, time, and privacy settings..."
  info "Only valid and writable keys will be applied."

  local settings=(
    "org.cinnamon.desktop.interface|clock-use-24h|true"
    "org.cinnamon.desktop.interface|clock-show-date|true"
    "org.cinnamon.desktop.calendar|first-day-of-week|'sunday'"
    "org.gnome.desktop.interface|clock-format|'24h'"
    "org.gnome.desktop.interface|clock-show-date|true"
  )

  local entry schema key value
  local applied_count=0
  local skipped_count=0
  local privacy_applied=0
  local privacy_skipped=0

  for entry in "${settings[@]}"; do
    IFS='|' read -r schema key value <<< "$entry"

    if gsettings_key_exists "$schema" "$key" && gsettings_key_writable "$schema" "$key"; then
      if run_as_user gsettings set "$schema" "$key" "$value" >>"$LOG_FILE" 2>&1; then
        success "Set $schema::$key to $value"
        ((applied_count++))
      else
        warn "Could not set $schema::$key"
      fi
    else
      info "Skipping unsupported or non-writable key: $schema::$key"
      ((skipped_count++))
    fi
  done

  echo
  info "Privacy option: disable remembering recently accessed files."
  if confirm "Disable 'Remember recently accessed files' for this user?" "Y"; then
    local privacy_settings=(
      "org.cinnamon.desktop.privacy|remember-recent-files|false"
      "org.gnome.desktop.privacy|remember-recent-files|false"
    )

    for entry in "${privacy_settings[@]}"; do
      IFS='|' read -r schema key value <<< "$entry"

      if gsettings_key_exists "$schema" "$key" && gsettings_key_writable "$schema" "$key"; then
        if run_as_user gsettings set "$schema" "$key" "$value" >>"$LOG_FILE" 2>&1; then
          success "Set $schema::$key to $value"
          ((privacy_applied++))
        else
          warn "Could not set $schema::$key"
        fi
      else
        info "Skipping unsupported or non-writable privacy key: $schema::$key"
        ((privacy_skipped++))
      fi
    done

    if [[ -f "${STARTING_HOME}/.local/share/recently-used.xbel" ]]; then
      if confirm "Clear the existing recent files history now?" "Y"; then
        if run_as_user truncate -s 0 "${STARTING_HOME}/.local/share/recently-used.xbel" >>"$LOG_FILE" 2>&1; then
          success "Cleared recent files history: ${STARTING_HOME}/.local/share/recently-used.xbel"
        else
          warn "Could not clear ${STARTING_HOME}/.local/share/recently-used.xbel"
          record_failure "recent-files-history-clear"
        fi
      else
        warn "Existing recent files history was left in place. New recent file tracking should still be disabled."
      fi
    else
      info "No existing recent files history file found at ${STARTING_HOME}/.local/share/recently-used.xbel"
    fi
  else
    warn "Leaving 'Remember recently accessed files' unchanged."
  fi

  echo
  info "Verification:"
  echo "  Cinnamon 24h               : $(get_gsetting_if_available org.cinnamon.desktop.interface clock-use-24h)"
  echo "  Cinnamon show date         : $(get_gsetting_if_available org.cinnamon.desktop.interface clock-show-date)"
  echo "  First day of week          : $(get_gsetting_if_available org.cinnamon.desktop.calendar first-day-of-week)"
  echo "  GNOME clock format         : $(get_gsetting_if_available org.gnome.desktop.interface clock-format)"
  echo "  GNOME show date            : $(get_gsetting_if_available org.gnome.desktop.interface clock-show-date)"
  echo "  Cinnamon recent files      : $(get_gsetting_if_available org.cinnamon.desktop.privacy remember-recent-files)"
  echo "  GNOME recent files         : $(get_gsetting_if_available org.gnome.desktop.privacy remember-recent-files)"

  echo
  info "Section 9 summary:"
  echo "  Applied date/time settings : $applied_count"
  echo "  Skipped date/time settings : $skipped_count"
  echo "  Applied privacy settings   : $privacy_applied"
  echo "  Skipped privacy settings   : $privacy_skipped"

  success "Date/time and privacy preferences section completed."
}

# ---------- Section 10 ----------
section_10_firewall() {
  show_section_header "Section 10 - Firewall (UFW)"

  if ! command_exists ufw; then
    if pkg_install ufw; then
      success "Installed ufw"
    else
      error "Failed to install ufw"
      record_failure "ufw"
      return 1
    fi
  fi

  if pkg_installed gufw; then
    success "GUFW is installed for GUI firewall management."
  fi

  if sudo ufw status | grep -qi "Status: active"; then
    success "UFW is already enabled"
  else
    info "Enabling UFW..."
    if sudo ufw --force enable >>"$LOG_FILE" 2>&1; then
      success "UFW enabled"
    else
      error "Failed to enable UFW"
      record_failure "ufw-enable"
      return 1
    fi
  fi

  echo
  info "UFW verbose status:"
  sudo ufw status verbose | tee -a "$LOG_FILE"

  if command_exists docker || pkg_installed docker-ce || pkg_installed docker.io; then
    warn "Docker can bypass expected UFW behavior when publishing container ports."

    if confirm "Apply basic Docker/UFW hardening defaults in /etc/docker/daemon.json if no file exists?" "N"; then
      local daemon_json="/etc/docker/daemon.json"
      if [[ -e "$daemon_json" ]]; then
        warn "$daemon_json already exists. Leaving it unchanged to avoid overwriting your Docker configuration."
      else
        if sudo tee "$daemon_json" >/dev/null <<'EOF'
{
  "iptables": true,
  "ip-forward": true,
  "userland-proxy": false
}
EOF
        then
          success "Wrote basic Docker daemon defaults to $daemon_json"
          warn "Restart Docker after installation for daemon.json changes to apply."
        else
          warn "Could not write $daemon_json"
          record_failure "docker-ufw-hardening"
        fi
      fi
    fi
  else
    warn "If you later install Docker and publish container ports, Docker can bypass expected UFW behavior."
  fi
}

# ---------- Section 11 ----------
section_11_nemo_preferences() {
  show_section_header "Section 11 - Nemo File Manager Preferences"

  if ! nemo_available; then
    warn "Nemo is not installed on this system. Skipping Nemo preferences."
    return 0
  fi

  info "Discovering supported Nemo settings on this build..."
  info "Only valid and writable keys will be applied."

  local settings=(
    "org.nemo.preferences|default-folder-viewer|'list-view'"
    "org.nemo.preferences|click-policy|'double'"
    "org.nemo.preferences|executable-text-activation|'display'"
    "org.nemo.window-state|start-with-toolbar|true"
    "org.nemo.window-state|start-with-sidebar|true"
    "org.nemo.window-state|start-with-status-bar|true"
    "org.nemo.preferences|show-full-path-titles|true"
    "org.nemo.preferences|show-location-entry|true"
    "org.nemo.preferences|show-open-in-terminal-toolbar|true"
    "org.nemo.preferences|show-new-folder-toolbar|true"
    "org.nemo.preferences|show-search-icon-toolbar|true"
    "org.nemo.preferences|show-icon-view|true"
    "org.nemo.preferences|show-list-view|true"
    "org.nemo.preferences|show-open-in-new-tab|true"
    "org.nemo.preferences|show-open-in-new-window|true"
    "org.nemo.preferences|show-open-in-terminal|true"
    "org.nemo.preferences|show-edit-icon-toolbar|true"
    "org.nemo.preferences|show-home-icon-toolbar|true"
    "org.nemo.preferences|show-computer-icon-toolbar|true"
    "org.nemo.preferences|show-up-icon-toolbar|true"
    "org.nemo.preferences|show-reload-icon-toolbar|true"
    "org.nemo.preferences|show-back-icon-toolbar|true"
    "org.nemo.preferences|show-forward-icon-toolbar|true"
    "org.nemo.preferences|show-hidden-files|true"
    "org.nemo.preferences|sort-directories-first|true"
  )

  local entry schema key value
  local applied_count=0
  local skipped_count=0
  local skipped_keys=()

  for entry in "${settings[@]}"; do
    IFS='|' read -r schema key value <<< "$entry"

    if gsettings_key_exists "$schema" "$key" && gsettings_key_writable "$schema" "$key"; then
      set_gsetting_if_supported "$schema" "$key" "$value"
      ((applied_count++))
    else
      skipped_keys+=("$schema::$key")
      ((skipped_count++))
    fi
  done

  echo
  info "Verification:"
  echo "  default-folder-viewer: $(get_gsetting_if_available org.nemo.preferences default-folder-viewer)"
  echo "  click-policy         : $(get_gsetting_if_available org.nemo.preferences click-policy)"
  echo "  executable-text-act. : $(get_gsetting_if_available org.nemo.preferences executable-text-activation)"
  echo "  show-location-entry  : $(get_gsetting_if_available org.nemo.preferences show-location-entry)"
  echo "  show-hidden-files    : $(get_gsetting_if_available org.nemo.preferences show-hidden-files)"
  echo "  sort-directories-first: $(get_gsetting_if_available org.nemo.preferences sort-directories-first)"
  echo "  start-with-toolbar   : $(get_gsetting_if_available org.nemo.window-state start-with-toolbar)"

  echo
  info "Section 11 summary:"
  echo "  Applied settings : $applied_count"
  echo "  Skipped settings : $skipped_count"

  if ((${#skipped_keys[@]} > 0)); then
    info "Skipped Nemo keys (${#skipped_keys[@]}):"
    printf '  - %s
' "${skipped_keys[@]}"
  fi

  run_as_user_shell "nemo -q >/dev/null 2>&1 || true"
  success "Nemo preferences section completed."
}

# ---------- Section 12 ----------
install_nemo_mediainfo_tab() {
  local url="https://github.com/linux-man/nemo-mediainfo-tab/releases/download/v1.0.4/nemo-mediainfo-tab_1.0.4_all.deb"
  local tmp_deb="/tmp/nemo-mediainfo-tab_1.0.4_all.deb"

  info "Downloading nemo-mediainfo-tab..."
  rm -f "$tmp_deb"

  if wget -O "$tmp_deb" "$url" >>"$LOG_FILE" 2>&1; then
    success "Downloaded nemo-mediainfo-tab package with wget"
  elif curl -fL "$url" -o "$tmp_deb" >>"$LOG_FILE" 2>&1; then
    success "Downloaded nemo-mediainfo-tab package with curl"
  else
    warn "Download failed for nemo-mediainfo-tab"
    record_failure "nemo-mediainfo-tab-download"
    return 1
  fi

  if [[ ! -s "$tmp_deb" ]]; then
    warn "Downloaded nemo-mediainfo-tab file is missing or empty"
    record_failure "nemo-mediainfo-tab-download-empty"
    return 1
  fi

  info "Installing nemo-mediainfo-tab package..."
  if sudo dpkg -i "$tmp_deb" >>"$LOG_FILE" 2>&1; then
    success "Installed nemo-mediainfo-tab package"
  else
    warn "dpkg reported dependency issues, attempting repair..."
    pkg_fix_broken
    if sudo dpkg -i "$tmp_deb" >>"$LOG_FILE" 2>&1; then
      success "Installed nemo-mediainfo-tab package after dependency repair"
    else
      warn "nemo-mediainfo-tab did not finish installing cleanly"
      record_failure "nemo-mediainfo-tab-install"
      return 1
    fi
  fi

  if dpkg -s nemo-mediainfo-tab >/dev/null 2>&1; then
    success "nemo-mediainfo-tab is installed"
  else
    warn "nemo-mediainfo-tab package is not detected as installed"
    record_failure "nemo-mediainfo-tab-install-verify"
    return 1
  fi

  return 0
}

section_12_nemo_enhancements() {
  show_section_header "Section 12 - Nemo Enhancements"

  if ! nemo_available; then
    warn "Nemo is not installed on this system. Skipping Nemo enhancements."
    return 0
  fi

  local nemo_enhancement_pkgs=(
    nemo-media-columns
    libmediainfo0v5
    libmms0
    libtinyxml2-11
    libzen0t64
    python3-mediainfodll
    python3-pymediainfo
    python3-pypdf
    python3-stopit
    gir1.2-gexiv2-0.10
  )

  info "Installing Nemo enhancement dependencies..."
  if ! pkg_install "${nemo_enhancement_pkgs[@]}"; then
    warn "Some Nemo enhancement dependencies failed to install."
    record_failure "nemo-enhancement-dependencies"
  else
    success "Installed Nemo enhancement dependencies"
  fi

  if confirm "Install Nemo MediaInfo tab enhancement?" "Y"; then
    if install_nemo_mediainfo_tab; then
      success "Nemo enhancement installation complete."
    else
      warn "Nemo enhancement section completed with warnings."
    fi
  else
    warn "Skipped nemo-mediainfo-tab installation."
    success "Nemo enhancement installation complete."
  fi

  echo
  if pgrep -x nemo >/dev/null 2>&1; then
    if confirm "Restart Nemo now to apply enhancements?" "Y"; then
      info "Restarting Nemo..."
      if run_as_user nemo -q >>"$LOG_FILE" 2>&1; then
        success "Nemo restarted successfully"
      else
        warn "Failed to restart Nemo automatically"
        warn "You can restart manually with: nemo -q"
        record_failure "nemo-restart"
      fi
    else
      warn "Skipping Nemo restart."
      warn "Run 'nemo -q' manually to apply changes."
    fi
  else
    info "Nemo is not currently running — no restart needed."
  fi
}

# ---------- Section 13 ----------
section_13_winboat() {
  show_section_header "Section 13 - WinBoat"

  detect_os

  info "Validating WinBoat prerequisites..."

  if kvm_available; then
    success "KVM device detected: /dev/kvm"
  else
    warn "KVM device not detected. WinBoat requires virtualization/KVM support."
    warn "Check BIOS/UEFI virtualization settings and that your system supports KVM."
    record_failure "winboat-kvm"
  fi

  if command_exists docker; then
    success "Docker is installed"
  else
    warn "Docker is not installed. Run Section 4 first."
    record_failure "winboat-docker"
  fi

  if docker compose version >>"$LOG_FILE" 2>&1; then
    success "Docker Compose v2 is available"
  else
    warn "Docker Compose v2 is not available. Run Section 4 first."
    record_failure "winboat-docker-compose"
  fi

  if systemctl is-active --quiet docker; then
    success "Docker daemon is running"
  else
    warn "Docker daemon is not running"
    if confirm "Start Docker now?" "Y"; then
      if sudo systemctl start docker >>"$LOG_FILE" 2>&1; then
        success "Docker daemon started"
      else
        warn "Could not start Docker daemon"
        record_failure "winboat-docker-start"
      fi
    fi
  fi

  if systemctl is-enabled --quiet docker 2>/dev/null; then
    success "Docker service is enabled at boot"
  else
    warn "Docker service is not enabled at boot"
    if confirm "Enable Docker at boot now?" "Y"; then
      sudo systemctl enable docker.service containerd.service >>"$LOG_FILE" 2>&1 || true
    fi
  fi

  if user_in_group "$STARTING_USER" docker; then
    success "User ${STARTING_USER} is already in the docker group"
  else
    warn "User ${STARTING_USER} is not in the docker group"
    if confirm "Add ${STARTING_USER} to the docker group now?" "Y"; then
      sudo groupadd docker >>"$LOG_FILE" 2>&1 || true
      sudo usermod -aG docker "$STARTING_USER" >>"$LOG_FILE" 2>&1 || true
      warn "Log out and back in before using Docker without sudo."
    fi
  fi

  if [[ -d "${STARTING_HOME}/.docker" ]]; then
    sudo chown "$STARTING_USER":"$STARTING_USER" "${STARTING_HOME}/.docker" -R >>"$LOG_FILE" 2>&1 || true
    sudo chmod g+rwx "${STARTING_HOME}/.docker" -R >>"$LOG_FILE" 2>&1 || true
  fi

  if flatpak_app_installed "com.freerdp.FreeRDP"; then
    success "FreeRDP Flatpak is installed"
  else
    warn "FreeRDP Flatpak is not installed. Run Section 3 first."
    record_failure "winboat-freerdp"
  fi

  if command_exists docker; then
    info "Running Docker hello-world test with sudo..."
    if sudo docker run --rm hello-world >>"$LOG_FILE" 2>&1; then
      success "Docker hello-world test passed"
    else
      warn "Docker hello-world test failed"
      record_failure "winboat-docker-hello-world"
    fi
  fi

  warn "WinBoat requires Docker, Docker Compose v2, Docker daemon running, user in docker group, KVM, and FreeRDP."
  warn "If you were just added to the docker group, log out and back in before trying Docker without sudo."

  if confirm "Download and install the latest WinBoat Debian package now?" "Y"; then
    install_latest_winboat_deb || return 1
  else
    warn "Skipped WinBoat package installation."
  fi

  if command_exists winboat; then
    success "WinBoat command detected"
    if confirm "Launch WinBoat now?" "N"; then
      run_as_user winboat >>"$LOG_FILE" 2>&1 &
      success "WinBoat launched"
    fi
  else
    warn "WinBoat command not found in PATH yet. You may need to log out/in or launch it from the app menu."
  fi
}

# ---------- Section 14 ----------
section_14_jdownloader() {
  show_section_header "Section 14 - JDownloader"

  local app_id="org.jdownloader.JDownloader"
  local flatpakref_url="https://dl.flathub.org/repo/appstream/org.jdownloader.JDownloader.flatpakref"
  local flatpakref_file="${DOWNLOAD_DIR}/org.jdownloader.JDownloader.flatpakref"

  detect_os

  if [[ "$STARTING_USER" == "root" ]]; then
    warn "The script is currently using STARTING_USER=root."
    warn "Flatpak desktop apps should normally be installed for your desktop user."
    warn "Best practice: run this script with sudo from your normal user session, not from a root shell."
  fi

  ensure_dir "$DOWNLOAD_DIR"

  if ! ensure_flatpak_flathub; then
    error "Flatpak/Flathub setup failed; cannot install JDownloader."
    record_failure "jdownloader-flatpak-setup"
    return 1
  fi

  if flatpak_app_installed "$app_id"; then
    success "JDownloader is already installed via Flatpak"
  else
    info "Installing JDownloader from Flathub..."
    if sudo flatpak install --system -y flathub "$app_id" >>"$LOG_FILE" 2>&1; then
      success "Installed JDownloader via Flatpak"
    else
      warn "Flatpak install from Flathub failed."
      warn "Trying .flatpakref fallback..."

      if wget -O "$flatpakref_file" "$flatpakref_url" >>"$LOG_FILE" 2>&1; then
        success "Downloaded JDownloader .flatpakref file"
        if sudo flatpak install --system -y "$flatpakref_file" >>"$LOG_FILE" 2>&1; then
          success "Installed JDownloader from .flatpakref"
        else
          error "Failed to install JDownloader from .flatpakref"
          record_failure "jdownloader-flatpakref-install"
          return 1
        fi
      else
        error "Failed to download JDownloader .flatpakref file"
        record_failure "jdownloader-flatpakref-download"
        return 1
      fi
    fi
  fi

  if sudo flatpak info --system "$app_id" >/dev/null 2>&1; then
    success "Verified JDownloader Flatpak installation"
  else
    error "JDownloader Flatpak installation could not be verified"
    record_failure "jdownloader-verify"
    return 1
  fi

  if confirm "Launch JDownloader now?" "Y"; then
    if run_as_user flatpak run "$app_id" >>"$LOG_FILE" 2>&1 & then
      success "Launched JDownloader"
    else
      warn "Could not launch JDownloader automatically"
      warn "You can launch it manually with: flatpak run $app_id"
      record_failure "jdownloader-launch"
    fi
  fi
}

# ---------- VS Code Helpers ----------
setup_vscode_repo() {
  local keyring="/usr/share/keyrings/microsoft.gpg"
  local repo_file="/etc/apt/sources.list.d/vscode.sources"

  info "Configuring the official VS Code apt repository..."

  if ! sudo_run_live "Install VS Code repo prerequisites" apt-get install -y wget gpg apt-transport-https; then
    record_failure "vscode-repo-prereqs"
    return 1
  fi

  if ! sudo bash -c 'wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg' >>"$LOG_FILE" 2>&1; then
    error "Failed to download or convert the Microsoft signing key"
    record_failure "vscode-signing-key"
    return 1
  fi

  if ! sudo install -D -o root -g root -m 644 /tmp/microsoft.gpg "$keyring" >>"$LOG_FILE" 2>&1; then
    error "Failed to install the Microsoft signing key"
    record_failure "vscode-signing-key-install"
    sudo rm -f /tmp/microsoft.gpg >>"$LOG_FILE" 2>&1 || true
    return 1
  fi

  sudo rm -f /tmp/microsoft.gpg >>"$LOG_FILE" 2>&1 || true

  if ! sudo tee "$repo_file" >/dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  then
    error "Failed to write $repo_file"
    record_failure "vscode-repo-file"
    return 1
  fi

  if ! sudo_run_live "Update apt after adding the VS Code repo" apt update; then
    record_failure "vscode-repo-update"
    return 1
  fi

  success "Official VS Code repository is configured"
  return 0
}

install_vscode_extensions() {
  local failed=()
  local ext

  if ! command_exists code; then
    warn "VS Code command 'code' is not available yet. Skipping extension install."
    record_failure "vscode-extensions-code-cli"
    return 1
  fi

  local extensions=(
    "GitHub.vscode-pull-request-github|GitHub Pull Requests and Issues"
    "GitHub.remotehub|GitHub Repositories"
    "ms-vscode.remote-repositories|Remote Repositories"
  )

  for ext in "${extensions[@]}"; do
    local ext_id ext_label
    IFS='|' read -r ext_id ext_label <<< "$ext"
    info "Installing VS Code extension: $ext_label"
    if run_as_user code --install-extension "$ext_id" >>"$LOG_FILE" 2>&1; then
      success "Installed VS Code extension: $ext_label"
    else
      warn "Could not install VS Code extension: $ext_label"
      failed+=("$ext_id")
      record_failure "$ext_id"
    fi
  done

  if ((${#failed[@]} > 0)); then
    warn "Some VS Code extensions failed: ${failed[*]}"
    return 1
  fi

  return 0
}

show_user_file_preview() {
  local file="$1"
  local lines="${2:-10}"

  if [[ -f "$file" ]]; then
    echo "------------------------------------------------------------"
    sed -n "1,${lines}p" "$file"
    echo "------------------------------------------------------------"
  fi
}

# ---------- Section 15 ----------
section_16_openssh_server() {
  show_section_header "Section 16 - OpenSSH Server"

  local ssh_pkgs=(
    openssh-server
    openssh-client
    openssh-sftp-server
    libwtmpdb0
    ncurses-term
  )
  local primary_ip=""
  local sshd_conf="/etc/ssh/sshd_config"
  local sshd_backup=""

  info "Installing OpenSSH Server packages..."
  if pkg_install "${ssh_pkgs[@]}"; then
    success "Installed OpenSSH Server packages"
  else
    error "Failed to install OpenSSH Server packages"
    record_failure "openssh-server-install"
    return 1
  fi

  info "Enabling SSH service..."
  if sudo systemctl enable ssh >>"$LOG_FILE" 2>&1; then
    success "SSH service enabled at boot"
  else
    error "Failed to enable SSH service"
    record_failure "openssh-server-enable"
    return 1
  fi

  info "Starting SSH service..."
  if sudo systemctl start ssh >>"$LOG_FILE" 2>&1; then
    success "SSH service started"
  else
    error "Failed to start SSH service"
    record_failure "openssh-server-start"
    return 1
  fi

  echo
  info "SSH service status:"
  if sudo systemctl status ssh --no-pager | tee -a "$LOG_FILE"; then
    :
  else
    warn "Could not display full SSH service status"
  fi

  if systemctl is-active --quiet ssh; then
    success "SSH service is active and running"
  else
    error "SSH service is not active"
    record_failure "openssh-server-active"
    return 1
  fi

  if systemctl is-enabled --quiet ssh 2>/dev/null; then
    success "SSH service is enabled"
  else
    warn "SSH service is not enabled"
    record_failure "openssh-server-enabled-check"
  fi

  info "Listening SSH sockets:"
  (sudo ss -tulpn 2>/dev/null | grep -E '(:22\s|sshd)' | tee -a "$LOG_FILE") || warn "Could not confirm SSH listener with ss"

  echo
  if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
    warn "UFW is active and may block SSH access."

    if sudo ufw status | grep -Eq '(^|[[:space:]])22/tcp[[:space:]]'; then
      success "UFW already allows SSH on port 22/tcp"
    elif confirm "Allow SSH (port 22/tcp) through the firewall?" "Y"; then
      if sudo ufw allow 22/tcp >>"$LOG_FILE" 2>&1; then
        success "Allowed SSH through UFW firewall"
      else
        warn "Failed to update UFW rules for SSH"
        record_failure "ufw-ssh-rule"
      fi
    else
      warn "SSH may not be accessible remotely due to firewall rules."
    fi
  fi

  primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$primary_ip" ]]; then
    info "To connect from another machine:"
    echo "  ssh ${STARTING_USER}@${primary_ip}"
  else
    warn "Could not determine the primary IP address automatically."
  fi

  echo
  if confirm "Apply basic SSH hardening now?" "N"; then
    sshd_backup="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"

    if sudo cp "$sshd_conf" "$sshd_backup" >>"$LOG_FILE" 2>&1; then
      success "Backed up sshd_config to $sshd_backup"
    else
      error "Failed to back up sshd_config"
      record_failure "sshd-config-backup"
      return 1
    fi

    if ! set_sshd_config_value PermitRootLogin no; then
      error "Failed to set PermitRootLogin"
      record_failure "sshd-permitrootlogin"
      return 1
    fi

    if ! set_sshd_config_value MaxAuthTries 3; then
      error "Failed to set MaxAuthTries"
      record_failure "sshd-maxauthtries"
      return 1
    fi

    success "Applied basic SSH hardening settings"

    if [[ -f "${STARTING_HOME}/.ssh/authorized_keys" ]]; then
      if confirm "Disable SSH password authentication and require keys only?" "N"; then
        if set_sshd_config_value PasswordAuthentication no \
          && set_sshd_config_value KbdInteractiveAuthentication no \
          && set_sshd_config_value ChallengeResponseAuthentication no; then
          success "Configured SSH for key-based authentication only"
        else
          error "Failed to apply key-only SSH authentication settings"
          record_failure "sshd-key-only-auth"
          return 1
        fi
      fi
    else
      warn "No ${STARTING_HOME}/.ssh/authorized_keys file detected; leaving password authentication enabled."
    fi

    info "Validating sshd configuration..."
    if sudo sshd -t >>"$LOG_FILE" 2>&1; then
      success "sshd configuration validation passed"
    else
      error "sshd configuration validation failed; restoring backup"
      sudo cp "$sshd_backup" "$sshd_conf" >>"$LOG_FILE" 2>&1 || true
      record_failure "sshd-config-validate"
      return 1
    fi

    info "Restarting SSH service after hardening..."
    if sudo systemctl restart ssh >>"$LOG_FILE" 2>&1; then
      success "SSH service restarted successfully"
    else
      error "Failed to restart SSH service after hardening"
      sudo cp "$sshd_backup" "$sshd_conf" >>"$LOG_FILE" 2>&1 || true
      sudo systemctl restart ssh >>"$LOG_FILE" 2>&1 || true
      record_failure "sshd-restart-hardened"
      return 1
    fi

    if systemctl is-active --quiet ssh; then
      success "SSH service is active after hardening"
    else
      error "SSH service is not active after hardening"
      record_failure "sshd-active-after-hardening"
      return 1
    fi
  fi
}

# ---------- Section 15 ----------
section_15_vscode() {
  show_section_header "Section 15 - VS Code + GitHub Setup"

  detect_os

  local git_name=""
  local git_email=""
  local current_git_name=""
  local current_git_email=""
  local ssh_dir="${STARTING_HOME}/.ssh"
  local ssh_key="${ssh_dir}/id_ed25519"
  local ssh_pub="${ssh_key}.pub"
  local ssh_config="${ssh_dir}/config"
  local projects_root="${STARTING_HOME}/Projects"
  local projects_dir="${projects_root}/github"
  local final_steps_file="${projects_root}/vscode_final_steps.txt"
  local vscode_pkg="code"

  if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" && "$ARCH" != "armhf" ]]; then
    warn "Official VS Code packages are typically provided for amd64, arm64, and armhf. Detected architecture: $ARCH"
  fi

  info "VS Code section will install the official Microsoft package, verify Git, and optionally help set up GitHub SSH access."

  if ! command_exists git; then
    if confirm "Git is not installed. Install Git now?" "Y"; then
      if pkg_install git; then
        success "Installed Git"
      else
        error "Failed to install Git"
        record_failure "git"
        return 1
      fi
    else
      warn "Git install skipped. VS Code can still be installed, but GitHub workflows will be limited."
    fi
  else
    success "Git is already installed"
    git --version | tee -a "$LOG_FILE"
  fi

  if pkg_installed "$vscode_pkg" || command_exists code; then
    success "VS Code is already installed"
  else
    if ! setup_vscode_repo; then
      error "VS Code repository setup failed"
      return 1
    fi

    if sudo_run_live "Install Visual Studio Code" apt install -y code; then
      success "Visual Studio Code installed successfully"
    else
      error "Failed to install Visual Studio Code"
      record_failure "vscode-install"
      return 1
    fi
  fi

  if command_exists code; then
    success "VS Code command detected: $(command -v code)"
    run_as_user code --version | head -n1 | tee -a "$LOG_FILE" || true
  else
    warn "VS Code package installed, but 'code' is not currently in PATH"
    record_failure "vscode-code-cli"
  fi

  if confirm "Configure global Git identity for ${STARTING_USER}?" "Y"; then
    current_git_name="$(run_as_user git config --global user.name 2>/dev/null || true)"
    current_git_email="$(run_as_user git config --global user.email 2>/dev/null || true)"

    read -r -p "Git user.name [${current_git_name:-Your Name}]: " git_name
    git_name="${git_name:-${current_git_name:-}}"

    read -r -p "Git user.email [${current_git_email:-your-email@example.com}]: " git_email
    git_email="${git_email:-${current_git_email:-}}"

    if [[ -n "$git_name" ]]; then
      run_as_user git config --global user.name "$git_name" >>"$LOG_FILE" 2>&1 \
        && success "Set git user.name to $git_name" \
        || warn "Could not set git user.name"
    else
      warn "Git user.name was left unchanged"
    fi

    if [[ -n "$git_email" ]]; then
      run_as_user git config --global user.email "$git_email" >>"$LOG_FILE" 2>&1 \
        && success "Set git user.email to $git_email" \
        || warn "Could not set git user.email"
    else
      warn "Git user.email was left unchanged"
    fi

    info "Current global Git settings:"
    run_as_user git config --global --list | tee -a "$LOG_FILE" || true
  fi

  if confirm "Create a default GitHub projects folder at ${projects_dir}?" "Y"; then
    if run_as_user mkdir -p "$projects_dir" >>"$LOG_FILE" 2>&1; then
      success "Created or confirmed: $projects_dir"
    else
      warn "Could not create $projects_dir"
      record_failure "vscode-projects-dir"
    fi
  fi

  info "Creating VS Code final steps reference file at ${final_steps_file}"
  if run_as_user mkdir -p "$projects_root" >>"$LOG_FILE" 2>&1; then
    if run_as_user bash -c 'cat > "$1" <<'"'"'EOF'"'"'
1. Sign into GitHub from VS Code
Open VS Code
Look at the Accounts icon in the bottom-left corner (little person icon).
Click it → Sign in with GitHub.
It’ll open a browser asking you to authorize VS Code / GitHub extension – accept.
Once done, VS Code should show you as signed in with your GitHub account.
If needed, install GitHub-related extensions:
Go to Extensions (square icon on left)
Search and install:
GitHub Pull Requests and Issues
(Optional) GitHub Repositories
These make interaction with GitHub much smoother.

2. Clone your GitHub repos into VS Code

Your repos are at:
https://github.com/sprite007-stack?tab=repositories
Pick one repo (say my-repo as an example).

Option A – Using VS Code UI (recommended)
In VS Code, press Ctrl+Shift+P to open the Command Palette.
Type: Git: Clone → select Clone from Github "remote sources"


For URL, use either:

SSH (recommended):
git@github.com:sprite007-stack/my-repo.git

Or HTTPS:
https://github.com/sprite007-stack/my-repo.git
https://github.com/sprite007-stack/debian_system
EOF' _ "$final_steps_file" >>"$LOG_FILE" 2>&1; then
      success "Created VS Code final steps file: $final_steps_file"
    else
      warn "Could not create $final_steps_file"
      record_failure "vscode-final-steps-file"
    fi
  else
    warn "Could not create ${projects_root}"
    record_failure "vscode-projects-root"
  fi

  if confirm "Set up GitHub SSH authentication guidance now?" "Y"; then
    if [[ ! -d "$ssh_dir" ]]; then
      run_as_user mkdir -p "$ssh_dir" >>"$LOG_FILE" 2>&1 || true
      run_as_user chmod 700 "$ssh_dir" >>"$LOG_FILE" 2>&1 || true
    fi

    if [[ -f "$ssh_key" && -f "$ssh_pub" ]]; then
      success "An Ed25519 SSH key already exists: $ssh_key"
    else
      local ssh_comment=""
      read -r -p "GitHub email/comment for the new SSH key [${git_email:-your-github-email@example.com}]: " ssh_comment
      ssh_comment="${ssh_comment:-${git_email:-your-github-email@example.com}}"

      if confirm "Generate a new Ed25519 SSH key at ${ssh_key}?" "Y"; then
        if run_as_user ssh-keygen -t ed25519 -C "$ssh_comment" -f "$ssh_key"; then
          success "Created SSH keypair: $ssh_key"
        else
          error "Failed to generate SSH keypair"
          record_failure "github-ssh-keygen"
        fi
      fi
    fi

    if [[ -f "$ssh_pub" ]]; then
      info "Ensuring SSH uses your Ed25519 key automatically..."
      touch "$ssh_config"
      fix_user_file_ownership "$ssh_config"
      run_as_user chmod 600 "$ssh_config" >>"$LOG_FILE" 2>&1 || true
      append_if_missing "$ssh_config" 'Host *'
      append_if_missing "$ssh_config" '    AddKeysToAgent yes'
      append_if_missing "$ssh_config" '    IdentityFile ~/.ssh/id_ed25519'
      append_if_missing "$ssh_config" 'Host github.com'
      append_if_missing "$ssh_config" '    HostName github.com'
      append_if_missing "$ssh_config" '    User git'
      append_if_missing "$ssh_config" '    IdentityFile ~/.ssh/id_ed25519'

      info "Attempting to add the SSH key to an agent for this session..."
      if run_as_user_shell 'eval "$(ssh-agent -s)" >/dev/null 2>&1 && ssh-add ~/.ssh/id_ed25519' >>"$LOG_FILE" 2>&1; then
        success "SSH key added to a session agent"
      else
        warn "Could not add the SSH key to an agent automatically. Your desktop session may still manage keys for you."
        record_failure "github-ssh-agent"
      fi

      info "Copy this public key into GitHub > Settings > SSH and GPG keys:"
      show_user_file_preview "$ssh_pub" 5
      warn "After adding the key in GitHub, test it with: ssh -T git@github.com"

      if confirm "Test SSH access to GitHub now?" "N"; then
        local ssh_test_output=""
        ssh_test_output="$(run_as_user ssh -o StrictHostKeyChecking=accept-new -T git@github.com </dev/null 2>&1 | tee -a "$LOG_FILE")"
        if grep -Fqi "successfully authenticated" <<< "$ssh_test_output"; then
          success "GitHub SSH authentication succeeded. GitHub does not provide shell access, so that message is expected."
        else
          warn "SSH test did not show a GitHub authentication success message. This is common if the key is not yet added to GitHub."
          record_failure "github-ssh-test"
        fi
      fi
    else
      warn "No SSH public key is available to show or test."
    fi
  fi

  if confirm "Install recommended GitHub-related VS Code extensions now?" "Y"; then
    install_vscode_extensions || true
  fi

  if confirm "Set VS Code as the default terminal editor using update-alternatives?" "N"; then
    if command_exists code; then
      sudo update-alternatives --install /usr/bin/editor editor "$(command -v code)" 10 >>"$LOG_FILE" 2>&1 || true
      if sudo update-alternatives --set editor "$(command -v code)" >>"$LOG_FILE" 2>&1; then
        success "VS Code is now configured as the default editor"
      else
        warn "Could not set VS Code as the default editor"
        record_failure "vscode-default-editor"
      fi
    else
      warn "Cannot set VS Code as default editor because the code command is unavailable"
    fi
  fi

  echo
  info "VS Code quick-start reminders:"
  echo "  1. Open VS Code and sign in with GitHub from the Accounts menu if desired."
  echo "  2. Clone repos with Ctrl+Shift+P -> Git: Clone"
  echo "  3. Recommended local repo folder: ${projects_dir}"
  echo "  4. Open a repo and use the Source Control panel to commit and push"

  if confirm "Launch VS Code now?" "Y"; then
    if command_exists code; then
      if [[ -d "$projects_dir" ]]; then
        run_as_user code "$projects_dir" >>"$LOG_FILE" 2>&1 &
      else
        run_as_user code >>"$LOG_FILE" 2>&1 &
      fi
      success "VS Code launched"
    else
      warn "VS Code could not be launched because the code command is unavailable"
      record_failure "vscode-launch"
    fi
  fi
}


# ---------- Section 17 ----------
section_17_timeshift_snapshot() {
  show_section_header "Section 17 - Timeshift Snapshot / Rollback"

  local snapshot_tag snapshot_comment delete_count existing_count
  local timeshift_cmd="timeshift"

  if ! command_exists timeshift; then
    if confirm "Timeshift is not installed. Install it now?" "Y"; then
      if pkg_install timeshift; then
        success "Installed Timeshift"
      else
        error "Failed to install Timeshift"
        record_failure "timeshift-install"
        return 1
      fi
    else
      warn "Skipped Timeshift installation."
      return 0
    fi
  fi

  info "Checking Timeshift status..."
  sudo timeshift --check >>"$LOG_FILE" 2>&1 || true

  echo
  info "Existing Timeshift snapshots:"
  if sudo timeshift --list 2>&1 | tee -a "$LOG_FILE"; then
    :
  else
    warn "Could not list Timeshift snapshots. Timeshift may not be fully configured yet."
  fi

  existing_count="$(sudo timeshift --list 2>/dev/null | grep -Ec '^>[[:space:]]|^[[:space:]]*[0-9]{4}-' || true)"
  info "Detected snapshot count: ${existing_count:-0}"

  if confirm "Create a new Timeshift snapshot now?" "Y"; then
    read -r -p "Snapshot tag [O]=On-demand or [B]=Boot (default O): " snapshot_tag
    snapshot_tag="${snapshot_tag:-O}"
    case "${snapshot_tag^^}" in
      B) snapshot_tag="B" ;;
      *) snapshot_tag="O" ;;
    esac

    read -r -p "Snapshot comment [Workstation setup manual snapshot]: " snapshot_comment
    snapshot_comment="${snapshot_comment:-Workstation setup manual snapshot}"

    info "Creating Timeshift snapshot. This can take a while..."
    if sudo timeshift --create --comments "$snapshot_comment" --tags "$snapshot_tag" 2>&1 | tee -a "$LOG_FILE"; then
      success "Timeshift snapshot created"
    else
      error "Failed to create Timeshift snapshot"
      record_failure "timeshift-create"
      return 1
    fi
  else
    warn "Skipped snapshot creation."
  fi

  if confirm "Show Timeshift snapshots again now?" "Y"; then
    sudo timeshift --list 2>&1 | tee -a "$LOG_FILE" || true
  fi

  if confirm "Delete older snapshots by count?" "N"; then
    read -r -p "How many oldest snapshots would you like to delete? [0]: " delete_count
    delete_count="${delete_count:-0}"
    if [[ "$delete_count" =~ ^[0-9]+$ ]] && (( delete_count > 0 )); then
      info "Deleting ${delete_count} old snapshot(s)..."
      if sudo timeshift --delete --snapshot-device "$(sudo timeshift --list 2>/dev/null | awk -F': ' '/Device :/{print $2; exit}')" >>"$LOG_FILE" 2>&1; then
        warn "Timeshift delete-by-count is not directly supported in all builds. Manual cleanup may still be required."
      else
        warn "Automated Timeshift cleanup by count is not supported on this system build."
      fi
    else
      info "No snapshots selected for deletion."
    fi
  fi

  echo
  warn "To restore a snapshot later, boot into a safe environment if needed and run: sudo timeshift --restore"
  success "Timeshift snapshot / rollback section completed."
}

# ---------- Section 18 ----------
section_18_mounts_and_fstab() {
  show_section_header "Section 18 - NFS/SMB Mounts and fstab Validation"

  local mount_pkgs=(nfs-common cifs-utils)
  local mount_type="" remote_path="" mount_point="" options="" fstab_entry="" username="" password_file=""
  local smb_version="3.0"

  info "Installing mount helper packages..."
  if pkg_install "${mount_pkgs[@]}"; then
    success "Mount helper packages are installed"
  else
    warn "Some mount helper packages may not have installed cleanly"
    record_failure "mount-helper-packages"
  fi

  if [[ -f /etc/fstab ]]; then
    sudo cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)" >>"$LOG_FILE" 2>&1 || true
    success "Backed up /etc/fstab"
  fi

  echo
  info "Current /etc/fstab entries:"
  sudo grep -Ev '^[[:space:]]*#|^[[:space:]]*$' /etc/fstab 2>/dev/null | tee -a "$LOG_FILE" || true

  if ! confirm "Create and test a new network mount now?" "N"; then
    if confirm "Run fstab validation only with mount -a?" "Y"; then
      if sudo mount -a 2>&1 | tee -a "$LOG_FILE"; then
        success "mount -a completed"
      else
        warn "mount -a reported errors. Review the output above."
        record_failure "fstab-validation"
        return 1
      fi
    fi
    return 0
  fi

  read -r -p "Choose mount type [nfs/smb] (default nfs): " mount_type
  mount_type="${mount_type:-nfs}"

  if [[ "$mount_type" == "smb" ]]; then
    read -r -p "Enter SMB share (example //server/share): " remote_path
    read -r -p "Enter local mount point (example /mnt/share): " mount_point
    read -r -p "SMB username: " username
    password_file="${STARTING_HOME}/.smbcredentials_$(date +%Y%m%d%H%M%S)"
    read -r -s -p "SMB password: " smb_password
    echo
    if [[ -z "${remote_path:-}" || -z "${mount_point:-}" || -z "${username:-}" ]]; then
      error "SMB setup requires share path, mount point, and username."
      record_failure "smb-input"
      return 1
    fi
    printf 'username=%s\npassword=%s\n' "$username" "$smb_password" | run_as_user tee "$password_file" >/dev/null
    chmod 600 "$password_file"
    fix_user_file_ownership "$password_file"
    read -r -p "SMB version to use [3.0]: " smb_version
    smb_version="${smb_version:-3.0}"
    options="credentials=${password_file},iocharset=utf8,uid=$(id -u "$STARTING_USER"),gid=$(id -g "$STARTING_USER"),vers=${smb_version},nofail,x-systemd.automount"
    fstab_entry="${remote_path} ${mount_point} cifs ${options} 0 0"
    sudo mkdir -p "$mount_point"
    info "Testing SMB mount..."
    if sudo mount -t cifs "$remote_path" "$mount_point" -o "$options" 2>&1 | tee -a "$LOG_FILE"; then
      success "SMB mount test succeeded"
      sudo umount "$mount_point" >>"$LOG_FILE" 2>&1 || true
    else
      error "SMB mount test failed"
      record_failure "smb-mount-test"
      return 1
    fi
  else
    read -r -p "Enter NFS export (example 10.0.0.49:/mnt/data): " remote_path
    read -r -p "Enter local mount point (example /mnt/data): " mount_point
    read -r -p "NFS mount options [rw,noatime,hard,intr,nofail,x-systemd.automount]: " options
    options="${options:-rw,noatime,hard,intr,nofail,x-systemd.automount}"
    if [[ -z "${remote_path:-}" || -z "${mount_point:-}" ]]; then
      error "NFS setup requires export path and mount point."
      record_failure "nfs-input"
      return 1
    fi
    fstab_entry="${remote_path} ${mount_point} nfs ${options} 0 0"
    sudo mkdir -p "$mount_point"
    info "Testing NFS mount..."
    if sudo mount -t nfs -o "$options" "$remote_path" "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
      success "NFS mount test succeeded"
      sudo umount "$mount_point" >>"$LOG_FILE" 2>&1 || true
    else
      error "NFS mount test failed"
      record_failure "nfs-mount-test"
      return 1
    fi
  fi

  echo
  info "Proposed fstab entry:"
  echo "  $fstab_entry"

  if confirm "Append this entry to /etc/fstab?" "Y"; then
    if grep -Fqx "$fstab_entry" /etc/fstab 2>/dev/null; then
      success "That exact /etc/fstab entry already exists"
    else
      echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
      success "Appended entry to /etc/fstab"
    fi

    info "Validating /etc/fstab with mount -a..."
    if sudo mount -a 2>&1 | tee -a "$LOG_FILE"; then
      success "fstab validation succeeded"
    else
      error "fstab validation failed"
      record_failure "fstab-append-validate"
      warn "Review /etc/fstab and remove or correct the new entry if needed."
      return 1
    fi
  else
    warn "Skipped editing /etc/fstab. Test mount only was completed."
  fi
}

# ---------- Section 19 ----------
section_19_dev_tools_profile() {
  show_section_header "Section 19 - Dev Tools Profile"

  local base_pkgs=(
    build-essential
    python3
    python3-pip
    python3-venv
    pipx
    jq
    yq
    git-lfs
    gh
    curl
    wget
    unzip
    zip
    ripgrep
    fd-find
    tmux
    shellcheck
  )
  local node_pkgs=(nodejs npm)
  local extra_pkgs=()
  local installed_any=false

  info "Installing base development tool packages..."
  if pkg_install "${base_pkgs[@]}"; then
    success "Base development tool packages installed"
    installed_any=true
  else
    warn "Some base development tool packages may not have installed cleanly"
    record_failure "dev-tools-base"
  fi

  if command_exists pipx; then
    run_as_user pipx ensurepath >>"$LOG_FILE" 2>&1 || true
    success "pipx path setup attempted"
  fi

  if confirm "Install Node.js and npm from distro repositories?" "Y"; then
    if pkg_install "${node_pkgs[@]}"; then
      success "Installed Node.js and npm"
      installed_any=true
    else
      warn "Node.js/npm install reported errors"
      record_failure "nodejs-npm"
    fi
  fi

  if confirm "Install Ansible?" "Y"; then
    extra_pkgs+=(ansible)
  fi

  if confirm "Install Terraform from distro repositories if available?" "N"; then
    extra_pkgs+=(terraform)
  fi

  if confirm "Install kubectl from distro repositories if available?" "N"; then
    extra_pkgs+=(kubectl)
  fi

  if ((${#extra_pkgs[@]} > 0)); then
    if pkg_install "${extra_pkgs[@]}"; then
      success "Installed selected extra development tools"
      installed_any=true
    else
      warn "One or more selected extra development tools did not install"
      record_failure "dev-tools-extra"
    fi
  fi

  echo
  info "Development tool versions:"
  command -v python3 >/dev/null 2>&1 && python3 --version | tee -a "$LOG_FILE"
  command -v pip3 >/dev/null 2>&1 && pip3 --version | tee -a "$LOG_FILE"
  command -v pipx >/dev/null 2>&1 && pipx --version | tee -a "$LOG_FILE"
  command -v node >/dev/null 2>&1 && node --version | tee -a "$LOG_FILE"
  command -v npm >/dev/null 2>&1 && npm --version | tee -a "$LOG_FILE"
  command -v ansible >/dev/null 2>&1 && ansible --version | head -n1 | tee -a "$LOG_FILE"
  command -v terraform >/dev/null 2>&1 && terraform version | head -n1 | tee -a "$LOG_FILE"
  command -v kubectl >/dev/null 2>&1 && kubectl version --client=true --output=yaml | head -n3 | tee -a "$LOG_FILE"
  command -v gh >/dev/null 2>&1 && gh --version | head -n1 | tee -a "$LOG_FILE"

  if $installed_any; then
    success "Dev tools profile section completed."
  else
    warn "No new dev tools were installed."
  fi
}

# ---------- Section 20 ----------
section_20_system_diagnostics_bundle() {
  show_section_header "Section 20 - System Diagnostics Bundle"

  local ts bundle_dir archive_file
  ts="$(date +%Y%m%d_%H%M%S)"
  bundle_dir="${STARTING_HOME}/Projects/system_diagnostics_${ts}"
  archive_file="${STARTING_HOME}/Projects/system_diagnostics_${ts}.tar.gz"

  ensure_dir "${STARTING_HOME}/Projects"
  mkdir -p "$bundle_dir"

  info "Collecting system diagnostics into: $bundle_dir"

  {
    echo "Generated: $(date)"
    echo "User: $STARTING_USER"
    echo "Home: $STARTING_HOME"
    echo "OS: $OS_PRETTY_NAME"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $ARCH"
  } > "${bundle_dir}/summary.txt"

  uname -a > "${bundle_dir}/uname.txt" 2>&1 || true
  lsblk -f > "${bundle_dir}/lsblk.txt" 2>&1 || true
  df -hT > "${bundle_dir}/df_hT.txt" 2>&1 || true
  free -h > "${bundle_dir}/free_h.txt" 2>&1 || true
  ip addr > "${bundle_dir}/ip_addr.txt" 2>&1 || true
  ip route > "${bundle_dir}/ip_route.txt" 2>&1 || true
  resolvectl status > "${bundle_dir}/resolvectl_status.txt" 2>&1 || true
  systemctl --failed > "${bundle_dir}/systemctl_failed.txt" 2>&1 || true
  journalctl -p 3 -xb > "${bundle_dir}/journal_errors_boot.txt" 2>&1 || true
  dpkg -l > "${bundle_dir}/dpkg_l.txt" 2>&1 || true
  apt-cache policy > "${bundle_dir}/apt_cache_policy.txt" 2>&1 || true
  sudo ufw status verbose > "${bundle_dir}/ufw_status.txt" 2>&1 || true
  sudo ss -tulpn > "${bundle_dir}/ss_tulpn.txt" 2>&1 || true
  cp "$LOG_FILE" "${bundle_dir}/workstation_setup.log" 2>/dev/null || true
  [[ -f "$REPORT_FILE" ]] && cp "$REPORT_FILE" "${bundle_dir}/workstation_setup_report.txt" 2>/dev/null || true
  [[ -f "$FAILED_FILE" ]] && cp "$FAILED_FILE" "${bundle_dir}/workstation_failed_items.txt" 2>/dev/null || true

  if command_exists docker; then
    docker version > "${bundle_dir}/docker_version.txt" 2>&1 || true
    docker info > "${bundle_dir}/docker_info.txt" 2>&1 || true
    docker ps -a > "${bundle_dir}/docker_ps_a.txt" 2>&1 || true
  fi

  if command_exists flatpak; then
    flatpak list --system > "${bundle_dir}/flatpak_list_system.txt" 2>&1 || true
  fi

  if command_exists timeshift; then
    sudo timeshift --list > "${bundle_dir}/timeshift_list.txt" 2>&1 || true
  fi

  if command_exists code; then
    code --version > "${bundle_dir}/code_version.txt" 2>&1 || true
  fi

  if confirm "Create a compressed tar.gz archive of the diagnostics bundle?" "Y"; then
    tar -czf "$archive_file" -C "${STARTING_HOME}/Projects" "$(basename "$bundle_dir")" 2>>"$LOG_FILE" \
      && success "Diagnostics archive created: $archive_file" \
      || warn "Could not create diagnostics archive"
  fi

  fix_user_file_ownership "$bundle_dir"
  [[ -f "$archive_file" ]] && fix_user_file_ownership "$archive_file"

  success "Diagnostics bundle created at: $bundle_dir"
}

# ---------- Section 21 ----------
section_21_backup_sync_helpers() {
  show_section_header "Section 21 - Backup / Sync Helpers"

  local source_dir target_dir exclude_file helper_script dry_run_flag archive_mode rsync_opts
  helper_script="${STARTING_HOME}/Projects/backup_sync_helper.sh"
  exclude_file="${STARTING_HOME}/Projects/rsync_excludes.txt"

  ensure_dir "${STARTING_HOME}/Projects"

  if ! command_exists rsync; then
    if confirm "rsync is not installed. Install it now?" "Y"; then
      if pkg_install rsync; then
        success "Installed rsync"
      else
        error "Failed to install rsync"
        record_failure "rsync-install"
        return 1
      fi
    else
      warn "Skipped rsync installation."
      return 0
    fi
  fi

  read -r -p "Source directory to back up [${STARTING_HOME}/Projects]: " source_dir
  source_dir="${source_dir:-${STARTING_HOME}/Projects}"
  read -r -p "Target directory [example /mnt/backup/projects]: " target_dir

  if [[ -z "$target_dir" ]]; then
    error "A target directory is required."
    record_failure "backup-target-missing"
    return 1
  fi

  if [[ ! -d "$source_dir" ]]; then
    error "Source directory does not exist: $source_dir"
    record_failure "backup-source-missing"
    return 1
  fi

  if [[ ! -d "$target_dir" ]]; then
    if confirm "Target directory does not exist. Create it now?" "Y"; then
      sudo mkdir -p "$target_dir" || {
        error "Could not create target directory"
        record_failure "backup-target-create"
        return 1
      }
    else
      warn "Cannot continue without a target directory."
      return 1
    fi
  fi

  if [[ ! -f "$exclude_file" ]]; then
    cat > "$exclude_file" <<'EOF'
# One exclude pattern per line
*.tmp
.cache/
node_modules/
.venv/
EOF
    fix_user_file_ownership "$exclude_file"
    success "Created default rsync exclude file: $exclude_file"
  fi

  if confirm "Use archive mode (-a)?" "Y"; then
    archive_mode="-a"
  else
    archive_mode="-rlt"
  fi

  if confirm "Do a dry run first?" "Y"; then
    dry_run_flag="--dry-run"
  else
    dry_run_flag=""
  fi

  rsync_opts="${archive_mode}h --info=progress2 --delete --partial --inplace --exclude-from=${exclude_file}"

  echo
  info "Planned rsync command:"
  echo "  rsync ${rsync_opts} ${dry_run_flag} \"${source_dir}/\" \"${target_dir}/\""

  if confirm "Run this rsync job now?" "Y"; then
    if rsync ${rsync_opts} ${dry_run_flag} "${source_dir}/" "${target_dir}/" 2>&1 | tee -a "$LOG_FILE"; then
      success "rsync job completed"
    else
      error "rsync job reported errors"
      record_failure "rsync-job"
      return 1
    fi
  else
    warn "Skipped running rsync job."
  fi

  cat > "$helper_script" <<EOF
#!/usr/bin/env bash
set -u
set -o pipefail

SOURCE_DIR="$(printf '%q' "$source_dir")"
TARGET_DIR="$(printf '%q' "$target_dir")"
EXCLUDE_FILE="$(printf '%q' "$exclude_file")"

rsync ${rsync_opts} "\${1:---dry-run}" "\${SOURCE_DIR}/" "\${TARGET_DIR}/"
EOF
  chmod +x "$helper_script"
  fix_user_file_ownership "$helper_script"

  success "Backup helper script saved to: $helper_script"
}

# ---------- Section 22 ----------
section_22_validation_report() {

  show_section_header "Section 22 - Validation Report"

  detect_os

  {
    echo "Workstation Setup Report"
    echo "Generated: $(date)"
    echo
    echo "System"
    echo "------"
    echo "User: $STARTING_USER"
    echo "Home: $STARTING_HOME"
    echo "OS: $OS_PRETTY_NAME"
    echo "Architecture: $ARCH"
    echo "APT codename: $APT_CODENAME"
    echo "Docker distro: $DOCKER_DISTRO"
    echo "Java package target: $JAVA_PKG"
    echo

    echo "Command Checks"
echo "--------------"
for cmd in nala apt-get zsh flatpak docker brave-browser 1password winboat code ssh; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd: present ($(command -v "$cmd"))"
  else
    echo "$cmd: not found"
  fi
done

if dpkg -s ufw >/dev/null 2>&1; then
  echo "ufw: installed"
else
  echo "ufw: not installed"
fi

if command -v sshd >/dev/null 2>&1; then
  echo "sshd: present ($(command -v sshd))"
elif [[ -x /usr/sbin/sshd ]]; then
  echo "sshd: present (/usr/sbin/sshd)"
else
  echo "sshd: not found"
fi
echo

    echo "APT Packages"
    echo "------------"
    for pkg in zsh tlp ufw gufw timeshift okular pdfarranger kodi 1password nfs-common openssh-server openssh-client openssh-sftp-server; do
      if pkg_installed "$pkg"; then
        echo "$pkg: installed"
      else
        echo "$pkg: not installed"
      fi
    done
    echo

    echo "Flatpak Apps"
    echo "------------"
    if command_exists flatpak; then
      sudo flatpak list --system --app --columns=application,name 2>/dev/null || true
    else
      echo "flatpak not installed"
    fi
    echo

    echo "Docker Repo"
    echo "-----------"
    if [[ -f /etc/apt/sources.list.d/docker.sources ]]; then
      cat /etc/apt/sources.list.d/docker.sources
    else
      echo "docker.sources not present"
    fi
    echo

    echo "Firewall"
    echo "--------"
    sudo ufw status verbose 2>/dev/null || echo "ufw status unavailable"
    echo

    echo "Failed Items"
    echo "------------"
    if [[ -s "$FAILED_FILE" ]]; then
      sort -u "$FAILED_FILE"
    else
      echo "None recorded."
    fi
    echo

    echo "SSH"
    echo "---"
    systemctl is-enabled ssh 2>/dev/null || echo "ssh enabled status unavailable"
    systemctl is-active ssh 2>/dev/null || echo "ssh active status unavailable"
    sudo ss -tulpn 2>/dev/null | grep -E '(:22\s|sshd)' || echo "ssh listener not confirmed"
    echo "Suggested SSH command:"
    if hostname -I 2>/dev/null | awk '{print $1}' | grep -q .; then
      echo "ssh ${STARTING_USER}@$(hostname -I | awk '{print $1}')"
    else
      echo "IP address unavailable"
    fi
    echo

    echo "Notes"
    echo "-----"
    echo "- If Docker was installed and group membership was changed, log out/in before testing docker without sudo."
    echo "- If terminal font does not change, check your terminal profile font override."
    echo "- If Microsoft fonts failed, enable the needed optional repository components for your distro and rerun Section 5."
    echo "- WinBoat requires KVM support, Docker, Docker Compose v2, FreeRDP, and a working docker group setup."
    echo "- OpenSSH Server should show enabled and active when Section 16 completes successfully."
    echo "- Timeshift snapshots, diagnostics bundles, and backup helpers are available in Sections 17 through 21."
    echo "- If SSH is running but remote login fails, confirm UFW allows 22/tcp."
  } > "$REPORT_FILE"

  success "Report written to: $REPORT_FILE"
  echo
  cat "$REPORT_FILE"
}

# ---------- Menu ----------
run_all_sections() {
  if confirm "Run Section 0 - Pre-Flight Checks?" "Y"; then run_section 0 section_0_preflight; fi
  if confirm "Run Section 1 - System Update & Upgrade?" "Y"; then run_section 1 section_1_system_update; fi
  if confirm "Run Section 2 - Core Packages and Vendor Apps?" "Y"; then run_section 2 section_2_core_and_vendor_apps; fi
  if confirm "Run Section 3 - Flatpak Applications?" "Y"; then run_section 3 section_3_flatpak_apps; fi
  if confirm "Run Section 4 - Docker Repo Setup / Validation?" "Y"; then run_section 4 section_4_docker_repo; fi
  if confirm "Run Section 5 - Fonts Installation?" "Y"; then run_section 5 section_5_install_fonts; fi
  if confirm "Run Section 6 - Set Monospace Font?" "Y"; then run_section 6 section_6_set_monospace_font; fi
  if confirm "Run Section 7 - ZSH Default Shell Setup?" "Y"; then run_section 7 section_7_zsh_default_shell; fi
  if confirm "Run Section 8 - Oh-My-Zsh + Powerlevel10k + Plugins?" "Y"; then run_section 8 section_8_oh_my_zsh_and_plugins; fi
  if confirm "Run Section 9 - Date/Time and Privacy Preferences?" "Y"; then run_section 9 section_9_date_time; fi
  if confirm "Run Section 10 - Firewall (UFW)?" "Y"; then run_section 10 section_10_firewall; fi
  if confirm "Run Section 11 - Nemo File Manager Preferences?" "Y"; then run_section 11 section_11_nemo_preferences; fi
  if confirm "Run Section 12 - Nemo Enhancements?" "Y"; then run_section 12 section_12_nemo_enhancements; fi
  if confirm "Run Section 13 - WinBoat?" "Y"; then run_section 13 section_13_winboat; fi
  if confirm "Run Section 14 - JDownloader?" "Y"; then run_section 14 section_14_jdownloader; fi
  if confirm "Run Section 15 - VS Code + GitHub Setup?" "Y"; then run_section 15 section_15_vscode; fi
  if confirm "Run Section 16 - OpenSSH Server?" "Y"; then run_section 16 section_16_openssh_server; fi
  if confirm "Run Section 17 - Timeshift Snapshot / Rollback?" "Y"; then run_section 17 section_17_timeshift_snapshot; fi
  if confirm "Run Section 18 - NFS/SMB Mounts and fstab Validation?" "Y"; then run_section 18 section_18_mounts_and_fstab; fi
  if confirm "Run Section 19 - Dev Tools Profile?" "Y"; then run_section 19 section_19_dev_tools_profile; fi
  if confirm "Run Section 20 - System Diagnostics Bundle?" "Y"; then run_section 20 section_20_system_diagnostics_bundle; fi
  if confirm "Run Section 21 - Backup / Sync Helpers?" "Y"; then run_section 21 section_21_backup_sync_helpers; fi
  if confirm "Run Section 22 - Validation Report?" "Y"; then run_section 22 section_22_validation_report; fi
}

show_menu() {
  clear
  echo -e "${BOLD}${CYAN}LMDE / Ubuntu Interactive Setup Script${NC}"
  echo -e "${CYAN}Log file   : ${LOG_FILE}${NC}"
  echo -e "${CYAN}Report file: ${REPORT_FILE}${NC}"
  echo
  echo -e "${GREEN}Green${NC} = completed   ${RED}Red${NC} = failed   ${YELLOW}Yellow${NC} = running"
  echo

  format_menu_item 0  "Section 0  - Pre-Flight Checks"
  format_menu_item 1  "Section 1  - System Update & Upgrade"
  format_menu_item 2  "Section 2  - Core Packages and Vendor Apps"
  format_menu_item 3  "Section 3  - Flatpak Applications"
  format_menu_item 4  "Section 4  - Docker Repo Setup / Validation"
  format_menu_item 5  "Section 5  - Fonts Installation"
  format_menu_item 6  "Section 6  - Set Monospace Font"
  format_menu_item 7  "Section 7  - ZSH Default Shell Setup"
  format_menu_item 8  "Section 8  - Oh-My-Zsh + Powerlevel10k + Plugins"
  format_menu_item 9  "Section 9  - Date/Time and Privacy Preferences"
  format_menu_item 10 "Section 10 - Firewall (UFW)"
  format_menu_item 11 "Section 11 - Nemo File Manager Preferences"
  format_menu_item 12 "Section 12 - Nemo Enhancements"
  format_menu_item 13 "Section 13 - WinBoat"
  format_menu_item 14 "Section 14 - JDownloader"
  format_menu_item 15 "Section 15 - VS Code + GitHub Setup"
  format_menu_item 16 "Section 16 - OpenSSH Server"
  format_menu_item 17 "Section 17 - Timeshift Snapshot / Rollback"
  format_menu_item 18 "Section 18 - NFS/SMB Mounts and fstab Validation"
  format_menu_item 19 "Section 19 - Dev Tools Profile"
  format_menu_item 20 "Section 20 - System Diagnostics Bundle"
  format_menu_item 21 "Section 21 - Backup / Sync Helpers"
  format_menu_item 22 "Section 22 - Validation Report"
  echo " 23) Run ALL sections (prompt before each)"
  echo " 24) Exit"
  echo
}

main() {
  require_sudo
  detect_os
  ensure_dir "$DOWNLOAD_DIR"
  init_section_status
  load_section_status

  info "Starting $SCRIPT_NAME as user: $STARTING_USER"
  info "Home detected: $STARTING_HOME"
  info "Log file: $LOG_FILE"

  while true; do
    show_menu
    read -r -p "Select an option [0-24]: " choice

    case "$choice" in
      0)  run_section 0 section_0_preflight; press_enter ;;
      1)  run_section 1 section_1_system_update; press_enter ;;
      2)  run_section 2 section_2_core_and_vendor_apps; press_enter ;;
      3)  run_section 3 section_3_flatpak_apps; press_enter ;;
      4)  run_section 4 section_4_docker_repo; press_enter ;;
      5)  run_section 5 section_5_install_fonts; press_enter ;;
      6)  run_section 6 section_6_set_monospace_font; press_enter ;;
      7)  run_section 7 section_7_zsh_default_shell; press_enter ;;
      8)  run_section 8 section_8_oh_my_zsh_and_plugins; press_enter ;;
      9)  run_section 9 section_9_date_time; press_enter ;;
      10) run_section 10 section_10_firewall; press_enter ;;
      11) run_section 11 section_11_nemo_preferences; press_enter ;;
      12) run_section 12 section_12_nemo_enhancements; press_enter ;;
      13) run_section 13 section_13_winboat; press_enter ;;
      14) run_section 14 section_14_jdownloader; press_enter ;;
      15) run_section 15 section_15_vscode; press_enter ;;
      16) run_section 16 section_16_openssh_server; press_enter ;;
      17) run_section 17 section_17_timeshift_snapshot; press_enter ;;
      18) run_section 18 section_18_mounts_and_fstab; press_enter ;;
      19) run_section 19 section_19_dev_tools_profile; press_enter ;;
      20) run_section 20 section_20_system_diagnostics_bundle; press_enter ;;
      21) run_section 21 section_21_backup_sync_helpers; press_enter ;;
      22) run_section 22 section_22_validation_report; press_enter ;;
      23) run_all_sections; press_enter ;;
      24) success "Exiting."; exit 0 ;;
      *)  warn "Invalid selection."; press_enter ;;
    esac
  done
}

main "$@"
