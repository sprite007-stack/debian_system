#!/usr/bin/env bash
set -u
set -o pipefail
set -E

###############################################################################
# LMDE / Ubuntu / Zorin Interactive Workstation Setup Script v48
# - Supports LMDE 6/7, Ubuntu, and Zorin OS 18+
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
FAVORITES_FILE="${HOME}/.workstation_setup_favorites"
REQUIRED_FAILED_FILE="${HOME}/workstation_failed_required_items.txt"
OPTIONAL_FAILED_FILE="${HOME}/workstation_failed_optional_items.txt"
TRACE_FILE="${HOME}/workstation_setup_trace.log"
DOWNLOAD_DIR="${HOME}/Downloads"

DRY_RUN=false
NON_INTERACTIVE=false
export DEBIAN_FRONTEND=noninteractive
APT_NONINTERACTIVE_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
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
  printf '[WARN] Desktop app and user-settings sections are running with STARTING_USER=root.\n'
  printf '[WARN] For desktop apps and per-user settings, launch this script with sudo from your normal user session.\n'
fi

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
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
IS_ZORIN=false
IS_SUPPORTED_OS=false
DISTRO_FAMILY="unknown"
DISTRO_NAME="unknown"
JAVA_PKG="default-jre"

declare -A SECTION_STATUS

declare -a SECTION_IDS=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)
declare -A SECTION_LABELS=(
  [0]="Pre-Flight Checks"
  [1]="System Update & Upgrade"
  [2]="Core Packages and Vendor Apps"
  [3]="Flatpak Applications"
  [4]="Docker Repo Setup / Validation"
  [5]="Fonts Installation"
  [6]="Set Monospace Font"
  [7]="ZSH Default Shell Setup"
  [8]="Oh-My-Zsh + Powerlevel10k + Plugins"
  [9]="Date/Time and Privacy Preferences"
  [10]="Firewall (UFW)"
  [11]="Nemo File Manager Preferences"
  [12]="Nemo Enhancements"
  [13]="WinBoat"
  [14]="JDownloader"
  [15]="VS Code + GitHub Setup"
  [16]="OpenSSH Server"
  [17]="Timeshift Snapshot / Rollback"
  [18]="NFS/SMB Mounts and fstab Validation"
  [19]="Developer CLI Tools"
  [20]="System Diagnostics Bundle"
  [21]="Validation Report"
  [22]="Ansible Automation Setup"
  [23]="Terraform Setup"
  [24]="Proxmox Toolkit"
  [25]="Synology Toolkit"
  [26]="Home Lab Docker Stack Installer"
  [27]="Network Engineer Toolkit"
  [28]="Logging / Diagnostics Toolkit"
  [29]="Media / Download Power Toolkit"
  [30]="Laptop Brightness / Backlight Toolkit"
  [31]="Desktop Environment Awareness / Tweaks"
  [32]="Diagnostics Dashboard / Auto-Fix"
)
declare -A SECTION_FUNCS=(
  [0]="section_0_preflight"
  [1]="section_1_system_update"
  [2]="section_2_core_and_vendor_apps"
  [3]="section_3_flatpak_apps"
  [4]="section_4_docker_repo"
  [5]="section_5_install_fonts"
  [6]="section_6_set_monospace_font"
  [7]="section_7_zsh_default_shell"
  [8]="section_8_oh_my_zsh_and_plugins"
  [9]="section_9_date_time"
  [10]="section_10_firewall"
  [11]="section_11_nemo_preferences"
  [12]="section_12_nemo_enhancements"
  [13]="section_13_winboat"
  [14]="section_14_jdownloader"
  [15]="section_15_vscode"
  [16]="section_16_openssh_server"
  [17]="section_17_timeshift_snapshot"
  [18]="section_18_mounts_and_fstab"
  [19]="section_19_dev_tools_profile"
  [20]="section_20_system_diagnostics_bundle"
  [21]="section_21_validation_report"
  [22]="section_22_ansible_setup"
  [23]="section_23_terraform_setup"
  [24]="section_24_proxmox_toolkit"
  [25]="section_25_synology_toolkit"
  [26]="section_26_docker_stack_installer"
  [27]="section_27_network_engineer_toolkit"
  [28]="section_28_logging_diagnostics_toolkit"
  [29]="section_29_media_download_power_toolkit"
  [30]="section_30_laptop_brightness_backlight_toolkit"
  [31]="section_31_desktop_environment_awareness"
  [32]="section_32_diagnostics_dashboard_autofix"
)
declare -A SECTION_GROUPS=(
  [0]="health"
  [1]="core"
  [2]="core"
  [3]="core"
  [4]="core"
  [5]="terminal"
  [6]="terminal"
  [7]="terminal"
  [8]="terminal"
  [9]="terminal"
  [10]="health"
  [11]="gui"
  [12]="gui"
  [13]="apps"
  [14]="apps"
  [15]="apps"
  [16]="health"
  [17]="health"
  [18]="storage"
  [19]="automation"
  [20]="health"
  [21]="health"
  [22]="automation"
  [23]="automation"
  [24]="infrastructure"
  [25]="storage"
  [26]="infrastructure"
  [27]="infrastructure"
  [28]="health"
  [29]="apps"
  [30]="gui"
  [31]="gui"
  [32]="health"
)
declare -A GROUP_LABELS=(
  [core]="Base System Setup"
  [terminal]="Terminal UI Enhancements"
  [gui]="GUI Enhancements"
  [apps]="Applications and Productivity"
  [health]="System Health / Security Check"
  [storage]="Storage / Mounting"
  [automation]="System External Automation"
  [infrastructure]="Full Infrastructure Toolkit"
)

# ---------- Menu Category Helpers ----------
# These helpers make the "Show all sections" view easier for new users.
# Each section already belongs to a SECTION_GROUPS entry. We reuse that
# registry data to print a readable category label beside every section.
group_color() {
  local group="$1"
  case "$group" in
    core)           printf '%b' "$CYAN" ;;
    terminal)       printf '%b' "$GREEN" ;;
    gui)            printf '%b' "$MAGENTA" ;;
    apps)           printf '%b' "$YELLOW" ;;
    health)         printf '%b' "$RED" ;;
    storage)        printf '%b' "$WHITE" ;;
    automation)     printf '%b' "$BLUE" ;;
    infrastructure) printf '%b' "$BOLD$CYAN" ;;
    *)              printf '%b' "$NC" ;;
  esac
}

print_section_with_category() {
  local sid="$1"
  local group="${SECTION_GROUPS[$sid]:-unknown}"
  local category="${GROUP_LABELS[$group]:-Misc}"
  local status="${SECTION_STATUS[$sid]:-pending}"
  local category_color
  category_color="$(group_color "$group")"

  case "$status" in
    complete)
      printf "${GREEN}%3s)${NC} %b[%-32s]${NC} %s\n" "$sid" "$category_color" "$category" "${SECTION_LABELS[$sid]}"
      ;;
    failed)
      printf "${RED}%3s)${NC} %b[%-32s]${NC} %s\n" "$sid" "$category_color" "$category" "${SECTION_LABELS[$sid]}"
      ;;
    running)
      printf "${YELLOW}%3s)${NC} %b[%-32s]${NC} %s\n" "$sid" "$category_color" "$category" "${SECTION_LABELS[$sid]}"
      ;;
    *)
      printf "%3s) %b[%-32s]${NC} %s\n" "$sid" "$category_color" "$category" "${SECTION_LABELS[$sid]}"
      ;;
  esac
}

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
touch "$TRACE_FILE"
: > "$FAILED_FILE"
: > "$REQUIRED_FAILED_FILE"
: > "$OPTIONAL_FAILED_FILE"

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
  local severity="${2:-required}"
  echo "$item" >> "$FAILED_FILE"

  if [[ "$severity" == "optional" ]]; then
    echo "$item" >> "$OPTIONAL_FAILED_FILE"
  else
    echo "$item" >> "$REQUIRED_FAILED_FILE"
  fi
}

record_optional_failure() {
  local item="$1"
  record_failure "$item" "optional"
}

# ---------- Section Status ----------
init_section_status() {
  local i
  for i in "${SECTION_IDS[@]}"; do
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
  for i in "${SECTION_IDS[@]}"; do
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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      --non-interactive|--yes)
        NON_INTERACTIVE=true
        ;;
      -h|--help)
        cat <<EOF
Usage: $SCRIPT_NAME [--dry-run] [--non-interactive]

  --dry-run          Show commands that would run for config-changing steps
  --non-interactive  Use default answers for prompts and skip pause prompts
EOF
        exit 0
        ;;
      *)
        warn "Ignoring unknown argument: $1"
        ;;
    esac
    shift
  done
}

on_error_trap() {
  local exit_code="$1"
  local line_no="$2"
  local cmd="${3:-<unknown>}"
  printf '%s [TRACE] exit=%s line=%s cmd=%s
' "$(date '+%F %T')" "$exit_code" "$line_no" "$cmd" >> "$TRACE_FILE"
}

on_exit_trap() {
  local exit_code="$?"
  if [[ "$exit_code" -eq 0 ]]; then
    log "INFO" "Script exited cleanly."
  else
    log "ERROR" "Script exited with code $exit_code. Review $LOG_FILE and $TRACE_FILE."
  fi
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

# ------------------------------------------------------------
# Function: detect_desktop_environment
# Purpose:
#   Detect the active desktop/session and preferred file manager.
# Why this matters:
#   LMDE commonly uses Cinnamon/Nemo, Ubuntu often uses GNOME/Nautilus,
#   and Zorin uses a GNOME-based desktop with Zorin-specific polish.
#   Desktop tweak sections should adapt instead of forcing Nemo-only logic.
# ------------------------------------------------------------
detect_desktop_environment() {
  local current_desktop session_type
  current_desktop="$(run_as_user_shell 'printf %s "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"' 2>/dev/null || true)"
  session_type="$(run_as_user_shell 'printf %s "${XDG_SESSION_TYPE:-unknown}"' 2>/dev/null || true)"

  DISPLAY_SERVER="${session_type:-unknown}"

  case "${current_desktop,,}" in
    *cinnamon*) DESKTOP_ENVIRONMENT="cinnamon" ;;
    *zorin*)    DESKTOP_ENVIRONMENT="zorin-gnome" ;;
    *gnome*)    DESKTOP_ENVIRONMENT="gnome" ;;
    *xfce*)     DESKTOP_ENVIRONMENT="xfce" ;;
    *kde*|*plasma*) DESKTOP_ENVIRONMENT="kde" ;;
    *)          DESKTOP_ENVIRONMENT="${current_desktop:-unknown}" ;;
  esac

  if command_exists nemo; then
    FILE_MANAGER="nemo"
  elif command_exists nautilus; then
    FILE_MANAGER="nautilus"
  elif command_exists thunar; then
    FILE_MANAGER="thunar"
  elif command_exists dolphin; then
    FILE_MANAGER="dolphin"
  else
    FILE_MANAGER="unknown"
  fi
}

# ------------------------------------------------------------\n# Function: detect_package_managers
# Purpose:
#   Detect whether Snap and/or Flatpak are available.
# Why this matters:
#   LMDE/Debian generally works best with Flatpak for desktop apps, while
#   Ubuntu/Zorin systems may already have Snap available. Later sections can
#   use these flags to choose the most reliable install method.
# ------------------------------------------------------------
detect_package_managers() {
  if command_exists snap; then
    HAS_SNAP=true
  else
    HAS_SNAP=false
  fi

  if command_exists flatpak; then
    HAS_FLATPAK=true
  else
    HAS_FLATPAK=false
  fi

  if [[ "$DISTRO_FAMILY" == "ubuntu" && "$HAS_SNAP" == true ]]; then
    PREFERRED_APP_INSTALLER="snap"
  else
    PREFERRED_APP_INSTALLER="flatpak"
DESKTOP_ENVIRONMENT="unknown"
DISPLAY_SERVER="unknown"
FILE_MANAGER="unknown"
  fi
}

# ------------------------------------------------------------
# Function: distro_dns_package
# Purpose:
#   Return the correct DNS tools package for the current distro family.
# Why:
#   Debian/LMDE trixie commonly uses bind9-dnsutils, while Ubuntu/Zorin
#   systems typically still provide dnsutils as the expected package name.
# ------------------------------------------------------------
distro_dns_package() {
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    printf '%s\n' "bind9-dnsutils"
  else
    printf '%s\n' "dnsutils"
  fi
}

# ------------------------------------------------------------
# Function: ensure_snap_available
# Purpose:
#   Install/enable snapd only when the user explicitly chooses a Snap-based
#   install path. We do not force Snap on LMDE/Debian.
# ------------------------------------------------------------
ensure_snap_available() {
  if command_exists snap; then
    HAS_SNAP=true
    return 0
  fi

  if [[ "$DISTRO_FAMILY" != "ubuntu" ]]; then
    warn "Snap is not installed and is not the preferred path for this distro."
    return 1
  fi

  if confirm "Snap is not installed. Install snapd now?" "Y"; then
    if pkg_install snapd; then
      sudo systemctl enable --now snapd.socket >>"$LOG_FILE" 2>&1 || true
      HAS_SNAP=true
      success "snapd installed/enabled"
      return 0
    fi
  fi

  warn "Snap is unavailable."
  return 1
}


ensure_dir() {
  mkdir -p "$1"
}

preseed_noninteractive_apt() {
  info "Preseeding debconf for noninteractive package operations..."

  local selections=(
    "debconf debconf/frontend select Noninteractive"
    "keyboard-configuration keyboard-configuration/modelcode string pc105"
    "keyboard-configuration keyboard-configuration/layoutcode string us"
    "keyboard-configuration keyboard-configuration/variantcode string"
    "keyboard-configuration keyboard-configuration/optionscode string"
    "keyboard-configuration keyboard-configuration/store_defaults_in_debconf_db boolean true"
    "console-setup console-setup/charmap47 select UTF-8"
    "console-setup console-setup/codeset47 select Guess optimal character set"
    "console-setup console-setup/fontface47 select Fixed"
    "console-setup console-setup/fontsize-text47 select 16"
    "console-setup console-setup/use_system_font boolean true"
    "tzdata tzdata/Areas select Etc"
    "tzdata tzdata/Zones/Etc select UTC"
  )

  local entry
  for entry in "${selections[@]}"; do
    if $DRY_RUN; then
      info "[DRY-RUN] Would preseed: $entry"
    else
      printf '%s\n' "$entry" | sudo debconf-set-selections >>"$LOG_FILE" 2>&1 || true
    fi
  done

  success "Debconf preseed step completed"
}

