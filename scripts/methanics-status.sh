#!/usr/bin/env bash
# 설치·실행 상태 요약
set -uo pipefail
APP_ROOT="${MTX_APP_ROOT:-/opt/methanics}"
echo "=== Methanics HMI 상태 ==="
echo "기기        : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || uname -m)"
echo "현재 버전   : $(readlink -f "$APP_ROOT/current" 2>/dev/null | xargs -r basename || echo '(없음)')"
echo "이전 버전   : $(cat "$APP_ROOT/previous" 2>/dev/null || echo '(없음)')"
echo "설치된 버전 : $(ls "$APP_ROOT/releases" 2>/dev/null | tr '\n' ' ')"
echo "릴리스 저장소: $(grep MTX_REPO "$APP_ROOT/repo.env" 2>/dev/null | cut -d= -f2)"
echo "설정 파일   : $( [[ -f /etc/methanics/config.yaml ]] && echo /etc/methanics/config.yaml || echo '(없음)')"
if [[ -f "$APP_ROOT/health/boot_ok" ]]; then
  echo "헬스 마커   : $(cat "$APP_ROOT/health/boot_ok") ($(stat -c %y "$APP_ROOT/health/boot_ok" | cut -d. -f1))"
else
  echo "헬스 마커   : 없음"
fi
echo
echo "--- 서비스 ---"
UNIT="$HOME/.config/systemd/user/methanics-hmi.service"
if [[ -L "$UNIT" ]]; then unit_desc="mask 됨 ($(readlink "$UNIT"))"
elif [[ ! -e "$UNIT" ]]; then unit_desc="없음"
elif [[ ! -s "$UNIT" ]]; then unit_desc="0바이트 (비어 있음 → systemd 가 masked 로 취급)"
else unit_desc="정상 ($(stat -c %s "$UNIT") bytes)"; fi
echo "유닛 파일   : $UNIT — $unit_desc"
if systemctl --user show methanics-hmi.service -p LoadState --value >/dev/null 2>&1; then
  echo "자동 시작   : $(systemctl --user is-enabled methanics-hmi.service 2>&1 | head -n 1) / 현재: $(systemctl --user is-active methanics-hmi.service 2>&1 | head -n 1)"
  systemctl --user status methanics-hmi.service --no-pager 2>/dev/null | head -n 5
else
  echo "(사용자 systemd 에 연결 불가 — 앱 사용자로 로그인한 터미널에서 실행하세요)"
fi
case "$unit_desc" in 정상*) ;; *) echo "→ 복구: sudo methanics-guard   (또는 cd ~/Methanics-HMI-Public && git pull && sudo ./install.sh)";; esac
echo "보호 서비스 : $(systemctl is-enabled methanics-guard.service 2>&1 | head -n 1)"
[[ -f "$APP_ROOT/health/hang_restarts.log" ]] && echo "멈춤 재시작  : $(wc -l < "$APP_ROOT/health/hang_restarts.log")회 — 앱 안 감시 (마지막 $(tail -n 1 "$APP_ROOT/health/hang_restarts.log"))"
echo
echo "--- 회선 포트 (config.yaml → 지금 실제 장치) ---"
CONF=/etc/methanics/config.yaml
if [[ -f "$CONF" ]]; then
  for key in modbus iontec ch4; do
    port="$(sed -n '/^ports:/,/^[^ #]/p' "$CONF" | grep -E "^[[:space:]]+$key:" | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^"//; s/"$//')"
    # 화면 「통신 포트」에서 기억한 장치(ports.json)가 설정 파일보다 먼저
    mem="$(jq -r --arg k "$key" '.[$k].path // empty' /var/lib/methanics/ports.json 2>/dev/null)"
    [[ -n "$mem" ]] && port="$mem (기억)"
    [[ -n "$port" ]] || port="/dev/mtx-$key (기본값)"
    p="${port% (기본값)}"; p="${p% (기억)}"
    if [[ ! -e "$p" ]]; then note="없음 ✗"
    elif [[ "$p" =~ ^/dev/tty(USB|ACM)[0-9]+$ ]]; then note="번호 경로 ⚠ 재부팅 때 바뀔 수 있음 → udev 이름(/dev/mtx-*) 이나 /dev/serial/by-id 경로로"
    else note="→ $(readlink -f "$p")"; fi
    printf '  %-7s %s  %s
' "$key" "$port" "$note"
  done
  grep -qE '^simulate:[[:space:]]*true' "$CONF" && echo "  ⚠ simulate: true — 시뮬레이션 모드 (현장 장비에서는 끄세요)"
  # 관제 서버 설정
  iot="$(sed -n '/^iot:/,/^[^ #]/p' "$CONF" | grep -E '^[[:space:]]+enabled:' | head -n1 | awk '{print $2}')"
  upl="$(sed -n '/^iot:/,/^[^ #]/p' "$CONF" | grep -E '^[[:space:]]+upload:' | head -n1 | awk '{print $2}')"
  echo "  관제 서버(iot.enabled) : ${iot:-true(기본)}   ·   측정 기록 업로드(iot.upload) : ${upl:-true(기본)}"
fi
ls -l /dev/mtx-* 2>/dev/null
echo "  고유 경로: $(ls /dev/serial/by-id 2>/dev/null | tr '
' ' ')"
echo
echo "--- 시각 (RTC · NTP) ---"
echo "  지금        : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "  NTP 동기화  : $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo '?')  (NTP 서비스 $(timedatectl show -p NTP --value 2>/dev/null || echo '?'))"
if [[ -r /sys/class/rtc/rtc0/time ]]; then
  echo "  RTC (UTC)   : $(cat /sys/class/rtc/rtc0/date) $(cat /sys/class/rtc/rtc0/time)"
else
  echo "  RTC         : 없음"
fi
cv="$(cat /sys/class/rtc/rtc0/charging_voltage 2>/dev/null)"
case "$cv" in
  "") echo "  RTC 충전    : 확인 불가" ;;
  0) echo "  RTC 충전    : 꺼짐 ⚠ 공식 충전식 배터리면 config.txt 에 dtparam=rtc_bbat_vchg=3000000 (install.sh 가 넣음) 후 재부팅" ;;
  *) echo "  RTC 충전    : 켜짐 (${cv} µV)" ;;
esac
echo
echo "--- 저장 장치 ---"
"$APP_ROOT/bin/methanics-nvme-check" --short 2>/dev/null || echo "  (methanics-nvme-check 없음)"
echo
echo "--- 디스플레이 ---"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
