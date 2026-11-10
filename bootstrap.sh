#!/usr/bin/env bash
# Methanics HMI 원클릭 설치 부트스트랩 (Raspberry Pi 5 / Raspberry Pi OS 64-bit Desktop)
#
#   curl -fsSL https://raw.githubusercontent.com/BlessingQ/Methanics-HMI-Public/main/bootstrap.sh | bash
#
# git 을 설치하고 저장소를 ~/Methanics-HMI-Public 에 클론(또는 갱신)한 뒤 install.sh 를 sudo 로 실행한다.
set -euo pipefail
REPO_URL="${MTX_REPO_URL:-https://github.com/BlessingQ/Methanics-HMI-Public.git}"
DEST="${MTX_INSTALLER_DIR:-$HOME/Methanics-HMI-Public}"

# 새로 설치한 OS 에는 한글 글꼴이 없어 터미널의 한글 안내가 □ 로 깨진다 → 글꼴부터 깐다 (그 전까지는 영문 안내만)
if ! fc-list 2>/dev/null | grep -qiE 'Noto Sans CJK|Noto Serif CJK|NanumGothic'; then
  echo "[bootstrap] Installing Korean fonts (fonts-noto-cjk) and git first, so the Korean messages below are readable..."
  sudo apt-get update -qq && sudo apt-get install -y -qq fonts-noto-cjk git
  fc-cache -f >/dev/null 2>&1 || true
  echo "[bootstrap] Korean fonts installed. If Korean text below still shows as boxes, close and reopen the terminal and run the same command again (safe to repeat)."
fi
if ! command -v git >/dev/null; then
  echo "[bootstrap] git 설치"
  sudo apt-get update -qq && sudo apt-get install -y -qq git
fi
if [[ -d "$DEST/.git" ]]; then
  echo "[bootstrap] 설치 스크립트 갱신: $DEST"
  git -C "$DEST" pull --ff-only
else
  echo "[bootstrap] 설치 스크립트 클론: $REPO_URL -> $DEST"
  git clone --depth 1 "$REPO_URL" "$DEST"
fi
chmod +x "$DEST"/install.sh "$DEST"/uninstall.sh "$DEST"/scripts/*.sh
echo "[bootstrap] install.sh 실행 (sudo 비밀번호를 물을 수 있습니다)"
sudo "$DEST/install.sh" --user "$USER" "$@"
