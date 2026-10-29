#!/usr/bin/env bash

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 25
}

read_value() {
  local prompt="$1" default_value="${2:-}"
  local answer=""
  printf '%s [%s]: ' "$prompt" "$default_value" >/dev/tty
  if IFS= read -r answer </dev/tty; then
    printf '%s' "${answer:-$default_value}"
  else
    printf '%s' "$default_value"
  fi
}

ask_yes() {
  local prompt="$1" default_value="${2:-y}"
  local answer=""
  while true; do
    printf '%s [%s]: ' "$prompt" "$default_value" >/dev/tty
    if IFS= read -r answer </dev/tty; then
      answer="${answer:-$default_value}"
      case "${answer,,}" in
        y|yes|j|ja) return 0 ;;
        n|no|nein) return 1 ;;
        *) warn "Bitte nur y oder n eingeben." ;;
      esac
    else
      return 1
    fi
  done
}

ensure_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Bitte mit sudo oder als root ausführen: sudo bash ./bash.sh"
  fi
}

choose_mode() {
  case "${SETUP_MODE,,}" in
    m|manual)
      AUTO_MODE=0
      ;;
    a|auto)
      AUTO_MODE=1
      ;;
    w|wizard|interactive)
      while true; do
        printf 'Setup-Modus wählen [m=manual, a=auto, w=wizard]: ' >/dev/tty
        IFS= read -r SETUP_MODE </dev/tty || SETUP_MODE="w"
        case "${SETUP_MODE,,}" in
          m|manual)
            AUTO_MODE=0
            break
            ;;
          a|auto)
            AUTO_MODE=1
            break
            ;;
          w|wizard|interactive)
            AUTO_MODE=0
            break
            ;;
          *) warn "Ungültiger Modus. Verwende m, a oder w." ;;
        esac
      done
      ;;
    *)
      warn "Unbekannter Modus: $SETUP_MODE. Nutze Standard 'w'."
      SETUP_MODE="w"
      AUTO_MODE=0
      ;;
  esac
}

load_env_if_available() {
  local env_file="$INSTALL_DIR/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi
}