detect_grub_install_disk() {
  local source="" pkname="" disk=""
  local probe_targets=(/boot / /)
  local target

  for target in /boot /; do
    source="$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)"
    [[ -n "$source" ]] || continue

    if [[ "$source" =~ ^/dev/ ]]; then
      pkname="$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1)"
      if [[ -n "$pkname" ]]; then
        disk="/dev/${pkname}"
        break
      fi

      pkname="$(basename "$source" | sed 's/p\?[0-9].*$//')"
      if [[ -n "$pkname" && -b "/dev/${pkname}" ]]; then
        disk="/dev/${pkname}"
        break
      fi
    fi
  done

  if [[ -z "$disk" ]] && command -v grub-probe >/dev/null 2>&1; then
    source="$(sudo grub-probe --target=device /boot 2>/dev/null || sudo grub-probe --target=device / 2>/dev/null || true)"
    if [[ "$source" =~ ^/dev/ ]]; then
      pkname="$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1)"
      if [[ -n "$pkname" ]]; then
        disk="/dev/${pkname}"
      fi
    fi
  fi

  if [[ -z "$disk" ]]; then
    disk="$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print "/dev/"$1; exit}')"
  fi

  [[ -n "$disk" ]] && printf '%s
' "$disk"
}

preseed_grub_pc() {
  local grub_disk=""
  grub_disk="$(detect_grub_install_disk)"

  if [[ -z "$grub_disk" ]]; then
    warn "Could not determine GRUB install device automatically. Skipping grub-pc preseed."
    return 1
  fi

  info "Preseeding grub-pc install device: $grub_disk"
  if $DRY_RUN; then
    info "[DRY-RUN] Would preseed grub-pc for $grub_disk"
    return 0
  fi

  while IFS= read -r line; do
    printf '%s
' "$line" | sudo debconf-set-selections >>"$LOG_FILE" 2>&1 || true
  done <<EOF
grub-pc grub-pc/install_devices multiselect $grub_disk
grub-pc grub-pc/install_devices_disks_changed multiselect $grub_disk
grub-pc grub-pc/install_devices_failed boolean false
grub-pc grub-pc/install_devices_empty boolean false
EOF

  success "grub-pc preseed step completed"
  return 0
}

recover_grub_pc_if_needed() {
  local grub_disk=""

  if ! dpkg -s grub-pc >/dev/null 2>&1; then
    return 0
  fi

  warn "Attempting grub-pc recovery for noninteractive upgrade..."
  preseed_grub_pc || true
  grub_disk="$(detect_grub_install_disk)"

  if $DRY_RUN; then
    info "[DRY-RUN] Would run grub-pc recovery commands"
    return 0
  fi

  if [[ -n "$grub_disk" ]] && command -v grub-install >/dev/null 2>&1; then
    info "Running grub-install on detected disk: $grub_disk"
    sudo grub-install "$grub_disk" >>"$LOG_FILE" 2>&1 || true
  fi

  if command -v update-grub >/dev/null 2>&1; then
    info "Running update-grub"
    sudo update-grub >>"$LOG_FILE" 2>&1 || true
  fi

  sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure grub-pc >>"$LOG_FILE" 2>&1 || true
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a >>"$LOG_FILE" 2>&1 || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold >>"$LOG_FILE" 2>&1 || true

  if dpkg --audit 2>/dev/null | grep -Eq '(^|[[:space:]])grub-pc([[:space:]]|$)'; then
    warn "grub-pc still appears to need attention after recovery attempt."
    warn "Detected GRUB disk was: ${grub_disk:-<unknown>}"
    return 1
  fi

  success "grub-pc recovery attempt completed"
  return 0
}


backup_file() {
  local file="$1"

  if [[ ! -e "$file" ]]; then
    info "No existing file to back up: $file"
    return 0
  fi

  local backup_root="${HOME}/workstation_backups"
  local sanitized_rel
  sanitized_rel="$(printf '%s' "$file" | sed 's#^/##; s#/#__#g')"
  local backup_path="${backup_root}/${sanitized_rel}.bak.$(date +%Y%m%d%H%M%S)"
  if $DRY_RUN; then
    info "[DRY-RUN] Would back up $file to $backup_path"
    return 0
  fi

  mkdir -p "$backup_root" >>"$LOG_FILE" 2>&1 || true

  if sudo cp -a "$file" "$backup_path" >>"$LOG_FILE" 2>&1; then
    success "Backed up $file to $backup_path"
    return 0
  else
    warn "Failed to back up $file"
    record_failure "backup:$(basename "$file")"
    return 1
  fi
}

