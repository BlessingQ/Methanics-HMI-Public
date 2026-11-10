#!/usr/bin/env bash
# Methanics HMI 설치 스크립트 — Raspberry Pi 5 / Raspberry Pi OS (64-bit, Desktop, Bookworm 이상), M.2 NVMe 부팅 권장
#
# 하는 일:
#   1. 필수 패키지 설치, 앱 사용자를 dialout · gpio 그룹에 추가, ModemManager 제거 (USB 시리얼 변환기에 AT 명령을 보내지 않게)
#   2. /opt/methanics 구성 (releases/, current -> 심볼릭 링크, bin/, downloads/, health/), 데이터 /var/lib/methanics
#   3. GitHub Releases 에서 최신 앱 패키지 다운로드 + sha256 검증 + 설치 (--local <tar.gz> 로 대체 가능)
#   4. /etc/methanics/config.yaml 설정 파일 배치 (이미 있으면 유지)
#   5. 시리얼 udev 규칙 템플릿 (/dev/mtx-* 고정 이름)
#   6. /boot/firmware/config.txt: usb_max_current_enable=1 (USB 허브 · 카메라 · 터치 전원) · RTC 배터리 충전 (재부팅 후 적용) · NTP 켬
#      + 시각 권한 규칙(polkit) — 앱 설정 「시간 · RTC」 에서 시각을 맞출 수 있게
#   7. 키오스크: 데스크톱 자동 로그인, 화면 꺼짐 방지
#   8. systemd 사용자 서비스 -> 부팅 시 앱 자동 시작, 죽으면 5초 뒤 재시작
#   9. 멈춤 감지 · 재시작은 앱 안 감시(watchdog)가 한다 — 별도 타이머 없음 (예전 methanics-healthcheck 가 있으면 지운다)
#  10. 자동 시작 보호 (root methanics-guard.service) -> 전원 급차단으로 유닛 파일이 비어도 부팅 때 복구
#
# 사용법:
#   sudo ./install.sh                     # 최신 릴리스 설치
#   sudo ./install.sh --local app.tar.gz  # 직접 빌드한 패키지 설치
#   sudo ./install.sh --user pi           # 앱을 실행할 데스크톱 사용자 (기본: sudo 를 호출한 사용자)
#   sudo ./install.sh --no-kiosk          # 자동 로그인 · 화면 설정을 건드리지 않음
#   sudo ./install.sh --keep-modemmanager # ModemManager 를 지우지 않음
#   sudo ./install.sh --no-rtc-charge     # RTC 배터리 충전을 켜지 않음 (충전식이 아닌 코인 전지를 단 경우 — 꼭 이 옵션)
set -euo pipefail

REPO="${MTX_REPO:-BlessingQ/Methanics-HMI-Public}"
APP_ROOT=/opt/methanics
CONF_DIR=/etc/methanics
DATA_DIR=/var/lib/methanics
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCAL_PKG=""
APP_USER="${SUDO_USER:-}"
KIOSK=1
KEEP_MM=0
RTC_CHARGE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL_PKG="$2"; shift 2 ;;
    --user) APP_USER="$2"; shift 2 ;;
    --no-kiosk) KIOSK=0; shift ;;
    --keep-modemmanager) KEEP_MM=1; shift ;;
    --no-rtc-charge) RTC_CHARGE=0; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m[Methanics]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[Methanics] 경고:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[Methanics] 오류:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "sudo 로 실행하세요:  sudo ./install.sh"
[[ -n "$APP_USER" && "$APP_USER" != "root" ]] || die "앱을 실행할 데스크톱 사용자를 --user 로 지정하세요 (예: --user pi)"
id "$APP_USER" >/dev/null 2>&1 || die "사용자 '$APP_USER' 가 없습니다"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
APP_UID="$(id -u "$APP_USER")"

ARCH="$(uname -m)"
[[ "$ARCH" == "aarch64" ]] || warn "aarch64 가 아닙니다 ($ARCH). Raspberry Pi OS 64-bit 가 필요합니다."
if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
  log "기기: $(tr -d '\0' < /proc/device-tree/model)"
else
  warn "Raspberry Pi 5 가 아닌 것으로 보입니다: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
fi
case "$(findmnt -n -o SOURCE / 2>/dev/null)" in
  /dev/nvme*) log "부팅 장치: NVMe ✓" ;;
  *) warn "NVMe 로 부팅하지 않았습니다 ($(findmnt -n -o SOURCE /)). 현장 장비는 NVMe 부팅을 권장합니다 — docs/1_초기설정_M2_NVMe.md" ;;
esac

