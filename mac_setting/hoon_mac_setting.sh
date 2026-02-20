#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="$HOME/mac-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ===============================
# 🔥 여기 한 곳만 수정하면 됨
# ===============================
APPS=(
  "google-chrome"
  "iterm2"
  "rectangle"
)

# ===============================
# 옵션
# ===============================
AUTO_ALL=false
AUTO_REINSTALL=false

for arg in "${@:-}"; do
  case "$arg" in
    --all) AUTO_ALL=true ;;
    --reinstall) AUTO_REINSTALL=true ;;
    -h|--help)
      echo "./setup-mac.sh"
      echo "./setup-mac.sh --all"
      echo "./setup-mac.sh --all --reinstall"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ===============================
# 유틸
# ===============================
has_cmd() { command -v "$1" >/dev/null 2>&1; }

brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

confirm() {
  local prompt="$1"

  if $AUTO_ALL; then
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

# ===============================
# 리포트 저장
# ===============================
declare -A ACTION

mark() {
  ACTION["$1"]="$2"
}

# ===============================
# Homebrew
# ===============================
install_homebrew() {
  if has_cmd brew; then
    mark "homebrew" "already installed"
    return
  fi

  echo "⏳ Homebrew 설치 중..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew_shellenv
  mark "homebrew" "installed"
}

# ===============================
# Cask 설치 로직
# ===============================
install_cask() {
  local app="$1"

  if brew list --cask "$app" >/dev/null 2>&1; then
    echo "⚠️  $app 이미 설치되어 있습니다."

    if $AUTO_REINSTALL; then
      brew reinstall --cask "$app"
      mark "$app" "reinstalled"
      return
    fi

    if confirm "스킵하시겠습니까?"; then
      mark "$app" "skipped"
    else
      brew reinstall --cask "$app"
      mark "$app" "reinstalled"
    fi
    return
  fi

  echo "⏳ $app 설치 중..."
  brew install --cask "$app"
  mark "$app" "installed"
}

# ===============================
# 리포트 출력
# ===============================
print_report() {
  echo
  echo "=============================="
  echo " 설치 결과 요약"
  echo "=============================="

  for key in "homebrew" "${APPS[@]}"; do
    printf "%-18s : %s\n" "$key" "${ACTION[$key]:-not executed}"
  done

  echo "=============================="
  echo "로그: $LOG_FILE"
  echo
}

# ===============================
# 실행
# ===============================
brew_shellenv || true
install_homebrew
brew_shellenv

if $AUTO_ALL; then
  for app in "${APPS[@]}"; do
    install_cask "$app"
  done
  print_report
  exit 0
fi

# 대화형 메뉴
while true; do
  echo
  echo "=============================="
  echo " Mac Setup"
  echo "=============================="

  i=1
  for app in "${APPS[@]}"; do
    echo "$i) $app 설치"
    ((i++))
  done

  echo "9) 설치 결과 요약 보기"
  echo "0) 종료"
  echo

  read -r -p "선택하세요: " choice

  if [[ "$choice" == "0" ]]; then
    print_report
    exit 0
  fi

  if [[ "$choice" == "9" ]]; then
    print_report
    continue
  fi

  index=$((choice - 1))

  if [[ $index -ge 0 && $index -lt ${#APPS[@]} ]]; then
    install_cask "${APPS[$index]}"
  else
    echo "잘못된 입력입니다."
  fi
done