run_or_preview() {
  local desc="$1"
  shift

  if $DRY_RUN; then
    info "[DRY-RUN] $desc"
    printf '[DRY-RUN CMD] %q ' "$@" | tee -a "$LOG_FILE" >/dev/null
    echo | tee -a "$LOG_FILE" >/dev/null
    return 0
  fi

  "$@"
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
  if $NON_INTERACTIVE; then
    return 0
  fi
  read -r -p "Press Enter to continue..."
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer

  if $NON_INTERACTIVE; then
    info "[NON-INTERACTIVE] ${prompt} -> default ${default}"
    [[ "$default" == "Y" ]]
    return
  fi

  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "$prompt [y/N]: " answer
    answer="${answer:-N}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

section_result_summary() {
  local section_label="$1"
  local required_count="${2:-0}"
  local optional_count="${3:-0}"
  local skipped_count="${4:-0}"

  echo
  info "${section_label} summary:"
  echo "  Required failures : ${required_count}"
  echo "  Optional failures : ${optional_count}"
  echo "  Skipped items     : ${skipped_count}"
}

show_section_header() {
  echo
  printf "${BOLD}${CYAN}============================================================${NC}\n"
  printf "${BOLD}${CYAN}%s${NC}\n" "$1"
  printf "${BOLD}${CYAN}============================================================${NC}\n"
}

log_dry_run_command() {
  local prefix="$1"
  shift
  printf '%s' "$prefix" | tee -a "$LOG_FILE" >/dev/null
  printf '%q ' "$@" | tee -a "$LOG_FILE" >/dev/null
  echo | tee -a "$LOG_FILE" >/dev/null
}

run_step() {
  local desc="$1"
  local use_sudo="${2:-false}"
  local live_output="${3:-false}"
  shift 3

  if [[ $# -eq 0 ]]; then
    error "run_step called without a command for: $desc"
    return 1
  fi

  if [[ "$use_sudo" == "true" ]]; then
    case "$1" in
      apt|apt-get|nala|dpkg)
        wait_for_apt_lock || return 1
        ;;
    esac
  fi

  info "$desc"
  [[ "$live_output" == "true" ]] && echo "------------------------------------------------------------"

  if $DRY_RUN; then
    info "[DRY-RUN] Skipping execution for: $desc"
    if [[ "$use_sudo" == "true" ]]; then
      log_dry_run_command '[DRY-RUN CMD] sudo ' "$@"
    else
      log_dry_run_command '[DRY-RUN CMD] ' "$@"
    fi
    [[ "$live_output" == "true" ]] && echo "------------------------------------------------------------"
    success "$desc"
    return 0
  fi

  local -a cmd=("$@")
  local rc=0

  if [[ "$live_output" == "true" ]]; then
    if [[ "$use_sudo" == "true" ]]; then
      sudo DEBIAN_FRONTEND=noninteractive "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
      rc=${PIPESTATUS[0]}
    else
      "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
      rc=${PIPESTATUS[0]}
    fi
    echo "------------------------------------------------------------"
  else
    if [[ "$use_sudo" == "true" ]]; then
      sudo DEBIAN_FRONTEND=noninteractive "${cmd[@]}" >>"$LOG_FILE" 2>&1
      rc=$?
    else
      "${cmd[@]}" >>"$LOG_FILE" 2>&1
      rc=$?
    fi
  fi

  if (( rc == 0 )); then
    success "$desc"
    return 0
  fi

  error "$desc"
  return 1
}

run_cmd() {
  local desc="$1"
  shift
  run_step "$desc" false false "$@"
}

sudo_run() {
  local desc="$1"
  shift
  run_step "$desc" true false "$@"
}

run_cmd_live() {
  local desc="$1"
  shift
  run_step "$desc" false true "$@"
}

sudo_run_live() {
  local desc="$1"
  shift
  run_step "$desc" true true "$@"
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

  if grep -Fqx "$line" "$file"; then
    fix_user_file_ownership "$file"
    return 0
  fi

  if [[ "$file" == /etc/* ]]; then
    backup_file "$file" || true
  fi

  if $DRY_RUN; then
    info "[DRY-RUN] Would append line to $file: $line"
    return 0
  fi

  echo "$line" >> "$file"
  fix_user_file_ownership "$file"
}

replace_or_append() {
  local file="$1"
  local regex="$2"
  local newline="$3"

  touch "$file"

  if [[ "$file" == /etc/* ]]; then
    backup_file "$file" || true
  fi

  if $DRY_RUN; then
    info "[DRY-RUN] Would update $file using regex: $regex"
    return 0
  fi

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
# ------------------------------------------------------------
# Function: detect_os
# Purpose:
#   Reads /etc/os-release and normalizes distro-specific details into
#   script variables. Sections should use DISTRO_FAMILY, APT_CODENAME,
#   DOCKER_DISTRO, and JAVA_PKG instead of hardcoding distro behavior.
# ------------------------------------------------------------
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
  UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  IS_LMDE=false
  IS_UBUNTU=false
  IS_ZORIN=false
  IS_SUPPORTED_OS=false
  DISTRO_FAMILY="unknown"
  DISTRO_NAME="$OS_ID"
  JAVA_PKG="default-jre"

  if [[ "$OS_ID" == "linuxmint" ]] && [[ "$OS_NAME" == "LMDE" ]]; then
    IS_LMDE=true
    DISTRO_NAME="lmde"
  fi

  if [[ "$OS_ID" == "ubuntu" ]]; then
    IS_UBUNTU=true
    DISTRO_NAME="ubuntu"
  fi

  if [[ "$OS_ID" == "zorin" ]] || grep -qi '^ID=.*zorin' /etc/os-release 2>/dev/null || grep -qi '^NAME=.*Zorin' /etc/os-release 2>/dev/null; then
    IS_ZORIN=true
    DISTRO_NAME="zorin"
  fi

  if $IS_LMDE; then
    IS_SUPPORTED_OS=true
    DISTRO_FAMILY="debian"
    DOCKER_DISTRO="debian"
    APT_CODENAME="${DEBIAN_CODENAME:-bookworm}"

    case "$APT_CODENAME" in
      bookworm) JAVA_PKG="openjdk-17-jre" ;;
      trixie)   JAVA_PKG="openjdk-21-jre" ;;
      *)        JAVA_PKG="default-jre" ;;
    esac
  elif $IS_UBUNTU || $IS_ZORIN; then
    IS_SUPPORTED_OS=true
    DISTRO_FAMILY="ubuntu"
    DOCKER_DISTRO="ubuntu"
    APT_CODENAME="${UBUNTU_CODENAME:-${OS_VERSION_CODENAME:-}}"
    if [[ -z "$APT_CODENAME" && $IS_ZORIN == true ]]; then
      case "$OS_VERSION_ID" in
        18*|18.*) APT_CODENAME="noble" ;;
        17*|17.*) APT_CODENAME="jammy" ;;
      esac
    fi
    JAVA_PKG="default-jre"
  else
    DISTRO_FAMILY="debian"
    DOCKER_DISTRO="debian"
    APT_CODENAME="${DEBIAN_CODENAME:-${OS_VERSION_CODENAME:-bookworm}}"
    JAVA_PKG="default-jre"
  fi

  if command_exists nala; then
    PKG_MGR="nala"
  else
    PKG_MGR="apt-get"
  fi

  detect_package_managers
  detect_desktop_environment
}


print_detected_environment() {
  info "Detected OS           : $OS_PRETTY_NAME"
  info "Detected architecture : $ARCH"
  info "Distro name           : $DISTRO_NAME"
  info "Distro family         : $DISTRO_FAMILY"
  info "LMDE                  : $IS_LMDE"
  info "Ubuntu                : $IS_UBUNTU"
  info "Zorin                 : $IS_ZORIN"
  info "Supported OS          : $IS_SUPPORTED_OS"
  info "APT codename          : $APT_CODENAME"
  info "Docker distro         : $DOCKER_DISTRO"
  info "Java package          : $JAVA_PKG"
  info "Preferred package mgr : $PKG_MGR"
  info "Snap available        : $HAS_SNAP"
  info "Flatpak available     : $HAS_FLATPAK"
  info "Preferred app method  : $PREFERRED_APP_INSTALLER"
  info "Desktop environment  : $DESKTOP_ENVIRONMENT"
  info "Display server       : $DISPLAY_SERVER"
  info "File manager         : $FILE_MANAGER"
}

pkg_name_dns_tools() {
  case "$DISTRO_FAMILY" in
    ubuntu) echo "dnsutils" ;;
    debian) echo "bind9-dnsutils" ;;
    *)
      if apt-cache show bind9-dnsutils >/dev/null 2>&1; then
        echo "bind9-dnsutils"
      else
        echo "dnsutils"
      fi
      ;;
  esac
}


# ---------- Package Manager Wrappers ----------
pkg_update() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo DEBIAN_FRONTEND=noninteractive nala update 2>&1 | tee -a "$LOG_FILE"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_upgrade_full() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo DEBIAN_FRONTEND=noninteractive nala upgrade -y 2>&1 | tee -a "$LOG_FILE"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_install() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo DEBIAN_FRONTEND=noninteractive nala install -y "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

pkg_fix_broken() {
  wait_for_apt_lock || return 1
  if command_exists nala; then
    sudo DEBIAN_FRONTEND=noninteractive nala install -f -y 2>&1 | tee -a "$LOG_FILE" || true
    wait_for_apt_lock || return 1
    sudo DEBIAN_FRONTEND=noninteractive nala --fix-broken install -y 2>&1 | tee -a "$LOG_FILE" || true
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold 2>&1 | tee -a "$LOG_FILE" || true
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

# ---------- Snap Helpers ----------
# These helpers are used only when the user chooses a Snap install path.
# They keep Snap-specific logic out of individual sections.
snap_app_installed() {
  local app_name="$1"
  snap list "$app_name" >/dev/null 2>&1
}

install_snap_app() {
  local app_name="$1"
  local label="$2"
  shift 2

  if ! ensure_snap_available; then
    record_failure "snap-${app_name}"
    return 1
  fi

  if snap_app_installed "$app_name"; then
    success "Already installed (Snap): $label"
    return 0
  fi

  info "Installing Snap app: $label"
  if sudo snap install "$app_name" "$@" >>"$LOG_FILE" 2>&1; then
    success "Installed (Snap): $label"
    return 0
  else
    error "Failed to install (Snap): $label"
    record_failure "snap-${app_name}"
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
    warn "This script is optimized for LMDE 6/7, Ubuntu, and Zorin OS 18+. Some steps may need manual adjustment on other distros."
  fi
}

# ---------- Section 1 ----------
section_1_system_update() {
  show_section_header "Section 1 - System Update & Upgrade"

  if ! sudo_run "Create /etc/apt/apt.conf.d" mkdir -p /etc/apt/apt.conf.d; then
    record_failure "apt-conf-dir"
    return 1
  fi

  preseed_noninteractive_apt
  preseed_grub_pc || true

  backup_file /etc/apt/apt.conf.d/99releaseinfo || true
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would write /etc/apt/apt.conf.d/99releaseinfo"
  else
    info "Allow apt release info version changes"
    if printf '%s\n' 'Acquire::AllowReleaseInfoChange "true";' | sudo tee /etc/apt/apt.conf.d/99releaseinfo >/dev/null 2>>"$LOG_FILE"; then
      success "Allow apt release info version changes"
    else
      error "Allow apt release info version changes"
      return 1
    fi
  fi

  info "Recovering package manager state if needed..."
  wait_for_apt_lock || return 1
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a >>"$LOG_FILE" 2>&1 || true

  wait_for_apt_lock || return 1
  sudo DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold >>"$LOG_FILE" 2>&1 || true

  info "Forcing APT to use IPv4 for better repo reliability..."
  backup_file /etc/apt/apt.conf.d/99force-ipv4 || true
  if $DRY_RUN; then
    info "[DRY-RUN] Would write /etc/apt/apt.conf.d/99force-ipv4"
  else
    echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 >/dev/null
  fi

  sudo_run_live "Update apt package lists (allow release info version change)" apt-get update -o Acquire::AllowReleaseInfoChange::Version=true || return 1

  if ! sudo_run_live "Run apt full-upgrade" apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade; then
    warn "apt full-upgrade failed. Checking whether grub-pc needs recovery..."
    if recover_grub_pc_if_needed && sudo_run_live "Retry apt full-upgrade after grub-pc recovery" apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade; then
      success "apt full-upgrade succeeded after grub-pc recovery"
    else
      error "Run apt full-upgrade"
      record_failure "section1-full-upgrade"
      return 1
    fi
  fi

  if ! command_exists nala; then
    sudo_run_live "Install nala" apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold nala || return 1
  else
    success "nala is already installed"
  fi

  if command_exists nala; then
    sudo_run_live "Update package lists with nala" nala update || return 1
    if ! sudo_run_live "Upgrade packages with nala" nala upgrade -y; then
      warn "nala upgrade failed. Attempting grub-pc recovery and apt-based retry..."
      if recover_grub_pc_if_needed && sudo_run_live "Retry upgrade with apt-get after grub-pc recovery" apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade; then
        success "Upgrade completed after grub-pc recovery"
      else
        return 1
      fi
    fi
  else
    sudo_run_live "Update package lists with apt-get" apt-get update || return 1
    sudo_run_live "Upgrade packages with apt-get" apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade || return 1
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
      record_optional_failure "$pkg"
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
  echo "  Optional failed   : ${#optional_failed[@]}"
  section_result_summary "Section 2" "${#failed[@]}" "${#optional_failed[@]}" "${#skipped[@]}"

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

  # v44 note: Flatpak remains the default for this section because several
  # desktop apps here are distributed consistently through Flathub. Snap
  # detection is still performed globally so Ubuntu/Zorin-specific sections
  # can offer Snap when it is the better install method.

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
  section_result_summary "Section 3" "${#failed[@]}" "0" "0"
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
  backup_file /etc/apt/sources.list.d/docker.sources || true
  if $DRY_RUN; then
    info "[DRY-RUN] Would write /etc/apt/sources.list.d/docker.sources"
  else
    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: ${docker_uri}
Suites: ${APT_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: ${docker_gpg}
EOF
  fi

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
  local docker_madison docker_candidate
  docker_madison="$(apt-cache madison docker-ce 2>&1)"
  docker_candidate="$(apt-cache policy docker-ce 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  echo "$docker_madison" | tee -a "$LOG_FILE"
  echo "Candidate: ${docker_candidate:-<none>}" | tee -a "$LOG_FILE"

  if [[ -n "$docker_madison" && -n "$docker_candidate" && "$docker_candidate" != "(none)" ]]; then
    success "docker-ce package is visible from configured repositories."
  else
    error "docker-ce package is still not visible after repo setup."
    warn "Detected Docker repo target: ${DOCKER_DISTRO}:${APT_CODENAME}. This codename may not be published by Docker yet."
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
    info "Changing default shell for $STARTING_USER to $zsh_path using usermod -s"
    if sudo usermod -s "$zsh_path" "$STARTING_USER" >>"$LOG_FILE" 2>&1; then
      local updated_shell
      updated_shell="$(getent passwd "$STARTING_USER" | cut -d: -f7)"
      if [[ "$updated_shell" == "$zsh_path" ]]; then
        success "Default login shell updated successfully to $zsh_path for $STARTING_USER."
      else
        error "usermod completed, but verification failed. Expected $zsh_path and found ${updated_shell:-<unknown>}."
        record_failure "usermod-zsh-verify"
        return 1
      fi
    else
      error "Failed to change default shell with usermod -s. Try manually: sudo usermod -s $zsh_path $STARTING_USER"
      record_failure "usermod-zsh"
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
          record_optional_failure "p10k-config"
        fi
      else
        warn "Powerlevel10k wizard did not complete successfully."
        warn "Run these manually in your terminal:"
        echo '  exec zsh -l'
        echo '  p10k configure'
        record_optional_failure "p10k-config"
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

  detect_desktop_environment
  info "Detected desktop/file manager: $DESKTOP_ENVIRONMENT / $FILE_MANAGER"
  # v45 note: this section is intentionally Nemo-only. On Zorin/Ubuntu
  # systems that use Nautilus, the section exits safely instead of applying
  # Cinnamon/Nemo keys that do not exist.
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
  section_result_summary "Section 11" "0" "0" "$skipped_count"

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
      record_optional_failure "jdownloader-launch"
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

  backup_file "$repo_file" || true
  if $DRY_RUN; then
    info "[DRY-RUN] Would write $repo_file"
  elif ! sudo tee "$repo_file" >/dev/null <<'EOF'
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

install_vscode_from_repo() {
  if ! setup_vscode_repo; then
    error "VS Code repository setup failed"
    return 1
  fi
  sudo_run_live "Install Visual Studio Code from Microsoft APT repo" apt install -y code
}

install_vscode_from_snap() {
  install_snap_app code "Visual Studio Code" --classic
}

install_vscode_from_flatpak() {
  ensure_flatpak_flathub || return 1
  install_flatpak_app com.visualstudio.code "Visual Studio Code"
}

choose_vscode_install_method() {
  local method=""
  echo
  info "Choose VS Code install method:"
  echo "  1) Microsoft APT repo (recommended)"
  echo "  2) Snap (Ubuntu/Zorin only, if Snap is available)"
  echo "  3) Flatpak (cross-distro fallback)"
  if [[ "$DISTRO_FAMILY" == "ubuntu" && "$HAS_SNAP" == true ]]; then
    read -r -p "Select method [1/2/3, default 1]: " method
  else
    read -r -p "Select method [1/3, default 1]: " method
  fi
  case "${method:-1}" in
    2) printf '%s\n' "snap" ;;
    3) printf '%s\n' "flatpak" ;;
    *) printf '%s\n' "repo" ;;
  esac
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
      record_optional_failure "$ext_id"
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

  if pkg_installed "$vscode_pkg" || command_exists code || flatpak_app_installed com.visualstudio.code || snap_app_installed code; then
    success "VS Code is already installed"
  else
    local vscode_method
    vscode_method="$(choose_vscode_install_method)"
    case "$vscode_method" in
      snap)
        install_vscode_from_snap || { record_failure "vscode-install-snap"; return 1; }
        ;;
      flatpak)
        install_vscode_from_flatpak || { record_failure "vscode-install-flatpak"; return 1; }
        ;;
      *)
        install_vscode_from_repo || { record_failure "vscode-install-repo"; return 1; }
        ;;
    esac
    success "Visual Studio Code installation step completed using method: $vscode_method"
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
  local timeshift_list_output="" timeshift_check_output="" timeshift_create_log=""
  local first_run_mode=false selected_device="" selected_path="" selected_mode="" free_space_human=""
  local run_id="" create_rc=0

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
  timeshift_check_output="$(sudo timeshift --check 2>&1 || true)"
  printf '%s\n' "$timeshift_check_output" | tee -a "$LOG_FILE" >/dev/null

  echo
  info "Existing Timeshift snapshots:"
  timeshift_list_output="$(sudo timeshift --list 2>&1 || true)"
  printf '%s\n' "$timeshift_list_output" | tee -a "$LOG_FILE"

  if grep -Fqi "First run mode (config file not found)" <<< "$timeshift_list_output"; then
    first_run_mode=true
    warn "Timeshift is in first-run mode and has not been fully configured yet."
    warn "The first RSYNC snapshot can take a long time and may appear to sit at 0.00% for quite a while."
  fi

  if grep -Fq "No snapshots found" <<< "$timeshift_list_output"; then
    warn "No snapshots were found on the selected Timeshift device yet."
  fi

  selected_device="$(awk -F': ' '/^Device[[:space:]]*:/{print $2; exit}' <<< "$timeshift_list_output")"
  selected_path="$(awk -F': ' '/^Path[[:space:]]*:/{print $2; exit}' <<< "$timeshift_list_output")"
  selected_mode="$(awk -F': ' '/^Mode[[:space:]]*:/{print $2; exit}' <<< "$timeshift_list_output")"

  if [[ -n "$selected_device" ]]; then
    info "Selected snapshot device : $selected_device"
  fi
  if [[ -n "$selected_path" ]]; then
    info "Snapshot path            : $selected_path"
    free_space_human="$(df -h "$selected_path" 2>/dev/null | awk 'NR==2 {print $4 " free of " $2}')"
    if [[ -n "$free_space_human" ]]; then
      info "Free space on device     : $free_space_human"
    fi
  fi
  if [[ -n "$selected_mode" ]]; then
    info "Snapshot mode            : $selected_mode"
  fi

  existing_count="$(grep -Ec '^>[[:space:]]|^[[:space:]]*[0-9]{4}-' <<< "$timeshift_list_output" || true)"
  info "Detected snapshot count: ${existing_count:-0}"

  echo
  info "Recommended flow:"
  echo "  1) Confirm the snapshot device/path above are correct"
  echo "  2) Create the first snapshot only when you are ready to let it run"
  echo "  3) Expect the first RSYNC snapshot to be much slower than later ones"

  if ! confirm "Create a new Timeshift snapshot now?" "Y"; then
    warn "Skipped snapshot creation."
  else
    read -r -p "Snapshot tag [O]=On-demand or [B]=Boot (default O): " snapshot_tag
    snapshot_tag="${snapshot_tag:-O}"
    case "${snapshot_tag^^}" in
      B) snapshot_tag="B" ;;
      *) snapshot_tag="O" ;;
    esac

    read -r -p "Snapshot comment [Workstation setup manual snapshot]: " snapshot_comment
    snapshot_comment="${snapshot_comment:-Workstation setup manual snapshot}"

    echo
    if $first_run_mode; then
      warn "This appears to be your first Timeshift snapshot."
      warn "It may stay at 0.00% for several minutes while Timeshift scans and builds the initial RSYNC baseline."
    fi

    info "Creating Timeshift snapshot. Leave this running until Timeshift exits."
    run_id="$(date +%Y%m%d%H%M%S)"
    timeshift_create_log="/tmp/timeshift_create_${run_id}.log"
    : > "$timeshift_create_log"

    if sudo timeshift --create --comments "$snapshot_comment" --tags "$snapshot_tag" 2>&1 | tee -a "$LOG_FILE" "$timeshift_create_log"; then
      create_rc=0
    else
      create_rc=$?
    fi

    if (( create_rc != 0 )); then
      error "Timeshift snapshot command exited with a non-zero status."
      record_failure "timeshift-create"
      warn "Review the output above and $timeshift_create_log for the exact Timeshift error."
      return 1
    fi

    if grep -Eqi 'snapshot saved successfully|Tagged snapshot|created successfully|created new snapshot' "$timeshift_create_log"; then
      success "Timeshift snapshot created"
    else
      success "Timeshift command completed. Verifying snapshot list next."
    fi
  fi

  if confirm "Show Timeshift snapshots again now?" "Y"; then
    sudo timeshift --list 2>&1 | tee -a "$LOG_FILE" || true
  fi

  if confirm "Delete older snapshots by count?" "N"; then
    read -r -p "How many oldest snapshots would you like to delete? [0]: " delete_count
    delete_count="${delete_count:-0}"
    if [[ "$delete_count" =~ ^[0-9]+$ ]] && (( delete_count > 0 )); then
      warn "Automated delete-by-count behavior varies across Timeshift builds."
      warn "Use the Timeshift GUI or 'sudo timeshift --delete' manually if you want tightly controlled cleanup."
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
      backup_file /etc/fstab || true
      if $DRY_RUN; then
        info "[DRY-RUN] Would append entry to /etc/fstab: $fstab_entry"
      else
        echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
      fi
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

# ---------- Toolkit Helpers ----------
command_or_pkg_present() {
  command_exists "$1" || pkg_installed "$1"
}

ensure_user_dirs() {
  local dir
  for dir in "$@"; do
    if $DRY_RUN; then
      info "[DRY-RUN] Would create directory: $dir"
    else
      run_as_user mkdir -p "$dir" >>"$LOG_FILE" 2>&1 || true
      fix_user_file_ownership "$dir"
    fi
  done
}

write_user_template() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"

  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    info "Template already up to date: $target"
    return 0
  fi

  if $DRY_RUN; then
    info "[DRY-RUN] Would write template: $target"
    rm -f "$tmp"
    return 0
  fi

  run_as_user mkdir -p "$(dirname "$target")" >>"$LOG_FILE" 2>&1 || true
  cp "$tmp" "$target"
  rm -f "$tmp"
  fix_user_file_ownership "$target"
  success "Wrote template: $target"
}

append_block_if_missing() {
  local file="$1"
  local marker="$2"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"

  touch "$file"
  if grep -Fq "$marker" "$file" 2>/dev/null; then
    rm -f "$tmp"
    info "Block already present in $file: $marker"
    fix_user_file_ownership "$file"
    return 0
  fi

  if $DRY_RUN; then
    info "[DRY-RUN] Would append block to $file: $marker"
    rm -f "$tmp"
    return 0
  fi

  cat "$tmp" >> "$file"
  rm -f "$tmp"
  fix_user_file_ownership "$file"
  success "Appended block to $file: $marker"
}

install_package_group() {
  local label="$1"
  local required_name="$2"
  local optional_name="$3"
  local installed_name="$4"
  local skipped_name="$5"
  local required_failed_name="$6"
  local optional_failed_name="$7"

  local -n required_ref="$required_name"
  local -n optional_ref="$optional_name"
  local -n installed_ref="$installed_name"
  local -n skipped_ref="$skipped_name"
  local -n required_failed_ref="$required_failed_name"
  local -n optional_failed_ref="$optional_failed_name"

  local pkg
  info "Installing package group: $label"
  for pkg in "${required_ref[@]}"; do
    if pkg_installed "$pkg"; then
      success "Already installed: $pkg"
      skipped_ref+=("$pkg")
    elif pkg_install "$pkg"; then
      success "Installed: $pkg"
      installed_ref+=("$pkg")
    else
      warn "Failed to install required package: $pkg"
      required_failed_ref+=("$pkg")
      record_failure "$pkg"
    fi
  done

  for pkg in "${optional_ref[@]}"; do
    if pkg_installed "$pkg"; then
      success "Already installed: $pkg"
      skipped_ref+=("$pkg")
    elif pkg_install "$pkg"; then
      success "Installed: $pkg"
      installed_ref+=("$pkg")
    else
      warn "Failed to install optional package: $pkg"
      optional_failed_ref+=("$pkg")
      record_optional_failure "$pkg"
    fi
  done
}

find_available_port() {
  local start="${1:-3000}"
  local end="${2:-3999}"
  local port
  for ((port=start; port<=end; port++)); do
    if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

write_compose_stack() {
  local stack_dir="$1"
  local file="$stack_dir/compose.yml"
  run_as_user mkdir -p "$stack_dir" >>"$LOG_FILE" 2>&1 || true
  write_user_template "$file"
}

docker_compose_cmd() {
  if docker ps >/dev/null 2>&1; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}

docker_cmd() {
  if docker ps >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

warn_if_docker_group_not_active() {
  if ! docker ps >/dev/null 2>&1; then
    warn "${STARTING_USER} cannot currently access Docker without sudo. Section 26 will use sudo for Docker commands."
    warn "If you recently ran 'sudo usermod -aG docker ${STARTING_USER}', fully log out/in or reboot before using Docker without sudo."
  fi
}

write_url_note() {
  local file="$1"
  shift
  if $DRY_RUN; then
    info "[DRY-RUN] Would write URL notes to $file"
    return 0
  fi
  run_as_user bash -c 'cat > "$1"' _ "$file" <<< "$*" >>"$LOG_FILE" 2>&1 || true
  fix_user_file_ownership "$file"
}

# ---------- Section 19 ----------
section_19_dev_tools_profile() {
  show_section_header "Section 19 - Developer CLI Tools"

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
    pre-commit
  )
  local installed_now=()
  local already_installed=()
  local failed_required=()
  local failed_optional=()
  local node_mode="skip"
  local reply=""
  local want_kubectl=false
  local node_requested=false

  dev_tool_cmd_exists() {
    command -v "$1" >/dev/null 2>&1
  }

  dev_tool_install_pkg() {
    local pkg="$1"
    local label="$2"
    local required_flag="${3:-required}"

    if pkg_installed "$pkg"; then
      success "Already installed: $label"
      already_installed+=("$label")
      return 0
    fi

    info "Installing package: $label"
    if pkg_install "$pkg" && pkg_installed "$pkg"; then
      success "Installed: $label"
      installed_now+=("$label")
      return 0
    fi

    warn "Failed to install: $label"
    if [[ "$required_flag" == "optional" ]]; then
      failed_optional+=("$label")
      record_optional_failure "$label"
    else
      failed_required+=("$label")
      record_failure "$label"
    fi
    return 1
  }

  verify_dev_tool() {
    local label="$1"
    local cmd="$2"
    if dev_tool_cmd_exists "$cmd"; then
      success "$label is installed"
    else
      warn "$label is not installed"
    fi
  }

  info "Installing developer CLI packages..."
  local pkg
  for pkg in "${base_pkgs[@]}"; do
    dev_tool_install_pkg "$pkg" "$pkg" "required" || true
  done

  if dev_tool_cmd_exists pipx; then
    run_as_user pipx ensurepath >>"$LOG_FILE" 2>&1 || true
    success "pipx path setup attempted"
  fi

  echo
  warn "Node.js from Debian/LMDE repositories can pull in a large dependency set."
  while true; do
    read -r -p "Node.js install mode [1=Node.js only, 2=Node.js + npm, 3=Skip] (default 2): " reply
    reply="${reply:-2}"
    case "$reply" in
      1) node_mode="node_only"; node_requested=true; break ;;
      2) node_mode="node_and_npm"; node_requested=true; break ;;
      3) node_mode="skip"; break ;;
      *) warn "Invalid selection. Enter 1, 2, or 3." ;;
    esac
  done

  case "$node_mode" in
    node_only)
      if confirm "Proceed with Node.js only installation?" "Y"; then
        dev_tool_install_pkg nodejs "nodejs" "optional" || true
      fi
      ;;
    node_and_npm)
      if confirm "Proceed with Node.js + npm installation?" "Y"; then
        dev_tool_install_pkg nodejs "nodejs" "optional" || true
        dev_tool_install_pkg npm "npm" "optional" || true
      fi
      ;;
    *)
      info "Skipping Node.js installation by user choice."
      ;;
  esac

  if confirm "Install kubectl from distro repositories if available?" "N"; then
    want_kubectl=true
    if pkg_installed kubectl; then
      success "Already installed: kubectl"
      already_installed+=("kubectl")
    else
      info "Checking whether kubectl is available from configured repositories..."
      if apt-cache policy kubectl 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -vq '(none)'; then
        dev_tool_install_pkg kubectl "kubectl" "optional" || true
      else
        warn "kubectl is not available from the currently configured repositories."
        failed_optional+=("kubectl (repo unavailable)")
        record_optional_failure "kubectl-repo-unavailable"
      fi
    fi
  fi

  echo
  info "Development tool verification:"
  verify_dev_tool "Python 3" python3
  verify_dev_tool "pipx" pipx
  verify_dev_tool "GitHub CLI" gh
  if $want_kubectl; then
    verify_dev_tool "kubectl" kubectl
  fi
  if $node_requested; then
    verify_dev_tool "Node.js" node
    [[ "$node_mode" == "node_and_npm" ]] && verify_dev_tool "npm" npm
  fi

  echo
  info "Development tool versions:"
  dev_tool_cmd_exists python3 && python3 --version | tee -a "$LOG_FILE"
  dev_tool_cmd_exists pip3 && pip3 --version | tee -a "$LOG_FILE"
  dev_tool_cmd_exists pipx && pipx --version | tee -a "$LOG_FILE"
  dev_tool_cmd_exists node && node --version | tee -a "$LOG_FILE"
  dev_tool_cmd_exists npm && npm --version | tee -a "$LOG_FILE"
  dev_tool_cmd_exists kubectl && kubectl version --client=true --output=yaml | head -n3 | tee -a "$LOG_FILE"
  dev_tool_cmd_exists gh && gh --version | head -n1 | tee -a "$LOG_FILE"

  echo
  section_result_summary "Section 19 - Developer CLI Tools" "${#failed_required[@]}" "${#failed_optional[@]}" "${#already_installed[@]}"

  if (( ${#failed_required[@]} > 0 )); then
    warn "Developer CLI tools completed with required package warnings."
  elif (( ${#failed_optional[@]} > 0 )); then
    warn "Developer CLI tools completed with optional package warnings."
  elif (( ${#installed_now[@]} > 0 )); then
    success "Developer CLI tools section completed."
  else
    warn "No new developer CLI tools were installed."
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
    echo "Distro name: $DISTRO_NAME"
    echo "Distro family: $DISTRO_FAMILY"
    echo "Zorin: $IS_ZORIN"
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
section_21_validation_report() {

  show_section_header "Section 21 - Validation Report"

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
    echo "Distro name: $DISTRO_NAME"
    echo "Distro family: $DISTRO_FAMILY"
    echo "Zorin: $IS_ZORIN"
    echo "Architecture: $ARCH"
    echo "APT codename: $APT_CODENAME"
    echo "Docker distro: $DOCKER_DISTRO"
    echo "Java package target: $JAVA_PKG"
    echo

    echo "Command Checks"
echo "--------------"
for cmd in nala apt-get zsh flatpak docker brave-browser 1password winboat code ssh nmap iperf3 tcpdump brightnessctl xrandr; do
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
    for pkg in zsh tlp ufw gufw timeshift okular pdfarranger kodi 1password nfs-common cifs-utils openssh-server openssh-client openssh-sftp-server btrfs-progs mdadm lvm2 smartmontools testdisk nmap tcpdump wireshark tshark iperf3 mtr bind9-dnsutils dnsutils snmp lldpd lnav multitail ccze grc brightnessctl x11-xserver-utils; do
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
    echo "Proxmox Toolkit"
    echo "---------------"
    [[ -d "${STARTING_HOME}/Projects/proxmox" ]] && echo "Projects/proxmox: present" || echo "Projects/proxmox: not present"
    [[ -f "${STARTING_HOME}/Projects/proxmox/commands_reference.txt" ]] && echo "commands_reference.txt: present" || echo "commands_reference.txt: not present"
    echo

    echo "Synology Toolkit"
    echo "----------------"
    [[ -d "/mnt/synology" ]] && echo "/mnt/synology: present" || echo "/mnt/synology: not present"
    [[ -f "${STARTING_HOME}/Projects/storage/synology_mount_templates.txt" ]] && echo "synology_mount_templates.txt: present" || echo "synology_mount_templates.txt: not present"
    echo

    echo "Docker Stacks"
    echo "-------------"
    [[ -d "${STARTING_HOME}/docker/stacks" ]] && find "${STARTING_HOME}/docker/stacks" -maxdepth 2 -name compose.yml -printf '%h
' 2>/dev/null || echo "No docker stacks directory found"
    command_exists docker && docker ps --format 'table {{.Names}}	{{.Status}}' 2>/dev/null || true
    echo

    echo "Network Toolkit"
    echo "---------------"
    [[ -d "${STARTING_HOME}/Projects/network-tools" ]] && ls -1 "${STARTING_HOME}/Projects/network-tools" 2>/dev/null || echo "Projects/network-tools: not present"
    echo

    echo "Logging / Diagnostics Toolkit"
    echo "-----------------------------"
    for cmd in lnav multitail ccze grc brightnessctl x11-xserver-utils; do
      if command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd: present ($(command -v "$cmd"))"
      else
        echo "$cmd: not found"
      fi
    done
    [[ -d "${STARTING_HOME}/Projects/logging-diagnostics" ]] && echo "logging diagnostics folder: ${STARTING_HOME}/Projects/logging-diagnostics"
    echo

    echo "Laptop Brightness / Backlight"
    echo "-----------------------------"
    if [[ -d /sys/class/backlight ]]; then
      echo "Backlight interfaces:"
      ls -1 /sys/class/backlight 2>/dev/null || true
      for bl in /sys/class/backlight/*; do
        [[ -d "$bl" ]] || continue
        echo "$(basename "$bl"): brightness=$(cat "$bl/brightness" 2>/dev/null || echo n/a) max=$(cat "$bl/max_brightness" 2>/dev/null || echo n/a) actual=$(cat "$bl/actual_brightness" 2>/dev/null || echo n/a)"
      done
    else
      echo "/sys/class/backlight not present"
    fi
    command -v brightnessctl >/dev/null 2>&1 && brightnessctl info 2>/dev/null || echo "brightnessctl not available or no controllable device detected"
    [[ -d "${STARTING_HOME}/Projects/display-brightness" ]] && echo "display-brightness folder: ${STARTING_HOME}/Projects/display-brightness"
    echo

    echo "Diagnostics Dashboard / Auto-Fix"
    echo "--------------------------------"
    if [[ -d "${STARTING_HOME}/Projects/system-health-dashboard" ]]; then
      echo "system-health-dashboard folder: ${STARTING_HOME}/Projects/system-health-dashboard"
      find "${STARTING_HOME}/Projects/system-health-dashboard" -maxdepth 3 -type f \( -name "dashboard.html" -o -name "dashboard.txt" -o -name "*.sh" \) 2>/dev/null | sort | tail -n 20
    else
      echo "system-health-dashboard folder: not present"
    fi
    echo

    echo "Firewall"
    echo "--------"
    sudo ufw status verbose 2>/dev/null || echo "ufw status unavailable"
    echo

    echo "Required Failed Items"
    echo "---------------------"
    if [[ -s "$REQUIRED_FAILED_FILE" ]]; then
      sort -u "$REQUIRED_FAILED_FILE"
    else
      echo "None recorded."
    fi
    echo

    echo "Optional Failed Items"
    echo "---------------------"
    if [[ -s "$OPTIONAL_FAILED_FILE" ]]; then
      sort -u "$OPTIONAL_FAILED_FILE"
    else
      echo "None recorded."
    fi
    echo

    echo "All Failed Items"
    echo "----------------"
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

    echo "Desktop Environment"
    echo "-------------------"
    detect_desktop_environment
    echo "Desktop environment: $DESKTOP_ENVIRONMENT"
    echo "Display server: $DISPLAY_SERVER"
    echo "File manager: $FILE_MANAGER"
    if [[ -f "${STARTING_HOME}/Projects/desktop-awareness/desktop_environment_report.txt" ]]; then
      echo "Desktop awareness report: ${STARTING_HOME}/Projects/desktop-awareness/desktop_environment_report.txt"
    fi
    echo

    echo "Notes"
    echo "-----"
    echo "- If Docker was installed and group membership was changed, log out/in before testing docker without sudo."
    echo "- If terminal font does not change, check your terminal profile font override."
    echo "- If Microsoft fonts failed, enable the needed optional repository components for your distro and rerun Section 5."
    echo "- WinBoat requires KVM support, Docker, Docker Compose v2, FreeRDP, and a working docker group setup."
    echo "- OpenSSH Server should show enabled and active when Section 16 completes successfully."
    echo "- Zorin OS 18+ is treated as Ubuntu-family for repo/package handling; Nemo sections may skip if Nemo is not installed."
    echo "- Timeshift snapshots, diagnostics bundles, and backup helpers are available in Sections 17 through 21."
    echo "- Logging / diagnostics tools including lnav are available in Section 28."
    echo "- If SSH is running but remote login fails, confirm UFW allows 22/tcp."
  } > "$REPORT_FILE"

  success "Report written to: $REPORT_FILE"
  echo
  cat "$REPORT_FILE"
}

# ---------- Section 22 ----------
section_22_ansible_setup() {
  show_section_header "Section 22 - Ansible Automation Setup"

  local ansible_pkgs=(ansible sshpass python3-jmespath python3-apt)
  local optional_pkgs=(ansible-lint)
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local project_root="${STARTING_HOME}/Projects/ansible"
  local inventory_file="${project_root}/inventory.ini"
  local cfg_file="${project_root}/ansible.cfg"
  local ping_playbook="${project_root}/ping.yml"

  detect_os

  info "Using distro repositories for Ansible by default."
  warn "v43 uses distro repositories for Ansible by default across LMDE/Debian/Ubuntu/Zorin to avoid third-party PPA signing-policy issues."

  if [[ -f /etc/apt/sources.list.d/ansible.list || -f /usr/share/keyrings/ansible-archive-keyring.gpg ]]; then
    warn "Existing Ansible PPA files were detected from an earlier run."
    if confirm "Disable/remove the older Ansible PPA files before continuing?" "Y"; then
      backup_file /etc/apt/sources.list.d/ansible.list || true
      backup_file /usr/share/keyrings/ansible-archive-keyring.gpg || true
      if $DRY_RUN; then
        info "[DRY-RUN] Would remove Ansible PPA files"
      else
        sudo rm -f /etc/apt/sources.list.d/ansible.list /usr/share/keyrings/ansible-archive-keyring.gpg >>"$LOG_FILE" 2>&1 || true
      fi
      sudo_run_live "Update apt after removing Ansible PPA files" apt-get update || true
    fi
  fi

  install_package_group "Ansible Automation Setup" ansible_pkgs optional_pkgs installed_now skipped failed_required failed_optional

  if command_exists ansible; then
    ansible --version | head -n3 | tee -a "$LOG_FILE"
  else
    error "Ansible command was not found after installation"
    record_failure "ansible-verify"
    return 1
  fi

  if confirm "Install or update ansible-lint with pipx instead of only the distro package?" "Y"; then
    if command_exists pipx || pkg_installed pipx; then
      run_as_user pipx install --force ansible-lint >>"$LOG_FILE" 2>&1 \
        && success "Installed/updated ansible-lint with pipx" \
        || warn "Could not install ansible-lint with pipx"
    else
      warn "pipx is not available. Run Section 19 first if you want pipx-managed automation tools."
    fi
  fi

  if confirm "Create a starter Ansible project in ${project_root}?" "Y"; then
    ensure_user_dirs "$project_root"
    write_user_template "$inventory_file" <<'EOT'
[local]
localhost ansible_connection=local

[linux]
# server1 ansible_host=192.168.1.10 ansible_user=bryan
EOT
    write_user_template "$cfg_file" <<'EOT'
[defaults]
inventory = ./inventory.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
EOT
    write_user_template "$ping_playbook" <<'EOT'
---
- name: Test Ansible connectivity
  hosts: all
  gather_facts: false
  tasks:
    - name: Ping host
      ansible.builtin.ping:
EOT
  fi

  echo
  section_result_summary "Section 22 - Ansible Automation Setup" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  [[ ${#failed_required[@]} -gt 0 ]] && warn "Required package failures: ${failed_required[*]}"
  [[ ${#failed_optional[@]} -gt 0 ]] && warn "Optional package failures: ${failed_optional[*]}"
  success "Ansible automation section completed."
}

# ---------- Section 23 ----------
section_23_terraform_setup() {
  show_section_header "Section 23 - Terraform Setup"

  local keyring="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
  local repo_file="/etc/apt/sources.list.d/hashicorp.list"
  local hashicorp_codename=""
  local project_root="${STARTING_HOME}/Projects/terraform-starter"
  local main_tf="${project_root}/main.tf"
  local gitignore_file="${project_root}/.gitignore"

  detect_os

  hashicorp_codename="$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release 2>/dev/null || true)"
  if [[ -z "$hashicorp_codename" && "$DISTRO_FAMILY" == "ubuntu" ]]; then
    hashicorp_codename="$APT_CODENAME"
  fi

  if [[ -z "$hashicorp_codename" ]]; then
    case "$APT_CODENAME" in
      trixie) hashicorp_codename="noble" ;;
      bookworm) hashicorp_codename="jammy" ;;
      bullseye) hashicorp_codename="focal" ;;
      *) hashicorp_codename="$APT_CODENAME" ;;
    esac
  fi

  info "Configuring the official HashiCorp apt repository using codename: $hashicorp_codename"

  if ! sudo_run_live "Install Terraform repo prerequisites" apt-get install -y wget gpg ca-certificates; then
    record_failure "terraform-repo-prereqs"
    return 1
  fi

  backup_file "$keyring" || true
  backup_file "$repo_file" || true

  if ! sudo bash -c 'wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg' >>"$LOG_FILE" 2>&1; then
    error "Failed to install the HashiCorp signing key"
    record_failure "terraform-signing-key"
    return 1
  fi

  if $DRY_RUN; then
    info "[DRY-RUN] Would write ${repo_file}"
  else
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://apt.releases.hashicorp.com ${hashicorp_codename} main" | sudo tee "$repo_file" >/dev/null
  fi

  if ! sudo_run_live "Update apt after adding the HashiCorp repository" apt-get update; then
    record_failure "terraform-repo-update"
    return 1
  fi

  if ! pkg_install terraform; then
    error "Failed to install Terraform"
    record_failure "terraform-install"
    return 1
  fi

  if command_exists terraform; then
    terraform version | head -n1 | tee -a "$LOG_FILE"
    success "Terraform command verified"
  else
    error "Terraform command was not found after installation"
    record_failure "terraform-verify"
    return 1
  fi

  if confirm "Create a starter Terraform project in ${project_root}?" "Y"; then
    run_as_user mkdir -p "$project_root" >>"$LOG_FILE" 2>&1 || true

    run_as_user bash -c 'cat > "$1" <<"EOF"
terraform {
  required_version = ">= 1.0.0"
}

locals {
  hostname = "terraform-control-node"
}

output "hostname" {
  value = local.hostname
}
EOF' _ "$main_tf" >>"$LOG_FILE" 2>&1 || true

    run_as_user bash -c 'cat > "$1" <<"EOF"
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.*
*.tfvars
*.tfplan
crash.log
EOF' _ "$gitignore_file" >>"$LOG_FILE" 2>&1 || true

    success "Created starter Terraform project: $project_root"
  fi

  if confirm "Run terraform fmt and terraform init in the starter project now?" "Y"; then
    if [[ -d "$project_root" ]]; then
      run_as_user terraform -chdir="$project_root" fmt >>"$LOG_FILE" 2>&1 || true
      if run_as_user terraform -chdir="$project_root" init 2>&1 | tee -a "$LOG_FILE"; then
        success "Terraform starter project initialized"
      else
        warn "Terraform init failed in the starter project"
        record_failure "terraform-init"
      fi
    else
      warn "Starter project does not exist yet. Skipping terraform init."
    fi
  fi
}

# ---------- Section 24 ----------
section_24_proxmox_toolkit() {
  show_section_header "Section 24 - Proxmox Toolkit"

  local required_pkgs=(openssh-client sshpass nfs-common cifs-utils jq curl wget rsync tmux bridge-utils netcat-openbsd)
  local optional_pkgs=(python3-proxmoxer libguestfs-tools)
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local prox_root="${STARTING_HOME}/Projects/proxmox"
  local ssh_config="${STARTING_HOME}/.ssh/config"

  install_package_group "Proxmox Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$prox_root" "$prox_root/scripts" "$prox_root/notes" "$prox_root/terraform"
  ensure_user_dirs "/mnt/proxmox-backups" "/mnt/proxmox-iso" "/mnt/proxmox-shares"

  if confirm "Append example SSH config entries for Proxmox hosts?" "Y"; then
    append_block_if_missing "$ssh_config" "# Added by workstation setup script - Proxmox" <<'EOF'

# Added by workstation setup script - Proxmox
Host proxmox-main
    HostName 192.168.1.10
    User root
    ServerAliveInterval 30
    IdentitiesOnly yes

Host proxmox-lab
    HostName 192.168.1.11
    User root
    ServerAliveInterval 30
    IdentitiesOnly yes
EOF
  fi

  write_user_template "$prox_root/commands_reference.txt" <<'EOF'
Proxmox quick reference
=======================
SSH:
  ssh root@proxmox-main
  ssh root@proxmox-lab

Common commands:
  pvesm status
  qm list
  pct list
  pveversion -v
  journalctl -u pveproxy -n 100

API examples:
  curl -k https://proxmox-main:8006/api2/json/version
EOF

  write_user_template "$prox_root/scripts/proxmox_quick_commands.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ssh "${1:-root@proxmox-main}" 'hostname; pveversion; echo; qm list; echo; pct list; echo; pvesm status'
EOF
  if [[ ! "$DRY_RUN" == true ]]; then run_as_user chmod +x "$prox_root/scripts/proxmox_quick_commands.sh" >>"$LOG_FILE" 2>&1 || true; fi

  echo
  section_result_summary "Section 24 - Proxmox Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  [[ ${#failed_required[@]} -gt 0 ]] && warn "Required package failures: ${failed_required[*]}"
  [[ ${#failed_optional[@]} -gt 0 ]] && warn "Optional package failures: ${failed_optional[*]}"
  success "Proxmox toolkit section completed."
}

# ---------- Section 25 ----------
section_25_synology_toolkit() {
  show_section_header "Section 25 - Synology Toolkit"

  local required_pkgs=(nfs-common cifs-utils rsync btrfs-progs mdadm lvm2 smartmontools testdisk lm-sensors ncdu tree pv curl wget)
  local optional_pkgs=()
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local storage_root="${STARTING_HOME}/Projects/storage"

  install_package_group "Synology Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$storage_root" "/mnt/synology" "/mnt/synology/media" "/mnt/synology/backups" "/mnt/synology/downloads"

  write_user_template "$storage_root/synology_mount_templates.txt" <<'EOF'
Synology mount templates
========================
NFS example:
  192.168.1.50:/volume1/media /mnt/synology/media nfs rw,noatime,hard,intr,nofail,x-systemd.automount 0 0

SMB example:
  //192.168.1.50/media /mnt/synology/media cifs credentials=$HOME/.smbcredentials_synology,iocharset=utf8,uid=1000,gid=1000,vers=3.0,nofail,x-systemd.automount 0 0
EOF

  write_user_template "$storage_root/rsync_synology_backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-$HOME}"
DST="${2:-/mnt/synology/backups/home-backup}"
rsync -avh --delete --progress --dry-run "$SRC" "$DST"
EOF

  write_user_template "$storage_root/rsync_media_sync.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-/mnt/synology/downloads}"
DST="${2:-/mnt/synology/media}"
rsync -avh --progress --dry-run "$SRC" "$DST"
EOF

  write_user_template "$storage_root/recovery_notes.txt" <<'EOF'
Storage recovery quick notes
============================
Commands to verify availability:
  mdadm --version
  btrfs --version
  lvm version
  testdisk /list
  smartctl --scan

Common checks:
  lsblk -f
  cat /proc/mdstat
  pvs
  vgs
  lvs
EOF
  if [[ ! "$DRY_RUN" == true ]]; then
    run_as_user chmod +x "$storage_root/rsync_synology_backup.sh" "$storage_root/rsync_media_sync.sh" >>"$LOG_FILE" 2>&1 || true
  fi

  echo
  section_result_summary "Section 25 - Synology Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  [[ ${#failed_required[@]} -gt 0 ]] && warn "Required package failures: ${failed_required[*]}"
  success "Synology toolkit section completed."
}

# ---------- Section 26 ----------
section_26_docker_stack_installer() {
  show_section_header "Section 26 - Home Lab Docker Stack Installer"

  local extra_pkgs=(jq curl wget)
  local optional_pkgs=()
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local docker_root="${STARTING_HOME}/docker/stacks"
  local selection=""
  local chosen=()
  local chosen_dirs=()
  local stack_urls=()
  local uid gid
  uid="$(id -u "$STARTING_USER")"
  gid="$(id -g "$STARTING_USER")"

  if ! command_or_pkg_present docker; then
    warn "Docker is not installed yet. Section 26 works best after Section 4."
    if confirm "Run Section 4 - Docker Repo Setup / Validation now?" "Y"; then
      run_registered_section 4
    fi
  fi

  if ! command_or_pkg_present docker; then
    error "Docker is still not available. Cannot continue with Docker stacks."
    record_failure "docker-stacks-docker-missing"
    return 1
  fi

  warn_if_docker_group_not_active
  install_package_group "Docker Stack Installer" extra_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$docker_root" "$docker_root/portainer" "$docker_root/watchtower" "$docker_root/uptime-kuma" "$docker_root/dozzle" "$docker_root/filebrowser" "$docker_root/flaresolverr"

  echo
  echo "Choose Docker stacks to generate (space-separated numbers):"
  echo "  1) Portainer"
  echo "  2) Watchtower"
  echo "  3) Uptime Kuma"
  echo "  4) Dozzle"
  echo "  5) Filebrowser"
  echo "  6) FlareSolverr"
  read -r -p "Selection [1 3 4]: " selection
  selection="${selection:-1 3 4}"

  local portainer_port kuma_port dozzle_port filebrowser_port flaresolverr_port
  portainer_port="$(find_available_port 9000 9099 || echo 9000)"
  kuma_port="$(find_available_port 3001 3099 || echo 3001)"
  dozzle_port="$(find_available_port 8085 8185 || echo 8085)"
  filebrowser_port="$(find_available_port 8080 8180 || echo 8080)"
  flaresolverr_port="$(find_available_port 8191 8291 || echo 8191)"

  for item in $selection; do
    case "$item" in
      1) chosen+=("Portainer"); chosen_dirs+=("portainer"); stack_urls+=("Portainer: http://localhost:${portainer_port}"); write_compose_stack "$docker_root/portainer" <<EOT
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "${portainer_port}:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
EOT
      ;;
      2) chosen+=("Watchtower"); chosen_dirs+=("watchtower"); stack_urls+=("Watchtower: no web UI; check logs with docker logs watchtower"); write_compose_stack "$docker_root/watchtower" <<'EOT'
services:
  watchtower:
    image: ghcr.io/containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 86400
EOT
      ;;
      3) chosen+=("Uptime Kuma"); chosen_dirs+=("uptime-kuma"); stack_urls+=("Uptime Kuma: http://localhost:${kuma_port}"); write_compose_stack "$docker_root/uptime-kuma" <<EOT
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "${kuma_port}:3001"
    volumes:
      - ./data:/app/data
EOT
      ;;
      4) chosen+=("Dozzle"); chosen_dirs+=("dozzle"); stack_urls+=("Dozzle: http://localhost:${dozzle_port}"); write_compose_stack "$docker_root/dozzle" <<EOT
services:
  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    ports:
      - "${dozzle_port}:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOT
      ;;
      5)
        chosen+=("Filebrowser"); chosen_dirs+=("filebrowser"); stack_urls+=("Filebrowser: http://localhost:${filebrowser_port}")
        ensure_user_dirs "$docker_root/filebrowser/srv" "$docker_root/filebrowser/database" "$docker_root/filebrowser/config"
        if ! $DRY_RUN; then
          sudo chown -R "${uid}:${gid}" "$docker_root/filebrowser" >>"$LOG_FILE" 2>&1 || true
          sudo chmod -R u+rwX,g+rwX "$docker_root/filebrowser" >>"$LOG_FILE" 2>&1 || true
        fi
        write_compose_stack "$docker_root/filebrowser" <<EOT
services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    user: "${uid}:${gid}"
    ports:
      - "${filebrowser_port}:80"
    volumes:
      - ./srv:/srv
      - ./database:/database
      - ./config:/config
    command: --database /database/filebrowser.db --config /config/settings.json --address 0.0.0.0
EOT
      ;;
      6) chosen+=("FlareSolverr"); chosen_dirs+=("flaresolverr"); stack_urls+=("FlareSolverr: http://localhost:${flaresolverr_port}  API: http://localhost:${flaresolverr_port}/v1"); write_compose_stack "$docker_root/flaresolverr" <<EOT
services:
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    restart: unless-stopped
    ports:
      - "${flaresolverr_port}:8191"
    environment:
      - LOG_LEVEL=info
EOT
      ;;
      *) warn "Unknown Docker stack selection: $item" ;;
    esac
  done

  if [[ ${#chosen[@]} -eq 0 ]]; then
    warn "No Docker stacks selected."
    return 0
  fi

  write_url_note "$docker_root/stack_urls.txt" "$(printf '%s\n' "${stack_urls[@]}")"

  if confirm "Start only the selected/generated Docker stacks now with docker compose up -d?" "N"; then
    local stack
    for stack in "${chosen_dirs[@]}"; do
      [[ -f "$docker_root/$stack/compose.yml" ]] || continue
      if $DRY_RUN; then
        info "[DRY-RUN] Would start stack: $stack"
      else
        info "Starting Docker stack: $stack"
        (cd "$docker_root/$stack" && docker_compose_cmd pull && docker_compose_cmd up -d) >>"$LOG_FILE" 2>&1 \
          && success "Started Docker stack: $stack" \
          || warn "Could not start stack: $stack. Review: $docker_root/$stack/compose.yml and $LOG_FILE"
      fi
    done
  fi

  info "Generated Docker stacks: ${chosen[*]}"
  echo
  info "Access URLs / notes:"
  printf '  - %s\n' "${stack_urls[@]}"
  echo
  section_result_summary "Section 26 - Home Lab Docker Stack Installer" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  success "Docker stack installer section completed."
}

# ---------- Section 27 ----------
section_27_network_engineer_toolkit() {
  show_section_header "Section 27 - Network Engineer Toolkit"

  local dns_pkg
  dns_pkg="$(pkg_name_dns_tools)"
  local required_pkgs=(nmap tcpdump wireshark tshark iperf3 mtr traceroute net-tools iputils-ping "$dns_pkg" whois snmp snmpd sshpass expect lldpd ethtool arp-scan netcat-openbsd telnet socat curl jq)
  local optional_pkgs=()
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local tools_root="${STARTING_HOME}/Projects/network-tools"

  install_package_group "Network Engineer Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$tools_root"

  write_user_template "$tools_root/network_quick_check.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
echo "Host: $(hostname)"
echo
ip -brief address
echo
ip route
echo
ss -tulpn | head -n 40
echo
ping -c 3 8.8.8.8 || true
echo
dig +short openai.com || true
EOT

  write_user_template "$tools_root/dns_test.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${1:-openai.com}"
echo "Testing DNS for: $DOMAIN"
for resolver in 1.1.1.1 8.8.8.8 9.9.9.9; do
  echo
  echo "Resolver: $resolver"
  dig @"$resolver" "$DOMAIN" +short || true
done
EOT

  write_user_template "$tools_root/latency_monitor.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-8.8.8.8}"
ping "$TARGET"
EOT

  write_user_template "$tools_root/port_test.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
HOST="${1:?Usage: port_test.sh host port}"
PORT="${2:?Usage: port_test.sh host port}"
nc -vz "$HOST" "$PORT"
EOT

  write_user_template "$tools_root/snmp_walk_template.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
HOST="${1:-192.168.1.1}"
COMMUNITY="${2:-public}"
snmpwalk -v2c -c "$COMMUNITY" "$HOST" sysDescr
EOT

  if [[ ! "$DRY_RUN" == true ]]; then
    run_as_user chmod +x "$tools_root"/*.sh >>"$LOG_FILE" 2>&1 || true
  fi

  if command_exists systemctl && pkg_installed lldpd; then
    if confirm "Enable/start LLDP daemon for network discovery?" "Y"; then
      sudo systemctl enable --now lldpd >>"$LOG_FILE" 2>&1 \
        && success "lldpd enabled and started" \
        || warn "Could not enable/start lldpd"
    fi
  fi

  echo
  section_result_summary "Section 27 - Network Engineer Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  [[ ${#failed_required[@]} -gt 0 ]] && warn "Required package failures: ${failed_required[*]}"
  success "Network engineer toolkit section completed."
}

# ---------- Section 28 ----------
section_28_logging_diagnostics_toolkit() {
  show_section_header "Section 28 - Logging / Diagnostics Toolkit"

  local required_pkgs=(lnav jq curl less)
  local optional_pkgs=(multitail ccze grc)
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local log_root="${STARTING_HOME}/Projects/logging-diagnostics"

  install_package_group "Logging / Diagnostics Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$log_root"

  write_user_template "$log_root/journal_errors.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
journalctl -p 3 -xb --no-pager
EOT

  write_user_template "$log_root/apt_dpkg_errors.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
sudo lnav /var/log/apt/history.log /var/log/apt/term.log /var/log/dpkg.log
EOT

  write_user_template "$log_root/docker_logs_helper.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
CONTAINER="${1:-}"
if [[ -z "$CONTAINER" ]]; then
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo
  echo "Usage: $0 <container-name>"
  exit 0
fi
docker logs "$CONTAINER" --tail 200 -f
EOT

  write_user_template "$log_root/auth_log_review.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f /var/log/auth.log ]]; then
  sudo lnav /var/log/auth.log
else
  journalctl _COMM=sshd --no-pager | lnav
fi
EOT

  write_user_template "$log_root/logging_quick_reference.txt" <<'EOT'
Logging / diagnostics quick reference
=====================================
lnav examples:
  sudo lnav /var/log/syslog
  sudo lnav /var/log/apt/history.log /var/log/apt/term.log /var/log/dpkg.log
  journalctl -p 3 -xb --no-pager
  journalctl -u docker --since today

Docker logs:
  docker ps
  docker logs <container> --tail 100 -f

APT/dpkg repair clues:
  sudo dpkg --audit
  sudo apt-get install -f
EOT

  if [[ ! "$DRY_RUN" == true ]]; then
    run_as_user chmod +x "$log_root"/*.sh >>"$LOG_FILE" 2>&1 || true
  fi

  echo
  section_result_summary "Section 28 - Logging / Diagnostics Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  [[ ${#failed_required[@]} -gt 0 ]] && warn "Required package failures: ${failed_required[*]}"
  [[ ${#failed_optional[@]} -gt 0 ]] && warn "Optional package failures: ${failed_optional[*]}"
  success "Logging / diagnostics toolkit section completed."
}

# ---------- Section 29 ----------
section_29_media_download_power_toolkit() {
  show_section_header "Section 29 - Media / Download Power Toolkit"

  local required_pkgs=(yt-dlp ffmpeg mediainfo jq aria2)
  local optional_pkgs=(handbrake-cli atomicparsley python3-mutagen)
  local installed_now=() skipped=() failed_required=() failed_optional=()
  local media_root="${STARTING_HOME}/Projects/media-tools"
  local scripts_dir="${media_root}/scripts"
  local config_dir="${media_root}/config"
  local jd_dir="${STARTING_HOME}/Downloads/JDownloader"
  local media_dir="${STARTING_HOME}/Downloads/Media"
  local temp_dir="${STARTING_HOME}/Downloads/Temp"
  local aria2_dir="${STARTING_HOME}/.aria2"

  info "Installing media and download toolkit packages..."
  install_package_group "Media / Download Power Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional

  info "Creating media/download folder layout..."
  ensure_user_dirs "${STARTING_HOME}/Downloads" "$jd_dir" "$media_dir" "$temp_dir" "$media_root" "$scripts_dir" "$config_dir" "$aria2_dir"

  write_user_template "$scripts_dir/yt-dlp-best.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <url> [extra yt-dlp args...]" >&2
  exit 1
fi
yt-dlp \
  -f "bestvideo+bestaudio/best" \
  --merge-output-format mp4 \
  --embed-metadata \
  --embed-thumbnail \
  --add-metadata \
  --no-playlist \
  "$@"
EOT

  write_user_template "$scripts_dir/yt-dlp-audio.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <url> [extra yt-dlp args...]" >&2
  exit 1
fi
yt-dlp -x --audio-format mp3 --audio-quality 0 "$@"
EOT

  write_user_template "$scripts_dir/convert-to-mp4.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "$0") <input-file> <output-file.mp4>" >&2
  exit 1
fi
ffmpeg -i "$1" -c:v libx264 -preset fast -crf 23 -c:a aac "$2"
EOT

  write_user_template "$scripts_dir/media-info.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <media-file>" >&2
  exit 1
fi
mediainfo "$1"
EOT

  write_user_template "$scripts_dir/flaresolverr-test.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <url>" >&2
  exit 1
fi
curl -sS -X POST http://localhost:8192/v1 \
  -H "Content-Type: application/json" \
  -d "{\"cmd\":\"request.get\",\"url\":\"$1\"}" | jq .
EOT

  write_user_template "$scripts_dir/aria2-download.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <url-or-metalink> [extra aria2c args...]" >&2
  exit 1
fi
aria2c --conf-path="$HOME/.aria2/aria2.conf" "$@"
EOT

  write_user_template "$aria2_dir/aria2.conf" <<'EOT'
continue=true
max-connection-per-server=16
split=16
min-split-size=1M
max-concurrent-downloads=3
file-allocation=none
summary-interval=60
EOT

  write_user_template "$media_root/jdownloader_optimization.txt" <<'EOT'
JDownloader optimization notes for LMDE 7 + v41

Recommended JDownloader settings:
1. Settings > Account Manager
   - Add premium accounts such as Real-Debrid where applicable.
   - Keep premium accounts enabled and preferred.

2. Settings > Downloads
   - Max simultaneous downloads: 2 to 5
   - Max chunks per download: 4 to 8 for most premium/direct links
   - Download folder suggestion: ~/Downloads/JDownloader

3. Settings > LinkGrabber
   - Enable clipboard monitoring if you want auto-capture.
   - Enable deep decrypt analysis for stubborn links.
   - Use auto-confirm only if you trust the sources you are collecting from.

4. Settings > Reconnect
   - Disable reconnect when using Real-Debrid or premium resolvers.

5. Captcha / browser workflow
   - Use Brave with the MyJDownloader browser extension for Cloudflare/login/cookie-heavy sites.
   - FlareSolverr is useful as an assist tool, but JDownloader does not have a native global FlareSolverr setting.
EOT

  write_user_template "$media_root/real-debrid-workflow.txt" <<'EOT'
Real-Debrid + JDownloader workflow

1. Open JDownloader > Settings > Account Manager > Add.
2. Search for real-debrid.com and add the account.
3. If normal login fails, use the Real-Debrid API token from your account page where supported by the plugin.
4. Paste supported host links or magnet links into JDownloader.
5. JDownloader should resolve supported links through Real-Debrid and download direct/premium links.

Best practices:
- Keep reconnect disabled.
- Prefer 2 to 5 simultaneous downloads.
- Use 4 to 8 chunks per download as a starting point.
- If a link does not use Real-Debrid, confirm the account is enabled and the host is supported.
EOT

  write_user_template "$media_root/browser-to-jd-guide.txt" <<'EOT'
Brave Browser + MyJDownloader workflow

Recommended setup:
1. Create a dedicated Brave profile called Bryan Downloads.
2. Install the MyJDownloader browser extension in that profile.
3. Log into the same MyJDownloader account inside JDownloader and the browser extension.
4. For protected sites, open the page in Brave, complete any browser challenge, then send links to JDownloader from the extension.

For stubborn sites:
- Temporarily lower Brave Shields for that specific site.
- Keep cookies/session data in the dedicated download profile.
- Use FlareSolverr test helper only for troubleshooting or extracting challenge-solved responses.
EOT

  write_user_template "$media_root/media_folder_layout.txt" <<EOT
Recommended folder layout created by Section 29:

${STARTING_HOME}/Downloads/JDownloader
${STARTING_HOME}/Downloads/Media
${STARTING_HOME}/Downloads/Temp
${STARTING_HOME}/Projects/media-tools
${STARTING_HOME}/Projects/media-tools/scripts
${STARTING_HOME}/Projects/media-tools/config

Suggested use:
- JDownloader default folder: ${STARTING_HOME}/Downloads/JDownloader
- Temporary downloads: ${STARTING_HOME}/Downloads/Temp
- Finished media/manual organization: ${STARTING_HOME}/Downloads/Media
EOT

  if ! $DRY_RUN; then
    run_as_user chmod +x \
      "$scripts_dir/yt-dlp-best.sh" \
      "$scripts_dir/yt-dlp-audio.sh" \
      "$scripts_dir/convert-to-mp4.sh" \
      "$scripts_dir/media-info.sh" \
      "$scripts_dir/flaresolverr-test.sh" \
      "$scripts_dir/aria2-download.sh" >>"$LOG_FILE" 2>&1 || true
  fi

  echo
  info "Media / Download Power Toolkit paths:"
  echo "  Scripts        : $scripts_dir"
  echo "  JDownloader dir: $jd_dir"
  echo "  Media dir      : $media_dir"
  echo "  Temp dir       : $temp_dir"
  echo "  aria2 config   : $aria2_dir/aria2.conf"

  echo
  info "Quick examples:"
  echo "  $scripts_dir/yt-dlp-best.sh 'https://example.com/video'"
  echo "  $scripts_dir/yt-dlp-audio.sh 'https://example.com/video'"
  echo "  $scripts_dir/convert-to-mp4.sh input.mkv output.mp4"
  echo "  $scripts_dir/flaresolverr-test.sh 'https://example.com'"

  section_result_summary "Section 29 - Media / Download Power Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"

  if ((${#failed_required[@]} > 0)); then
    warn "Media toolkit completed with required package failures: ${failed_required[*]}"
    return 1
  fi

  if ((${#failed_optional[@]} > 0)); then
    warn "Optional media packages failed or were unavailable: ${failed_optional[*]}"
  fi

  success "Media / Download Power Toolkit section completed."
}


# ---------- Section 30 ----------
section_30_laptop_brightness_backlight_toolkit() {
  show_section_header "Section 30 - Laptop Brightness / Backlight Toolkit"

  local required_pkgs=(brightnessctl x11-xserver-utils)
  local optional_pkgs=()
  local installed_now=()
  local skipped=()
  local failed_required=()
  local failed_optional=()
  local display_root="${STARTING_HOME}/Projects/display-brightness"
  local scripts_dir="${display_root}/scripts"
  local backlight_dirs=()
  local bl="" name="" current="" max="" actual="" answer=""

  install_package_group "Laptop Brightness / Backlight Toolkit" required_pkgs optional_pkgs installed_now skipped failed_required failed_optional
  ensure_user_dirs "$display_root" "$scripts_dir"

  echo
  info "Detecting kernel backlight interfaces under /sys/class/backlight..."
  if compgen -G "/sys/class/backlight/*" >/dev/null; then
    for bl in /sys/class/backlight/*; do
      [[ -d "$bl" ]] || continue
      backlight_dirs+=("$bl")
      name="$(basename "$bl")"
      current="$(cat "$bl/brightness" 2>/dev/null || echo "n/a")"
      max="$(cat "$bl/max_brightness" 2>/dev/null || echo "n/a")"
      actual="$(cat "$bl/actual_brightness" 2>/dev/null || echo "n/a")"
      echo "  - ${name}: brightness=${current}, actual=${actual}, max=${max}"
    done
  else
    warn "No /sys/class/backlight interfaces were found. This can happen on some GPU/driver combinations."
    record_optional_failure "backlight-interface-not-found"
  fi

  echo
  info "brightnessctl device information:"
  if command_exists brightnessctl; then
    brightnessctl info 2>&1 | tee -a "$LOG_FILE" || warn "brightnessctl could not read a backlight device."
  fi

  echo
  if confirm "Test setting brightness to 80% with brightnessctl now?" "N"; then
    if sudo brightnessctl set 80% 2>&1 | tee -a "$LOG_FILE"; then
      success "brightnessctl set 80% completed."
    else
      warn "brightnessctl set 80% failed. This is often permissions or driver/backlight mapping."
      record_failure "brightnessctl-set-test"
    fi
  fi

  echo
  if ! id -nG "$STARTING_USER" 2>/dev/null | tr ' ' '\n' | grep -Fxq video; then
    warn "User ${STARTING_USER} is not currently in the video group."
    if confirm "Add ${STARTING_USER} to the video group for brightness/backlight access?" "Y"; then
      if sudo usermod -aG video "$STARTING_USER" >>"$LOG_FILE" 2>&1; then
        success "Added ${STARTING_USER} to the video group. Log out/in or reboot for this to fully apply."
      else
        warn "Could not add ${STARTING_USER} to the video group."
        record_failure "video-group-add"
      fi
    fi
  else
    success "User ${STARTING_USER} is already in the video group."
  fi

  write_user_template "$scripts_dir/brightness-info.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail

echo "Backlight interfaces:"
if compgen -G "/sys/class/backlight/*" >/dev/null; then
  for bl in /sys/class/backlight/*; do
    [[ -d "$bl" ]] || continue
    echo "--- $(basename "$bl") ---"
    printf 'brightness: '; cat "$bl/brightness" 2>/dev/null || true
    printf 'actual    : '; cat "$bl/actual_brightness" 2>/dev/null || true
    printf 'max       : '; cat "$bl/max_brightness" 2>/dev/null || true
  done
else
  echo "No /sys/class/backlight entries found."
fi

echo
echo "brightnessctl:"
brightnessctl info 2>/dev/null || true

echo
echo "Current displays:"
xrandr --verbose 2>/dev/null | awk '/ connected/{print $1}' || true
EOT
  run_as_user chmod +x "$scripts_dir/brightness-info.sh" >>"$LOG_FILE" 2>&1 || true

  write_user_template "$scripts_dir/set-brightness.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
level="${1:-80%}"
if command -v brightnessctl >/dev/null 2>&1; then
  brightnessctl set "$level"
else
  echo "brightnessctl is not installed." >&2
  exit 1
fi
EOT
  run_as_user chmod +x "$scripts_dir/set-brightness.sh" >>"$LOG_FILE" 2>&1 || true

  write_user_template "$scripts_dir/xrandr-brightness.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
level="${1:-0.85}"
out="${2:-}"
if [[ -z "$out" ]]; then
  out="$(xrandr --verbose | awk '/ connected/{print $1; exit}')"
fi
if [[ -z "$out" ]]; then
  echo "Could not detect a connected xrandr output." >&2
  exit 1
fi
xrandr --output "$out" --brightness "$level"
echo "Set software brightness for $out to $level"
EOT
  run_as_user chmod +x "$scripts_dir/xrandr-brightness.sh" >>"$LOG_FILE" 2>&1 || true

  write_user_template "$display_root/backlight_troubleshooting_guide.txt" <<'EOT'
Laptop Brightness / Backlight Troubleshooting Guide
===================================================

Recommended order:
1. Inspect interfaces:
   ~/Projects/display-brightness/scripts/brightness-info.sh

2. Try hardware backlight control:
   brightnessctl info
   brightnessctl set 80%
   brightnessctl set +10%
   brightnessctl set 10%-

3. If permission is denied, add your user to the video group and reboot/log out-in:
   sudo usermod -aG video "$USER"

4. If brightness keys move the slider but the panel brightness does not change, test one GRUB backlight parameter at a time:
   acpi_backlight=native
   acpi_backlight=vendor
   acpi_backlight=video
   acpi_backlight=none

5. After changing GRUB:
   sudo update-grub
   sudo reboot

6. Software fallback only darkens the image and does not change real panel backlight power:
   ~/Projects/display-brightness/scripts/xrandr-brightness.sh 0.85

Rollback GRUB change:
- Edit /etc/default/grub and remove the acpi_backlight=... parameter.
- Run sudo update-grub and reboot.
- A timestamped backup is created before this script changes /etc/default/grub.
EOT

  echo
  warn "GRUB acpi_backlight changes require a reboot and can improve or worsen brightness behavior depending on laptop/GPU firmware."
  warn "Try only one parameter at a time. The safest first test is usually acpi_backlight=native; vendor/video/none are fallback tests."
  if confirm "Add or replace a GRUB acpi_backlight parameter now?" "N"; then
    echo "Choose one parameter to apply:"
    echo "  1) acpi_backlight=native  - often best first test on modern laptops"
    echo "  2) acpi_backlight=vendor  - prefer vendor driver such as thinkpad_acpi/asus/wmi"
    echo "  3) acpi_backlight=video   - force ACPI video backlight interface"
    echo "  4) acpi_backlight=none    - disable ACPI backlight interface"
    echo "  5) remove existing acpi_backlight parameter"
    read -r -p "Selection [1-5]: " answer

    local param=""
    case "$answer" in
      1) param="acpi_backlight=native" ;;
      2) param="acpi_backlight=vendor" ;;
      3) param="acpi_backlight=video" ;;
      4) param="acpi_backlight=none" ;;
      5) param="" ;;
      *) warn "Invalid selection. Skipping GRUB change."; param="__skip__" ;;
    esac

    if [[ "$param" != "__skip__" ]]; then
      local grub_file="/etc/default/grub"
      if [[ ! -f "$grub_file" ]]; then
        warn "$grub_file not found; cannot apply GRUB parameter."
        record_failure "grub-file-missing-brightness"
      else
        backup_file "$grub_file" || true
        if $DRY_RUN; then
          info "[DRY-RUN] Would update GRUB_CMDLINE_LINUX_DEFAULT with ${param:-no acpi_backlight parameter}"
        else
          sudo python3 - "$grub_file" "$param" <<'PYGRUB'
import re, sys
path, param = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read()
pattern = re.compile(r'^(GRUB_CMDLINE_LINUX_DEFAULT=)(["\'])(.*?)(\2)', re.M)
match = pattern.search(text)
if not match:
    text += '\nGRUB_CMDLINE_LINUX_DEFAULT="{}"\n'.format(param)
else:
    prefix, quote, value, suffix = match.groups()
    parts = [part for part in value.split() if not part.startswith('acpi_backlight=')]
    if param:
        parts.append(param)
    new = prefix + quote + ' '.join(parts) + quote
    text = pattern.sub(new, text, count=1)
open(path, 'w', encoding='utf-8').write(text)
PYGRUB
          if sudo update-grub 2>&1 | tee -a "$LOG_FILE"; then
            success "Updated GRUB. Reboot is required to test the brightness behavior."
          else
            warn "update-grub failed. Review $LOG_FILE."
            record_failure "update-grub-brightness"
          fi
        fi
      fi
    fi
  fi

  echo
  info "Useful commands:"
  echo "  brightnessctl info"
  echo "  brightnessctl set 80%"
  echo "  ${scripts_dir}/brightness-info.sh"
  echo "  ${scripts_dir}/xrandr-brightness.sh 0.85"
  echo
  section_result_summary "Section 30 - Laptop Brightness / Backlight Toolkit" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  success "Laptop Brightness / Backlight Toolkit section completed."
}

# ---------- Section 31 ----------
section_31_desktop_environment_awareness() {
  show_section_header "Section 31 - Desktop Environment Awareness / Tweaks"

  # This section is intentionally conservative. It discovers the desktop
  # environment and file manager, creates a report, and only applies settings
  # when the detected schema/key is present and writable.
  detect_os
  detect_desktop_environment

  local report_dir="${STARTING_HOME}/Projects/desktop-awareness"
  local report_file="${report_dir}/desktop_environment_report.txt"
  local scripts_dir="${report_dir}/scripts"
  local failed_required=()
  local failed_optional=()
  local skipped=()

  ensure_user_dirs "$report_dir" "$scripts_dir"

  info "Detected desktop environment : $DESKTOP_ENVIRONMENT"
  info "Detected display server      : $DISPLAY_SERVER"
  info "Detected file manager        : $FILE_MANAGER"

  local desktop_pkgs=(dconf-cli dbus-x11 xdg-user-dirs)
  install_package_group "Desktop awareness support packages" desktop_pkgs skipped failed_required failed_optional

  write_user_template "$report_file" <<EOF_REPORT
Desktop Environment Awareness Report
Generated: $(date)

System
------
OS: ${OS_PRETTY_NAME}
Distro: ${DISTRO_NAME}
Family: ${DISTRO_FAMILY}
APT codename: ${APT_CODENAME}

Desktop
-------
Desktop environment: ${DESKTOP_ENVIRONMENT}
Display server: ${DISPLAY_SERVER}
File manager: ${FILE_MANAGER}
XDG_CURRENT_DESKTOP: $(run_as_user_shell 'printf %s "${XDG_CURRENT_DESKTOP:-}"' 2>/dev/null || true)
DESKTOP_SESSION: $(run_as_user_shell 'printf %s "${DESKTOP_SESSION:-}"' 2>/dev/null || true)
XDG_SESSION_TYPE: $(run_as_user_shell 'printf %s "${XDG_SESSION_TYPE:-}"' 2>/dev/null || true)

Guidance
--------
- Cinnamon/LMDE normally uses Nemo and Cinnamon-specific gsettings schemas.
- Ubuntu GNOME and Zorin normally use Nautilus and GNOME schemas.
- Existing Nemo sections are safe to skip on non-Nemo systems.
- Apply only settings where gsettings reports the key exists and is writable.
EOF_REPORT

  write_user_template "${scripts_dir}/desktop-info.sh" <<'EOF_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
echo "DESKTOP_SESSION=${DESKTOP_SESSION:-}"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
echo
echo "Available file managers:"
for cmd in nemo nautilus thunar dolphin; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  $cmd -> $(command -v "$cmd")"
  fi
done
echo
echo "Common GNOME interface settings:"
gsettings list-recursively org.gnome.desktop.interface 2>/dev/null | grep -E 'clock|font|color-scheme|gtk-theme|icon-theme' || true
EOF_SCRIPT
  run_as_user chmod +x "${scripts_dir}/desktop-info.sh" >>"$LOG_FILE" 2>&1 || true

  echo
  info "Optional safe desktop tweaks:"
  if [[ "$DESKTOP_ENVIRONMENT" == "gnome" || "$DESKTOP_ENVIRONMENT" == "zorin-gnome" ]]; then
    if confirm "Apply safe GNOME/Zorin preference: show date in top bar?" "Y"; then
      set_gsetting_if_supported org.gnome.desktop.interface clock-show-date true
    fi
    if confirm "Apply safe GNOME/Zorin preference: prefer dark color scheme if supported?" "N"; then
      set_gsetting_if_supported org.gnome.desktop.interface color-scheme "'prefer-dark'"
    fi
  elif [[ "$DESKTOP_ENVIRONMENT" == "cinnamon" ]]; then
    if confirm "Apply safe Cinnamon preference: show date in panel clock?" "Y"; then
      set_gsetting_if_supported org.cinnamon.desktop.interface clock-show-date true
    fi
    if confirm "Apply safe Cinnamon preference: use 24-hour clock?" "Y"; then
      set_gsetting_if_supported org.cinnamon.desktop.interface clock-use-24h true
    fi
  else
    skipped+=("desktop-specific-tweaks")
    warn "No automatic tweaks selected for detected desktop: $DESKTOP_ENVIRONMENT"
  fi

  echo
  info "Generated files:"
  echo "  $report_file"
  echo "  ${scripts_dir}/desktop-info.sh"
  echo
  section_result_summary "Section 31 - Desktop Environment Awareness / Tweaks" "${#failed_required[@]}" "${#failed_optional[@]}" "${#skipped[@]}"
  success "Desktop Environment Awareness section completed."
}

# ---------- Section 32 ----------
section_32_diagnostics_dashboard_autofix() {
  show_section_header "Section 32 - Diagnostics Dashboard / Auto-Fix"

  # This section is intentionally conservative. It collects a readable health
  # dashboard first, then offers small repair actions one-by-one. Risky fixes are
  # not applied silently.
  detect_os

  local ts dashboard_dir html_file txt_file scripts_dir
  local required_failed=()
  local optional_failed=()
  local skipped=()
  ts="$(date +%Y%m%d_%H%M%S)"
  dashboard_dir="${STARTING_HOME}/Projects/system-health-dashboard/health_${ts}"
  scripts_dir="${STARTING_HOME}/Projects/system-health-dashboard/scripts"
  html_file="${dashboard_dir}/dashboard.html"
  txt_file="${dashboard_dir}/dashboard.txt"

  ensure_user_dirs \
    "${STARTING_HOME}/Projects/system-health-dashboard" \
    "$dashboard_dir" \
    "$scripts_dir"

  info "Collecting system health data into: $dashboard_dir"

  # Collect core system health data. Commands are allowed to fail because some
  # systems do not have every service/tool installed.
  {
    echo "System Health Dashboard"
    echo "Generated: $(date)"
    echo
    echo "System"
    echo "------"
    echo "User: $STARTING_USER"
    echo "Home: $STARTING_HOME"
    echo "OS: ${OS_PRETTY_NAME:-unknown}"
    echo "Distro: ${DISTRO_NAME:-unknown}"
    echo "Distro family: ${DISTRO_FAMILY:-unknown}"
    echo "Kernel: $(uname -r)"
    echo "Architecture: ${ARCH:-unknown}"
    echo

    echo "Disk Usage"
    echo "----------"
    df -hT 2>/dev/null || true
    echo

    echo "Memory"
    echo "------"
    free -h 2>/dev/null || true
    echo

    echo "Failed systemd Units"
    echo "--------------------"
    systemctl --failed --no-pager 2>/dev/null || true
    echo

    echo "Critical Boot Journal Entries"
    echo "-----------------------------"
    journalctl -p 3 -xb --no-pager 2>/dev/null | tail -n 80 || true
    echo

    echo "APT / DPKG Audit"
    echo "----------------"
    dpkg --audit 2>/dev/null || true
    apt-get check 2>&1 || true
    echo

    echo "Networking"
    echo "----------"
    ip -brief addr 2>/dev/null || true
    echo
    ip route 2>/dev/null || true
    echo

    echo "Listening Ports"
    echo "---------------"
    sudo ss -tulpn 2>/dev/null || ss -tulpn 2>/dev/null || true
    echo

    echo "Docker"
    echo "------"
    if command_exists docker; then
      docker version 2>/dev/null || sudo docker version 2>/dev/null || true
      echo
      docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    else
      echo "Docker command not found."
    fi
    echo

    echo "Mounts / fstab Validation Preview"
    echo "---------------------------------"
    findmnt --verify 2>&1 || true
    echo

    echo "Large Home Directories"
    echo "----------------------"
    du -h --max-depth=1 "$STARTING_HOME" 2>/dev/null | sort -h | tail -n 20 || true
  } > "$txt_file"

  # Write a simple local HTML dashboard. This avoids requiring a web server and
  # gives you a quick browser-readable health view.
  {
    echo '<!doctype html><html><head><meta charset="utf-8">'
    echo '<title>System Health Dashboard</title>'
    echo '<style>body{font-family:system-ui,Arial,sans-serif;margin:2rem;line-height:1.4} pre{background:#111;color:#eee;padding:1rem;border-radius:8px;overflow:auto} h1{margin-bottom:.2rem}.muted{color:#666}</style>'
    echo '</head><body>'
    echo '<h1>System Health Dashboard</h1>'
    echo "<p class=\"muted\">Generated: $(date)</p>"
    echo '<pre>'
    sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$txt_file"
    echo '</pre>'
    echo '</body></html>'
  } > "$html_file"

  fix_user_file_ownership "${STARTING_HOME}/Projects/system-health-dashboard" || true

  # Create helper scripts so future diagnostics are repeatable without opening
  # the full setup script.
  write_user_template "${scripts_dir}/health-dashboard-refresh.sh" <<'EOF_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
out="$HOME/Projects/system-health-dashboard/quick_health_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$out")"
{
  echo "Quick Health Report - $(date)"
  echo
  echo "== systemctl --failed =="
  systemctl --failed --no-pager || true
  echo
  echo "== journal critical/errors this boot =="
  journalctl -p 3 -xb --no-pager | tail -n 100 || true
  echo
  echo "== disk =="
  df -hT || true
  echo
  echo "== apt/dpkg =="
  dpkg --audit || true
  apt-get check 2>&1 || true
  echo
  echo "== listening ports =="
  ss -tulpn || true
} > "$out"
echo "Wrote: $out"
EOF_SCRIPT
  run_as_user chmod +x "${scripts_dir}/health-dashboard-refresh.sh" >>"$LOG_FILE" 2>&1 || true

  write_user_template "${scripts_dir}/safe-auto-fix.sh" <<'EOF_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
sudo dpkg --configure -a
sudo apt-get install -f -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
sudo apt-get update
sudo systemctl reset-failed || true
echo "Basic safe repair actions completed."
EOF_SCRIPT
  run_as_user chmod +x "${scripts_dir}/safe-auto-fix.sh" >>"$LOG_FILE" 2>&1 || true

  echo
  info "Dashboard files created:"
  echo "  Text : $txt_file"
  echo "  HTML : $html_file"
  echo "  Tools: $scripts_dir"

  # Guided auto-fix actions. Each action is gated behind a prompt so the section
  # can be used as a diagnostic dashboard without changing the system.
  echo
  info "Optional safe auto-fix actions"
  warn "Each action will ask before it changes anything."

  if confirm "Run dpkg --configure -a and apt-get install -f repair now?" "N"; then
    wait_for_apt_lock || required_failed+=("apt-lock")
    sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>&1 | tee -a "$LOG_FILE" || required_failed+=("dpkg-configure")
    wait_for_apt_lock || required_failed+=("apt-lock")
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold 2>&1 | tee -a "$LOG_FILE" || required_failed+=("apt-fix-broken")
  else
    skipped+=("apt-dpkg-repair")
  fi

  if confirm "Clean apt package cache and remove unused packages?" "N"; then
    wait_for_apt_lock || optional_failed+=("apt-lock")
    sudo apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE" || optional_failed+=("apt-autoremove")
    sudo apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE" || optional_failed+=("apt-autoclean")
  else
    skipped+=("apt-cleanup")
  fi

  if command_exists systemctl && confirm "Reset failed systemd unit state?" "N"; then
    sudo systemctl reset-failed >>"$LOG_FILE" 2>&1 || optional_failed+=("systemctl-reset-failed")
  else
    skipped+=("systemctl-reset-failed")
  fi

  if command_exists docker && confirm "Restart Docker service if it is installed?" "N"; then
    sudo systemctl restart docker >>"$LOG_FILE" 2>&1 || optional_failed+=("docker-restart")
    if systemctl is-active --quiet docker; then
      success "Docker service is active after restart."
    else
      warn "Docker service is not active after restart."
    fi
  else
    skipped+=("docker-restart")
  fi

  if confirm "Validate fstab and run mount -a?" "N"; then
    findmnt --verify 2>&1 | tee -a "$LOG_FILE" || optional_failed+=("findmnt-verify")
    sudo mount -a 2>&1 | tee -a "$LOG_FILE" || optional_failed+=("mount-a")
  else
    skipped+=("fstab-mount-a")
  fi

  if confirm "Open the HTML dashboard now?" "Y"; then
    if command_exists xdg-open; then
      run_as_user xdg-open "$html_file" >>"$LOG_FILE" 2>&1 &
    else
      warn "xdg-open is not available. Open manually: $html_file"
    fi
  fi

  echo
  section_result_summary "Section 32 - Diagnostics Dashboard / Auto-Fix" "${#required_failed[@]}" "${#optional_failed[@]}" "${#skipped[@]}"

  if ((${#required_failed[@]} > 0)); then
    warn "Diagnostics Dashboard completed with required repair warnings: ${required_failed[*]}"
    return 1
  fi

  if ((${#optional_failed[@]} > 0)); then
    warn "Diagnostics Dashboard completed with optional repair warnings: ${optional_failed[*]}"
  else
    success "Diagnostics Dashboard / Auto-Fix section completed."
  fi
}

# ---------- Menu ----------
section_exists() {
  [[ -n "${SECTION_FUNCS[$1]:-}" ]]
}

run_registered_section() {
  local section_id="$1"
  if ! section_exists "$section_id"; then
    warn "Unknown section: $section_id"
    return 1
  fi
  run_section "$section_id" "${SECTION_FUNCS[$section_id]}"
}

show_section_registry_summary() {
  local group="$1"
  local sid
  for sid in "${SECTION_IDS[@]}"; do
    [[ "${SECTION_GROUPS[$sid]:-}" == "$group" ]] || continue
    format_menu_item "$sid" "Section ${sid} - ${SECTION_LABELS[$sid]}"
  done
}

run_group_sections() {
  local group="$1"
  local sid
  for sid in "${SECTION_IDS[@]}"; do
    [[ "${SECTION_GROUPS[$sid]:-}" == "$group" ]] || continue
    if confirm "Run Section ${sid} - ${SECTION_LABELS[$sid]}?" "Y"; then
      run_registered_section "$sid"
    fi
  done
}

show_submenu() {
  local group="$1"
  clear
  echo -e "${BOLD}${CYAN}${GROUP_LABELS[$group]}${NC}"
  echo -e "${CYAN}Log file   : ${LOG_FILE}${NC}"
  echo -e "${CYAN}Report file: ${REPORT_FILE}${NC}"
  echo
  echo -e "${GREEN}Green${NC} = completed   ${RED}Red${NC} = failed   ${YELLOW}Yellow${NC} = running"
  echo
  show_section_registry_summary "$group"
  echo " a) Run all sections in this submenu"
  echo " b) Back"
  echo
}

handle_submenu() {
  local group="$1"
  local choice=""
  while true; do
    show_submenu "$group"
    read -r -p "Select a section number, 'a', or 'b': " choice
    case "$choice" in
      a|A)
        run_group_sections "$group"
        press_enter
        ;;
      b|B)
        return 0
        ;;
      ''|*[!0-9]*)
        warn "Invalid selection."
        press_enter
        ;;
      *)
        if [[ "${SECTION_GROUPS[$choice]:-}" == "$group" ]]; then
          run_registered_section "$choice"
        else
          warn "Section $choice is not part of ${GROUP_LABELS[$group]}"
        fi
        press_enter
        ;;
    esac
  done
}

run_all_sections() {
  local sid
  for sid in "${SECTION_IDS[@]}"; do
    if confirm "Run Section ${sid} - ${SECTION_LABELS[$sid]}?" "Y"; then
      run_registered_section "$sid"
    fi
  done
}

# ---------- Smart Navigation Helpers (v48) ----------
# These helpers make the script easier for new users by allowing them to
# search for sections, save frequently used sections as favorites, and run
# an entire category without hunting through submenus.
section_matches_query() {
  local sid="$1"
  local query_lc="$2"
  local group="${SECTION_GROUPS[$sid]:-}"
  local haystack
  haystack="${sid} ${SECTION_LABELS[$sid]} ${GROUP_LABELS[$group]:-} ${group}"
  haystack="$(printf '%s' "$haystack" | tr '[:upper:]' '[:lower:]')"
  [[ "$haystack" == *"$query_lc"* ]]
}

search_sections() {
  clear
  echo -e "${BOLD}${CYAN}Search Sections${NC}"
  echo
  local query query_lc sid matches=()
  read -r -p "Search by section number, name, or category: " query
  query_lc="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$query_lc" ]]; then
    warn "Search term cannot be empty."
    return 0
  fi

  echo
  for sid in "${SECTION_IDS[@]}"; do
    if section_matches_query "$sid" "$query_lc"; then
      print_section_with_category "$sid"
      matches+=("$sid")
    fi
  done

  if ((${#matches[@]} == 0)); then
    warn "No matching sections found for: $query"
    return 0
  fi

  echo
  local choice
  read -r -p "Enter a section number to run it now, or press Enter to go back: " choice
  if [[ -n "$choice" ]]; then
    if section_exists "$choice"; then
      run_registered_section "$choice"
    else
      warn "Unknown section: $choice"
    fi
  fi
}

favorite_exists() {
  local sid="$1"
  [[ -f "$FAVORITES_FILE" ]] && grep -Fxq "$sid" "$FAVORITES_FILE"
}

add_favorite_section() {
  local sid="$1"
  if ! section_exists "$sid"; then
    warn "Unknown section: $sid"
    return 1
  fi
  touch "$FAVORITES_FILE"
  if favorite_exists "$sid"; then
    success "Section $sid is already a favorite."
  else
    echo "$sid" >> "$FAVORITES_FILE"
    success "Added Section $sid to favorites."
  fi
}

remove_favorite_section() {
  local sid="$1"
  if [[ ! -f "$FAVORITES_FILE" ]]; then
    warn "No favorites file exists yet."
    return 0
  fi
  grep -Fxv "$sid" "$FAVORITES_FILE" > "${FAVORITES_FILE}.tmp" || true
  mv "${FAVORITES_FILE}.tmp" "$FAVORITES_FILE"
  success "Removed Section $sid from favorites if it existed."
}

list_favorite_sections() {
  if [[ ! -s "$FAVORITES_FILE" ]]; then
    warn "No favorites saved yet."
    return 1
  fi
  local sid
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    if section_exists "$sid"; then
      print_section_with_category "$sid"
    fi
  done < "$FAVORITES_FILE"
}

run_favorite_sections() {
  if [[ ! -s "$FAVORITES_FILE" ]]; then
    warn "No favorites saved yet."
    return 0
  fi
  local sid
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    if section_exists "$sid" && confirm "Run Section ${sid} - ${SECTION_LABELS[$sid]}?" "Y"; then
      run_registered_section "$sid"
    fi
  done < "$FAVORITES_FILE"
}

manage_favorites() {
  local choice sid
  while true; do
    clear
    echo -e "${BOLD}${CYAN}Favorite Sections${NC}"
    echo
    list_favorite_sections || true
    echo
    echo "1) Add a favorite section"
    echo "2) Remove a favorite section"
    echo "3) Run favorite sections"
    echo "4) Back"
    echo
    read -r -p "Select an option [1-4]: " choice
    case "$choice" in
      1) read -r -p "Section number to add: " sid; add_favorite_section "$sid"; press_enter ;;
      2) read -r -p "Section number to remove: " sid; remove_favorite_section "$sid"; press_enter ;;
      3) run_favorite_sections; press_enter ;;
      4) return 0 ;;
      *) warn "Invalid selection."; press_enter ;;
    esac
  done
}

run_category_selector() {
  local groups=(core terminal gui apps health storage automation infrastructure)
  local choice group idx=1
  clear
  echo -e "${BOLD}${CYAN}Run Sections by Category${NC}"
  echo
  for group in "${groups[@]}"; do
    printf "%2d) %b%s${NC}\n" "$idx" "$(group_color "$group")" "${GROUP_LABELS[$group]}"
    idx=$((idx + 1))
  done
  echo " 9) Back"
  echo
  read -r -p "Select a category [1-9]: " choice
  if [[ "$choice" == "9" ]]; then
    return 0
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#groups[@]} )); then
    group="${groups[$((choice - 1))]}"
    run_group_sections "$group"
  else
    warn "Invalid category selection."
  fi
}

show_menu() {
  clear
  echo -e "${BOLD}${CYAN}LMDE / Ubuntu / Zorin Interactive Setup Script v48${NC}"
  echo -e "${CYAN}Log file         : ${LOG_FILE}${NC}"
  echo -e "${CYAN}Report file      : ${REPORT_FILE}${NC}"
  echo -e "${CYAN}Dry-run          : ${DRY_RUN}${NC}"
  echo -e "${CYAN}Non-interactive  : ${NON_INTERACTIVE}${NC}"
  echo
  echo -e "${GREEN}Green${NC} = completed   ${RED}Red${NC} = failed   ${YELLOW}Yellow${NC} = running"
  echo
  echo " 1) Base System Setup"
  echo " 2) Terminal UI Enhancements"
  echo " 3) GUI Enhancements"
  echo " 4) Applications and Productivity"
  echo " 5) System Health / Security Check"
  echo " 6) Storage / Mounting"
  echo " 7) System External Automation"
  echo " 8) Full Infrastructure Toolkit"
  echo " 9) Run ALL sections (prompt before each)"
  echo "10) Show all sections"
  echo "11) Search sections"
  echo "12) Favorite sections"
  echo "13) Run sections by category"
  echo "14) Exit"
  echo
}

show_all_sections() {
  clear
  echo -e "${BOLD}${CYAN}All Registered Sections${NC}"
  echo -e "${CYAN}Tip: category labels show where each section lives in the main submenu structure.${NC}"
  echo
  local sid
  for sid in "${SECTION_IDS[@]}"; do
    print_section_with_category "$sid"
  done
  echo
}

main() {
  parse_args "$@"
  trap 'on_error_trap $? ${LINENO} "${BASH_COMMAND}"' ERR
  trap 'on_exit_trap' EXIT

  require_sudo
  detect_os
  ensure_dir "$DOWNLOAD_DIR"
  init_section_status
  load_section_status

  info "Starting $SCRIPT_NAME as user: $STARTING_USER"
  info "Home detected: $STARTING_HOME"
  info "Log file: $LOG_FILE"
  info "Trace file: $TRACE_FILE"
  info "Dry-run mode: $DRY_RUN"
  info "Non-interactive mode: $NON_INTERACTIVE"

  local choice=""
  while true; do
    show_menu
    read -r -p "Select an option [1-14]: " choice

    case "$choice" in
      1) handle_submenu core ;;
      2) handle_submenu terminal ;;
      3) handle_submenu gui ;;
      4) handle_submenu apps ;;
      5) handle_submenu health ;;
      6) handle_submenu storage ;;
      7) handle_submenu automation ;;
      8) handle_submenu infrastructure ;;
      9) run_all_sections; press_enter ;;
      10) show_all_sections; press_enter ;;
      11) search_sections; press_enter ;;
      12) manage_favorites ;;
      13) run_category_selector; press_enter ;;
      14) success "Exiting."; exit 0 ;;
      *) warn "Invalid selection."; press_enter ;;
    esac
  done
}

main "$@"
