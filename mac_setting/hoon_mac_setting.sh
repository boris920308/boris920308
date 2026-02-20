#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="$HOME/mac-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ------------------------------------
# 옵션 파싱
# ------------------------------------
AUTO_ALL=false
AUTO_REINSTALL=false

usage() {
  cat <<'EOF'
Usage:
  ./setup-mac.sh            # 대화형 메뉴
  ./setup-mac.sh --all      # Chrome + iTerm2 자동 실행(기본: 이미 있으면 스킵)
  ./setup-mac.sh --all --reinstall  # 자동 실행 + 이미 있어도 재설치
  ./setup-mac.sh -h|--help  # 도움말
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    --all) AUTO_ALL=true ;;
    --reinstall) AUTO_REINSTALL=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# ------------------------------------
# 유틸
# ------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Apple Silicon 고정 (요구사항)
brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

confirm() {
  # AUTO_ALL 모드면 confirm을 자동 처리
  local prompt="$1"
  if $AUTO_ALL; then
    # --all 기본은 "스킵" / --all --reinstall이면 "재설치"
    if $AUTO_REINSTALL; then
      echo "$prompt [AUTO: No]"
      return 1
    else
      echo "$prompt [AUTO: Yes]"
      return 0
    fi
  fi

  read -r -p "$prompt [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

# ------------------------------------
# 리포트(요약) 수집
# ------------------------------------
# keys: homebrew, google-chrome, iterm2
declare -A ACTION    # installed|reinstalled|skipped|failed|unchanged
declare -A DETAIL    # 메시지/에러 요약

mark() {
  local key="$1" act="$2" msg="${3:-}"
  ACTION["$key"]="$act"
  DETAIL["$key"]="$msg"
}

# ------------------------------------
# Homebrew (멱등 + 대화형)
# ------------------------------------
install_homebrew() {
  if has_cmd brew; then
    echo "✅ Homebrew 이미 설치되어 있습니다."
    if confirm "Homebrew 업데이트를 실행할까요?"; then
      if brew update; then
        mark "homebrew" "unchanged" "already installed (updated)"
      else
        mark "homebrew" "failed" "brew update failed"
        return 1
      fi
    else
      mark "homebrew" "unchanged" "already installed (no update)"
    fi
    return 0
  fi

  echo "⏳ Homebrew 설치 중..."
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    brew_shellenv
    mark "homebrew" "installed" "installed homebrew"
  else
    mark "homebrew" "failed" "homebrew install failed"
    return 1
  fi
}

# ------------------------------------
# Cask 설치 (핵심 로직)
# ------------------------------------
install_cask() {
  local app="$1"

  if brew list --cask "$app" >/dev/null 2>&1; then
    echo "⚠️  $app 는 이미 설치되어 있습니다."
    if $AUTO_REINSTALL; then
      echo "→ (AUTO) 재설치 진행"
      if brew reinstall --cask "$app"; then
        mark "$app" "reinstalled" "reinstalled"
        return 0
      else
        mark "$app" "failed" "reinstall failed"
        return 1
      fi
    fi

    if confirm "스킵하시겠습니까?"; then
      echo "→ $app 스킵"
      mark "$app" "skipped" "already installed"
      return 0
    else
      echo "🔁 $app 재설치 진행"
      if brew reinstall --cask "$app"; then
        mark "$app" "reinstalled" "reinstalled"
        return 0
      else
        mark "$app" "failed" "reinstall failed"
        return 1
      fi
    fi
  fi

  echo "⏳ $app 설치 중..."
  if brew install --cask "$app"; then
    mark "$app" "installed" "installed"
    return 0
  else
    mark "$app" "failed" "install failed"
    return 1
  fi
}

# ------------------------------------
# 메뉴
# ------------------------------------
menu() {
  echo
  echo "=============================="
  echo " Mac Setup (Chrome + iTerm2)"
  echo "=============================="
  echo "1) Google Chrome 설치"
  echo "2) iTerm2 설치"
  echo "3) 둘 다 설치"
  echo "9) 설치 결과 요약 보기"
  echo "0) 종료"
  echo
}

# ------------------------------------
# 리포트 출력
# ------------------------------------
print_report() {
  echo
  echo "=============================="
  echo " 설치 결과 요약"
  echo " 로그: $LOG_FILE"
  echo "=============================="

  # Homebrew
  local hb="${ACTION[homebrew]:-unknown}"
  printf "Homebrew        : %-12s %s\n" "$hb" "${DETAIL[homebrew]:-}"

  # Apps
  local chrome="${ACTION[google-chrome]:-unknown}"
  printf "Google Chrome   : %-12s %s\n" "$chrome" "${DETAIL[google-chrome]:-}"

  local iterm="${ACTION[iterm2]:-unknown}"
  printf "iTerm2          : %-12s %s\n" "$iterm" "${DETAIL[iterm2]:-}"

  echo "=============================="
  echo
}

# ------------------------------------
# 실행부
# ------------------------------------
# Apple Silicon 전용 brew path 세팅(설치 전에는 없을 수 있음)
brew_shellenv || true

# Homebrew 준비
install_homebrew
brew_shellenv

# --all 모드면 자동 실행 후 리포트 출력하고 종료
if $AUTO_ALL; then
  install_cask "google-chrome" || true
  install_cask "iterm2" || true
  print_report
  exit 0
fi

# 대화형 모드
while true; do
  menu
  read -r -p "선택하세요: " choice

  case "$choice" in
    1)
      install_cask "google-chrome" || true
      ;;
    2)
      install_cask "iterm2" || true
      ;;
    3)
      install_cask "google-chrome" || true
      install_cask "iterm2" || true
      ;;
    9)
      print_report
      ;;
    0)
      print_report
      echo "종료합니다."
      exit 0
      ;;
    *)
      echo "잘못된 입력입니다."
      ;;
  esac
done