# ── 1. 패키지 ────────────────────────────────────────────────────────────────
log "패키지 설치"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# fonts-noto-cjk: 터미널 · 바탕화면의 한글 (앱 화면은 글꼴을 앱에 넣어 둠) — ARC-100 과 같음
apt-get install -y -qq curl jq git ca-certificates libgtk-3-0 liblzma5 libstdc++6 libblkid1 smartmontools fonts-noto-cjk locales >/dev/null
# 앱 실행 래퍼가 LANG=ko_KR.UTF-8 을 쓰므로 로캘을 만들어 둔다 (시스템 기본 언어는 바꾸지 않음)
if ! locale -a 2>/dev/null | grep -qi '^ko_KR\.utf-\?8$'; then
  sed -i 's/^# *\(ko_KR\.UTF-8 UTF-8\)/\1/' /etc/locale.gen && locale-gen >/dev/null 2>&1 || warn "ko_KR.UTF-8 로캘 생성 실패"
fi
usermod -aG dialout "$APP_USER"
getent group gpio >/dev/null && usermod -aG gpio "$APP_USER"   # 머리 진입 포토센서 (GPIO 입력)
if [[ $KEEP_MM -eq 0 ]] && dpkg -s modemmanager >/dev/null 2>&1; then
  # ModemManager 는 새 USB 시리얼마다 AT 명령을 보낸다 — RS-485 버스에 엉뚱한 바이트가 나가 센서 응답이 깨질 수 있다.
  # LTE 는 외부 라우터(RUT241)가 맡으므로 Pi 에는 필요 없다.
  log "ModemManager 제거 (USB 시리얼 변환기 보호)"
  systemctl disable --now ModemManager.service >/dev/null 2>&1 || true
  apt-get purge -y -qq modemmanager >/dev/null || warn "ModemManager 제거 실패"
fi

# ── 2. 디렉터리 ──────────────────────────────────────────────────────────────
log "디렉터리 구성: $APP_ROOT · $DATA_DIR"
install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT" "$APP_ROOT/releases" "$APP_ROOT/health" "$APP_ROOT/bin" "$APP_ROOT/downloads"
install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$DATA_DIR"
install -d "$CONF_DIR"

for s in fetch-release apply-update rollback run list-serial status nvme-check; do
  install -m 0755 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/scripts/methanics-$s.sh" "$APP_ROOT/bin/methanics-$s"
done
install -m 0755 -o root -g root "$SRC_DIR/scripts/methanics-guard.sh" "$APP_ROOT/bin/methanics-guard"
ln -sfn "$APP_ROOT/bin/methanics-guard" /usr/local/sbin/methanics-guard
for s in status fetch-release apply-update rollback list-serial nvme-check; do
  ln -sfn "$APP_ROOT/bin/methanics-$s" "/usr/local/bin/methanics-$s"
done
printf 'MTX_REPO=%s\n' "$REPO" > "$APP_ROOT/repo.env"
printf 'APP_USER=%s\nAPP_UID=%s\nAPP_HOME=%s\n' "$APP_USER" "$APP_UID" "$APP_HOME" > "$APP_ROOT/app.env"

# ── 3. 앱 패키지 ─────────────────────────────────────────────────────────────
if [[ -n "$LOCAL_PKG" ]]; then
  log "로컬 패키지 설치: $LOCAL_PKG"
  sudo -u "$APP_USER" MTX_REPO="$REPO" "$APP_ROOT/bin/methanics-fetch-release" --local "$LOCAL_PKG" --activate
else
  log "GitHub Releases 에서 최신 패키지 확인: $REPO"
  if ! sudo -u "$APP_USER" MTX_REPO="$REPO" "$APP_ROOT/bin/methanics-fetch-release" --activate; then
    warn "릴리스를 가져오지 못했습니다. 나중에 'methanics-fetch-release --activate' 를 다시 실행하거나 --local 로 설치하세요."
  fi
fi

# ── 4. 설정 파일 ─────────────────────────────────────────────────────────────
if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
  log "설정 파일 생성: $CONF_DIR/config.yaml (config.example.yaml 복사) — device_id · admin_pin · 서버 설정을 고치세요"
  install -m 0640 "$SRC_DIR/config/config.example.yaml" "$CONF_DIR/config.yaml"
else
  log "설정 파일 유지: $CONF_DIR/config.yaml"
fi
chown "$APP_USER":"$APP_USER" "$CONF_DIR/config.yaml"
chmod 0640 "$CONF_DIR/config.yaml"   # 관리자 PIN 이 들어간다 — 앱 사용자만 읽기

