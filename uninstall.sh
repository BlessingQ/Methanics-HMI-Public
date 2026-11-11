#!/usr/bin/env bash
# Methanics HMI 제거. 설정(/etc/methanics)과 데이터(/var/lib/methanics)는 --purge 를 줄 때만 지운다.
# config.txt 의 usb_max_current_enable 과 ModemManager 제거는 되돌리지 않는다.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "sudo 로 실행하세요" >&2; exit 1; }
APP_USER="${SUDO_USER:-pi}"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1
APP_UID="$(id -u "$APP_USER")"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
U="$APP_HOME/.config/systemd/user"

sudo -u "$APP_USER" XDG_RUNTIME_DIR="/run/user/$APP_UID" systemctl --user disable --now methanics-hmi.service methanics-healthcheck.timer 2>/dev/null || true
rm -f "$U/methanics-hmi.service" "$U/methanics-healthcheck.service" "$U/methanics-healthcheck.timer" \
      "$U/default.target.wants/methanics-hmi.service" "$U/timers.target.wants/methanics-healthcheck.timer"
systemctl disable --now methanics-guard.service 2>/dev/null || true
rm -f /etc/systemd/system/methanics-guard.service /usr/local/sbin/methanics-guard
for s in status fetch-release apply-update rollback list-serial nvme-check; do rm -f "/usr/local/bin/methanics-$s"; done
rm -rf /opt/methanics
rm -f /etc/udev/rules.d/99-methanics-serial.rules /etc/polkit-1/rules.d/50-methanics-time.rules /etc/sudoers.d/methanics-ssd
udevadm control --reload-rules || true

if [[ $PURGE -eq 1 ]]; then
  rm -rf /etc/methanics /var/lib/methanics
  echo "설정 · 데이터까지 삭제했습니다."
else
  echo "설정(/etc/methanics) · 데이터(/var/lib/methanics)는 남겨 두었습니다 (--purge 로 삭제)."
fi
echo "제거 완료. 자동 로그인 설정은 필요하면 raspi-config 에서 되돌리세요."
