#!/usr/bin/env bash
# 2분마다 타이머로 실행. 앱이 기동 후 60초 안에 health/boot_ok 를 쓰지 못한 채
# 재시작을 반복하면(3회) 이전 버전으로 자동 롤백한다.
set -euo pipefail
APP_ROOT="${MTX_APP_ROOT:-/opt/methanics}"
H="$APP_ROOT/health"
mkdir -p "$H"

# 서비스가 없거나 앱이 없으면 할 일 없음
systemctl --user is-active methanics-hmi.service >/dev/null 2>&1 || exit 0
[[ -e "$APP_ROOT/current/methanics_hmi" ]] || exit 0

# 정상 마커가 있으면: 앱이 60 s 마다 갱신하는 하트비트다 (2026-09-21 A1).
#   마커가 5 분 넘게 갱신되지 않았는데 서비스는 살아 있으면 = UI/이벤트 루프가 멈춘 것 → 서비스 재시작
#   (IOC-100 출력은 통신이 끊겨도 마지막 지령을 유지하고, 새 앱은 BOOT 에서 IOC 상태를 읽고 이어 받으므로 재시작은 안전).
#   방금 (재)시작한 서비스는 5 분간 기다린다.
if [[ -f "$H/boot_ok" ]]; then
  now=$(date +%s)
  age=$(( now - $(stat -c %Y "$H/boot_ok") ))
  start_us="$(systemctl --user show methanics-hmi.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null || echo 0)"
  up_s=$(( $(cut -d. -f1 /proc/uptime) - ${start_us:-0} / 1000000 ))
  if [[ $age -gt 300 && $up_s -gt 300 ]]; then
    echo "[healthcheck] 하트비트 ${age}s 정지 (서비스 가동 ${up_s}s) → 앱 재시작" | systemd-cat -t methanics-healthcheck -p warning
    date -Is >> "$H/hang_restarts.log"
    systemctl --user restart methanics-hmi.service || true
    exit 0
  fi
  echo 0 > "$H/fail_count"
  exit 0
fi

# 마커가 없다 = 기동 중이거나 기동 실패 반복
started="$(systemctl --user show methanics-hmi.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null || echo 0)"
restarts="$(systemctl --user show methanics-hmi.service -p NRestarts --value 2>/dev/null || echo 0)"
if [[ "${restarts:-0}" -ge 3 ]]; then
  echo "[healthcheck] 기동 실패 반복(NRestarts=$restarts) → 롤백" | systemd-cat -t methanics-healthcheck -p warning
  "$APP_ROOT/bin/methanics-rollback" || true
  systemctl --user reset-failed methanics-hmi.service || true
fi
exit 0