# ── 5. udev ──────────────────────────────────────────────────────────────────
if [[ ! -f /etc/udev/rules.d/99-methanics-serial.rules ]]; then
  log "udev 규칙 설치 (템플릿) — 실제 컨버터 값은 'methanics-list-serial' 로 확인 후 수정"
  install -m 0644 "$SRC_DIR/config/99-methanics-serial.rules" /etc/udev/rules.d/99-methanics-serial.rules
else
  log "udev 규칙 유지: /etc/udev/rules.d/99-methanics-serial.rules"
fi
udevadm control --reload-rules && udevadm trigger || true

# ── 6. config.txt (USB 전원) ─────────────────────────────────────────────────
BOOTCFG=/boot/firmware/config.txt
[[ -f "$BOOTCFG" ]] || BOOTCFG=/boot/config.txt
if [[ -f "$BOOTCFG" ]] && ! grep -qE '^usb_max_current_enable=1' "$BOOTCFG"; then
  log "config.txt: usb_max_current_enable=1 추가 (USB 포트 합계 1.6 A — 허브 · 카메라 · 터치, 재부팅 후 적용)"
  cp -a "$BOOTCFG" "$BOOTCFG.bak-methanics"
  printf '\n[all]\n# Methanics: USB 허브 · 카메라 · 터치 전원 — 27 W 공식 어댑터가 아니어도 USB 전류 제한을 푼다\nusb_max_current_enable=1\n' >> "$BOOTCFG"
fi
# RTC: Pi 5 보드 내장 RTC + 공식 충전식 배터리(ML-2020). 기본은 충전하지 않으므로 켠다 — 안 켜면 몇 달 뒤 방전돼 정전 때 시계가 초기화된다.
# 충전식이 아닌 코인 전지(CR2032 등)를 달았으면 --no-rtc-charge (충전하면 위험).
if [[ $RTC_CHARGE -eq 1 && -f "$BOOTCFG" ]] && grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null && ! grep -qE '^dtparam=rtc_bbat_vchg=' "$BOOTCFG"; then
  log "config.txt: RTC 배터리 충전 켬 (dtparam=rtc_bbat_vchg=3000000, 공식 충전식 배터리 전제 · 재부팅 후 적용)"
  [[ -f "$BOOTCFG.bak-methanics" ]] || cp -a "$BOOTCFG" "$BOOTCFG.bak-methanics"
  printf '\n[all]\n# Methanics: Pi 5 RTC 공식 충전식 배터리 충전 (충전식이 아니면 이 줄을 지울 것)\ndtparam=rtc_bbat_vchg=3000000\n' >> "$BOOTCFG"
fi
# 시각: 인터넷이 있으면 NTP(systemd-timesyncd)로 맞추고 RTC 에도 기록된다. 없으면 부팅 때 RTC 에서 읽는다.
timedatectl set-ntp true >/dev/null 2>&1 || warn "NTP 켜기 실패 (timedatectl)"
# 앱 설정 → 「시간 · RTC」 에서 앱이 직접 timedatectl 로 시각을 맞출 수 있게 — 스크립트 없이 polkit 규칙 파일 하나 (이 사용자 · 이 두 동작만)
install -d -m 0755 /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-methanics-time.rules <<RULES
// Methanics HMI: 앱 사용자($APP_USER)가 비밀번호 없이 시각 · NTP 를 바꿀 수 있게 (앱 설정 → 시간 · RTC). install.sh 가 만듦.
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.timedate1.set-time" || action.id == "org.freedesktop.timedate1.set-ntp") &&
      subject.user == "$APP_USER") {
    return polkit.Result.YES;
  }
});
RULES
chmod 0644 /etc/polkit-1/rules.d/50-methanics-time.rules

# ── 7. 키오스크 ──────────────────────────────────────────────────────────────
if [[ $KIOSK -eq 1 ]] && command -v raspi-config >/dev/null; then
  log "키오스크: 데스크톱 자동 로그인($APP_USER), 화면 꺼짐 방지"
  raspi-config nonint do_boot_behaviour B4 || warn "자동 로그인 설정 실패 (raspi-config)"
  raspi-config nonint do_blanking 1 || warn "화면 꺼짐 방지 설정 실패 (raspi-config)"
fi

# ── 8. systemd 사용자 서비스 (부팅 시 자동 시작 · 꺼지면 다시 켬) ─────────────
log "systemd 사용자 서비스 등록: methanics-hmi.service (멈춤 감지는 앱 안 감시가 함)"
USER_UNIT_DIR="$APP_HOME/.config/systemd/user"
install -d -o "$APP_USER" -g "$APP_USER" "$APP_HOME/.config" "$APP_HOME/.config/systemd" "$USER_UNIT_DIR"
install -d -o root -g root "$APP_ROOT/units"   # 원본 보관 — methanics-guard 가 부팅마다 비교해 복구
# 예전 설치(2026-11-10 전)의 헬스체크 타이머를 지운다 — 앱 v0.1.2~ 는 앱 안 감시를 쓴다
if [[ -d "/run/user/$APP_UID" ]]; then
  sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" systemctl --user disable --now methanics-healthcheck.timer >/dev/null 2>&1 || true
