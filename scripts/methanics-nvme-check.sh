#!/usr/bin/env bash
# M.2 NVMe 부팅 점검 — 장착 · 인식 · 부팅 장치 · EEPROM 부팅 순서 · PCIe 속도 · SSD 상태.
#   methanics-nvme-check           # 자세히
#   methanics-nvme-check --short   # 한 줄 요약 (methanics-status 가 부름)
# 바꾸는 것은 없다. 부팅 순서를 바꾸려면 안내서 「초기 설정」 4단계(raspi-config 또는 rpi-eeprom-config).
set -uo pipefail
SHORT=0; [[ "${1:-}" == "--short" ]] && SHORT=1

root_src="$(findmnt -n -o SOURCE / 2>/dev/null)"
case "$root_src" in
  /dev/nvme*) root_kind="NVMe" ;;
  /dev/mmcblk*) root_kind="SD 카드" ;;
  /dev/sd*) root_kind="USB 저장 장치" ;;
  *) root_kind="알 수 없음" ;;
esac
nvme="$(lsblk -dn -o NAME,SIZE,MODEL 2>/dev/null | awk '$1 ~ /^nvme/ {print}')"
order="$(rpi-eeprom-config 2>/dev/null | grep -E '^BOOT_ORDER=' | cut -d= -f2)"
[[ -z "$order" ]] && order="$(sudo -n rpi-eeprom-config 2>/dev/null | grep -E '^BOOT_ORDER=' | cut -d= -f2)"
speed=""
if [[ -n "$nvme" ]]; then
  dev="$(readlink -f /sys/class/nvme/nvme0/device 2>/dev/null)"
  [[ -n "$dev" && -r "$dev/current_link_speed" ]] && speed="$(cat "$dev/current_link_speed") x$(cat "$dev/current_link_width" 2>/dev/null)"
fi

# BOOT_ORDER 는 오른쪽 자리부터 시도한다: 6 = NVMe, 1 = SD, 4 = USB, f = 처음부터 다시
first="${order: -1}"
first_txt="$(case "$first" in 6) echo NVMe ;; 1) echo SD ;; 4) echo USB ;; 2) echo 네트워크 ;; *) echo "?" ;; esac)"

if [[ $SHORT -eq 1 ]]; then
  printf '  부팅: %s (%s) · NVMe: %s · BOOT_ORDER=%s(먼저 %s)%s\n' "$root_kind" "$root_src" "${nvme:-없음}" "${order:-?}" "$first_txt" "${speed:+ · PCIe $speed}"
  [[ "$root_kind" == "NVMe" ]] || echo "  ⚠ NVMe 로 부팅하지 않았습니다 — 안내서 「초기 설정」 확인"
  exit 0
fi

echo "=== M.2 NVMe 점검 ==="
echo "기기        : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
echo "루트(/)     : $root_src → $root_kind"
echo "NVMe 장치   : ${nvme:-없음 — HAT 리본 케이블 방향 · SSD 고정 나사 · 전원(27 W 어댑터) 확인}"
echo "PCIe 속도   : ${speed:-(NVMe 없음)}   (Gen2 = 5.0 GT/s 기본, Gen3 = 8.0 GT/s 는 config.txt dtparam=pciex1_gen=3)"
echo "BOOT_ORDER  : ${order:-읽지 못함 (sudo 필요)} → 먼저 시도: $first_txt   (권장 0xf416 = NVMe → SD → USB)"
echo "부트로더    : $(vcgencmd bootloader_version 2>/dev/null | head -n1)"
echo "디스크 사용 : $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
if command -v smartctl >/dev/null && [[ -n "$nvme" ]]; then
  sudo -n smartctl -H /dev/nvme0 2>/dev/null | grep -i "result" || echo "SMART      : sudo smartctl -a /dev/nvme0 로 확인"
fi
echo
if [[ "$root_kind" == "NVMe" && "$first" == "6" ]]; then
  echo "결과: 정상 — NVMe 로 부팅 중이고 부팅 순서도 NVMe 우선입니다."
elif [[ "$root_kind" == "NVMe" ]]; then
  echo "결과: NVMe 로 부팅 중이나 BOOT_ORDER 첫 순서가 NVMe 가 아닙니다 (SD 카드를 꽂아 두면 SD 로 부팅될 수 있음)."
else
  echo "결과: NVMe 부팅 아님 — 안내서 「초기 설정」 3~4단계(OS 를 NVMe 에 쓰기 · 부팅 순서)를 진행하세요."
fi