fi
rm -f "$USER_UNIT_DIR/methanics-healthcheck.service" "$USER_UNIT_DIR/methanics-healthcheck.timer" "$USER_UNIT_DIR/timers.target.wants/methanics-healthcheck.timer" \
      "$APP_ROOT/units/methanics-healthcheck.service" "$APP_ROOT/units/methanics-healthcheck.timer" "$APP_ROOT/bin/methanics-healthcheck"
for u in methanics-hmi.service; do
  [[ -s "$SRC_DIR/config/$u" ]] || die "유닛 파일이 비어 있습니다: $SRC_DIR/config/$u (git pull 로 다시 받으세요)"
  install -m 0644 -o root -g root "$SRC_DIR/config/$u" "$APP_ROOT/units/$u"
  rm -f "$USER_UNIT_DIR/$u"
  install -m 0644 -o "$APP_USER" -g "$APP_USER" "$SRC_DIR/config/$u" "$USER_UNIT_DIR/$u"
done
loginctl enable-linger "$APP_USER" || true

run_user_systemctl() {
  sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" systemctl --user "$@"
}
if [[ -d "/run/user/$APP_UID" ]]; then
  run_user_systemctl daemon-reload
  run_user_systemctl unmask methanics-hmi.service 2>/dev/null || true
  run_user_systemctl enable methanics-hmi.service
  if [[ -e "$APP_ROOT/current/methanics_hmi" ]]; then
    run_user_systemctl restart methanics-hmi.service || warn "서비스 시작 실패 — 'methanics-status' 로 확인"
  fi
else
  warn "사용자 세션이 아직 없어 서비스 활성화를 건너뜁니다. 재부팅 후 자동 로그인되면 활성화됩니다."
  install -d -o "$APP_USER" -g "$APP_USER" "$USER_UNIT_DIR/default.target.wants"
  ln -sfn "$USER_UNIT_DIR/methanics-hmi.service" "$USER_UNIT_DIR/default.target.wants/methanics-hmi.service"
  chown -h "$APP_USER":"$APP_USER" "$USER_UNIT_DIR/default.target.wants/methanics-hmi.service"
fi

# ── 10. 자동 시작 보호 (root) ───────────────────────────────────────────────
log "자동 시작 보호 등록: methanics-guard.service (부팅마다 유닛 파일 점검 · 복구)"
install -m 0644 -o root -g root "$SRC_DIR/config/methanics-guard.service" /etc/systemd/system/methanics-guard.service
systemctl daemon-reload
systemctl enable methanics-guard.service >/dev/null 2>&1 || warn "methanics-guard 활성화 실패"
"$APP_ROOT/bin/methanics-guard" || true

sync   # 전원 급차단 대비

if [[ -d "/run/user/$APP_UID" ]]; then
  st="$(run_user_systemctl is-enabled methanics-hmi.service 2>&1 || true)"
  [[ "$st" == "enabled" ]] || warn "methanics-hmi.service 상태가 '$st' 입니다 — 'methanics-status' 로 확인하세요"
fi

echo
log "설치 완료."
echo "  앱 경로      : $APP_ROOT/current  ->  $(readlink -f "$APP_ROOT/current" 2>/dev/null || echo '(릴리스 없음)')"
echo "  설정         : $CONF_DIR/config.yaml   (device_id · admin_pin · iot 를 현장에 맞게)"
echo "  데이터       : $DATA_DIR   (업데이트 기록 · 업로드 대기열 — 업데이트 · 롤백해도 유지)"
echo "  로그         : journalctl --user -u methanics-hmi -f   (사용자 $APP_USER 로)"
echo "  상태         : methanics-status   ·   NVMe 점검: methanics-nvme-check"
echo "  통신 포트    : 앱 설정 → 통신 포트 [지정] (USB 칩 시리얼로 기억)  ·  확인: methanics-list-serial"
echo "  업데이트     : methanics-fetch-release --activate   /  롤백: methanics-rollback"
echo "  자동시작 복구: sudo methanics-guard   (부팅마다 자동 실행됨)"
echo
echo "  재부팅하면 자동 로그인 후 앱이 전체화면으로 시작됩니다:  sudo reboot"
