# Methanics HMI 초기 설정 안내서 — Raspberry Pi 5 + M.2 NVMe

현장 장비 한 대를 **빈 Raspberry Pi 5에서 앱이 자동으로 뜨는 상태**까지 만드는 순서입니다.
처음 한 번만 하고, 그 뒤 앱 업데이트는 원격(OTA)으로 합니다 — [README](../README.md) 6장.

| 단계 | 할 일 | 걸리는 시간 |
|---|---|---|
| 1 | 준비물 확인 | — |
| 2 | M.2 HAT+ · SSD 장착 | 10분 |
| 3 | SD 카드로 첫 부팅 · 부트로더 최신화 | 15분 |
| 4 | 부팅 순서를 NVMe 우선으로 | 3분 |
| 5 | OS 를 NVMe 에 쓰기 | 15분 |
| 6 | NVMe 로 부팅 · 기본 설정 | 10분 |
| 7 | 앱 설치 (한 줄) | 5분 |
| 8 | 현장 설정 (config.yaml · 통신 포트 지정) | 15분 |
| 9 | 확인 체크리스트 (SD 에 먼저 설치했다면 9-1 로 옮기기) | 5분 |

---

## 1. 준비물

| 품목 | 규격 | 비고 |
|---|---|---|
| Raspberry Pi 5 | 4 GB 이상 | 액티브 쿨러 포함 세트 |
| M.2 HAT+ | Raspberry Pi 공식 (PCIe → M.2 M key, 2230 · 2242) | 리본 케이블 · 스페이서 · GPIO 연장 헤더 동봉 |
| NVMe SSD | Raspberry Pi SSD 256 GB (SC1439, 2230) | 사진 90일 보관에 약 94 GB 필요 — SD 로는 부족 |
| microSD 카드 | 64 GB | 처음 설치와 **복구용**. 설치 뒤에도 꽂아 둔다 (4단계 부팅 순서 참고) |
| RTC 배터리 | Raspberry Pi 공식 RTC 배터리 (충전식 ML-2020) | 보드 J5(BAT) 커넥터. 인터넷이 없어도 정전 뒤 시각 유지 — 충전은 설치 스크립트가 켬 |
| 전원 | 공식 27 W USB-C 어댑터 (설치 작업용) | 현장은 제어함 5 V 전원(5.2 V 조정) |
| 화면 · 입력 | 10.1" 1280×800 터치 LCD (HDMI + USB 터치) | 처음엔 USB 키보드 · 마우스가 편함 |
| 네트워크 | 유선 LAN (인터넷) | 현장은 LTE 라우터(RUT241) 경유 |
| PC | Windows · Mac 아무거나 | SD 카드에 OS 를 쓸 때만 |

> **주의** 모든 장착 작업은 전원을 뽑고 합니다. 정전기에 주의합니다.

## 2. M.2 HAT+ · SSD 장착

공식 설명서(raspberrypi.com → Documentation → Accessories → M.2 HAT+) 순서와 같습니다.

1. **액티브 쿨러를 먼저** 붙입니다 (HAT 아래에 들어갑니다).
2. 스페이서 4개를 Pi 에 나사로 고정합니다.
3. **GPIO 연장 헤더**를 Pi 의 GPIO 핀에 끝까지 눌러 끼웁니다 (방향 무관, 모든 핀이 들어가게).
4. 리본 케이블을 HAT 에서 빼고, 한쪽 끝을 **Pi 5 의 PCIe 커넥터**(보드 가장자리 「PCIe」)에 넣습니다.
   - 커넥터 잠금쇠를 양쪽으로 들어 올리고, **구리 접점이 안쪽(USB 포트 쪽)** 을 보게 끝까지 고르게 넣은 뒤 잠금쇠를 눌러 잠급니다.
5. HAT 를 스페이서 위에 올려 남은 나사 4개로 고정합니다.
6. 리본 케이블 다른 끝을 **HAT 의 커넥터**에 넣습니다 — **구리 접점이 위**를 보게, 잠금쇠로 잠급니다.
7. HAT 의 고정 나사를 풀고 SSD 를 M.2 슬롯에 비스듬히 넣은 뒤 눌러서 나사로 고정합니다.

> 메타닉스 표시함은 RPi5 를 **LCD 뒷면**에 붙입니다. HAT 를 올리면 높이가 약 16 mm 늘어나므로, 표시함(깊이 150) 안에서 문을 닫았을 때 닿지 않는지 확인합니다.

## 3. SD 카드로 첫 부팅 · 부트로더 최신화

부트로더(EEPROM)가 오래되면 NVMe 로 부팅하지 못합니다. 먼저 SD 카드로 켜서 최신으로 올립니다.

1. PC 에서 **Raspberry Pi Imager** 로 SD 카드에 **Raspberry Pi OS (64-bit)** (Desktop) 을 씁니다.
   - 장치: Raspberry Pi 5 / 설정 편집: 호스트 이름 · 사용자 · 비밀번호 · 시간대 · SSH 사용 (6단계와 같게)
2. SD 카드를 꽂고 LAN · 화면을 연결해 전원을 켭니다.
3. 터미널에서:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo rpi-eeprom-update -a        # 부트로더 최신화 (이미 최신이면 그대로)
sudo reboot
lsblk                            # nvme0n1 이 보여야 SSD 가 인식된 것
```

`nvme0n1` 이 없으면: 리본 케이블 방향 · 끝까지 들어갔는지 · SSD 고정 나사를 확인합니다.

## 4. 부팅 순서를 NVMe 우선으로

```bash
sudo raspi-config
#  → 6 Advanced Options → A4 Boot Order → B2 NVMe/USB Boot → Finish
```

또는 직접:

```bash
sudo rpi-eeprom-config --edit
#  BOOT_ORDER=0xf416   ← 이 줄로 바꾸고 저장
```

`0xf416` 은 **오른쪽 자리부터** 시도합니다: 6 = NVMe → 1 = SD 카드 → 4 = USB → f = 처음부터 다시.
NVMe 가 고장 나면 SD 카드로 켜지므로, **SD 카드는 복구용으로 꽂아 둡니다.**

> 공식 M.2 HAT+ 는 자동으로 인식됩니다. 다른 회사 어댑터는 `PCIE_PROBE=1` 을 같이 넣어야 할 수 있습니다.

## 5. OS 를 NVMe 에 쓰기

**방법 A (권장) — Pi 에서 바로 쓰기.** SD 카드로 켜진 상태에서:

1. 메뉴 → 보조 프로그램 → **Raspberry Pi Imager** (없으면 `sudo apt install -y rpi-imager`)
2. 장치 **Raspberry Pi 5** → OS **Raspberry Pi OS (64-bit)** → 저장소 **NVMe (nvme0n1, 약 256 GB)**
   - 저장소에 SD 카드(mmcblk0)를 고르지 않도록 크기를 확인합니다.
3. 「설정 편집」에 6단계 값을 넣고 쓰기 → 완료되면 `sudo poweroff`.

**방법 B — PC 에서 쓰기.** USB–NVMe 어댑터에 SSD 를 끼워 PC 의 Raspberry Pi Imager 로 쓴 뒤 HAT 에 장착합니다.

## 6. NVMe 로 부팅 · 기본 설정

전원을 다시 켜면 NVMe 로 부팅합니다(SD 카드가 꽂혀 있어도 NVMe 가 먼저).

| 항목 | 권장 값 |
|---|---|
| 호스트 이름 | `mtx-0001` (장비 번호와 같게) |
| 사용자 | `pi` (앱이 이 사용자로 자동 로그인해 실행됨) + 강한 비밀번호 |
| 시간대 | 현장 기준 — 키르기스스탄 `Asia/Bishkek` (공장 시험 중엔 `Asia/Seoul` 도 됨) |
| SSH | 사용 (원격 점검용) |
| Wi-Fi | 쓰지 않으면 끔 (LAN · LTE 라우터 사용) |

```bash
findmnt -n -o SOURCE /            # /dev/nvme0n1p2 이면 NVMe 부팅 성공
sudo apt update && sudo apt full-upgrade -y
```

> PCIe Gen 3 (선택): `sudo raspi-config` → Advanced → PCIe Speed 로 켤 수 있으나 공식 인증 속도가 아닙니다. 메타닉스는 기본(Gen 2)으로 충분합니다.

## 7. 앱 설치 (한 줄)

```bash
curl -fsSL https://raw.githubusercontent.com/BlessingQ/Methanics-HMI-Public/main/bootstrap.sh | bash
sudo reboot
```

설치 스크립트가 하는 일은 [README](../README.md) 2장에 있습니다. 재부팅하면 자동 로그인 뒤 앱이 전체화면으로 뜹니다.

> 새 OS 에는 한글 글꼴이 없어 처음 몇 줄은 영문으로 나오고, 스크립트가 맨 먼저 한글 글꼴을 설치합니다. 그 뒤에도 한글이 □ 로 보이면 터미널을 닫았다 열고 같은 명령을 한 번 더 실행하세요 (반복해도 안전합니다).

## 8. 현장 설정

### 8-1. 설정 파일 `/etc/methanics/config.yaml`

```bash
sudo nano /etc/methanics/config.yaml
systemctl --user restart methanics-hmi      # 저장 뒤 앱 다시 시작
```

| 키 | 할 일 |
|---|---|
| `device_id` | 장비 번호 (예 `MTX-0001`) — 데이터 업로드의 장비 ID |
| `site_id` · `timezone` | 설치 농장 · 시간대 |
| `admin_pin` | 기본 `1234` → **반드시 바꿈** |
| `simulate` | `false` 확인 (true 면 가짜 값) |
| `expect_nvme` | `true` (기본) — SD 로 켜지면 상단에 「SD 부팅」 경고. M.2 오기 전 SD 로만 시험할 때는 `false` |
| `iot.enabled` · `iot.upload` | `true` — 관제 서버 연결 · 1분 평균 측정 기록 업로드 (대시보드에서 승인 필요, 키 발급 없음) |

### 8-2. 통신 포트 지정 (USB 변환기 고르기)

USB 변환기 번호(`/dev/ttyUSB0~`)는 재부팅마다 바뀝니다. 앱이 변환기의 **칩 시리얼 번호**로 기억하게 합니다.

1. 변환기 3개를 꽂습니다 — Modbus 용 FUS-1T, IOC-100 · BPC-100 공용 FUS-1T, CH₄ 센서 USB-C 케이블(RPi5 에 직결).
2. 앱 [설정](관리자 PIN) → **「통신 포트」** → 회선마다 **[지정]** → 목록에서 그 변환기를 누릅니다.
   - 목록에 「FT232R USB UART · 시리얼 A1062KUD · ttyUSB0」 처럼 나옵니다. 어느 것인지 모르면 하나씩 뽑았다 꽂으며 목록을 다시 엽니다.
3. **[지금 다시 시작]** → 약 10초 뒤 앱이 다시 뜨고, [정보] → 장치 통신이 「정상」 이면 끝.

| 회선 | 연결 |
|---|---|
| Modbus 센서 | FUS-1T #1 — GMP252 · EE650 · 센서노드 |
| IOC-100 · BPC-100 (공용) | FUS-1T #2 — 한 회선 9600 (장치유형으로 구분) |
| CH₄ 센서 | Axetris USB-C 케이블 (RPi5 USB-A 에 직결, 허브 거치지 않음) |

- 시리얼이 있는 변환기(FTDI 등)는 **다른 USB 구멍에 꽂아도** 그대로 열립니다. 시리얼이 없는 변환기(CH340 등)는 **꽂은 구멍 위치**로 기억하므로 구멍을 바꾸면 다시 [지정] 합니다 (화면에 「USB 구멍 위치」로 표시).
- 기억은 `/var/lib/methanics/ports.json` 에 남고 업데이트 · 롤백해도 유지됩니다.
- 터미널로 확인: `methanics-list-serial` (시리얼 · 위치), `methanics-status` 「회선 포트」(기억한 경로).
- udev 고정 이름(`/dev/mtx-*`)을 쓰고 싶으면 `/etc/udev/rules.d/99-methanics-serial.rules` 템플릿을 채웁니다 (선택).

> **BPC-100 펌웨어**: IOC-100 과 한 회선(9600)을 쓰려면 BPC-100 이 공용 회선 펌웨어여야 합니다. 현 v1.8 은 J13(XBee 소켓) 115200 전용이라 이 회선에서 응답하지 않습니다 — [정보] 에서 BPC-100 만 오류면 이 때문입니다.

## 9. 확인 체크리스트

| 확인 | 방법 | 정상 |
|---|---|---|
| NVMe 부팅 | `methanics-nvme-check` | 「결과: 정상」 |
| 앱 자동 시작 | 재부팅 | 1분 안에 전체화면 |
| 서비스 · 헬스 | `methanics-status` | 자동 시작 enabled · 헬스 마커 시각이 1분 안 (멈춤 감지는 앱 안 감시) |
| 통신 포트 | 앱 [설정] → 통신 포트 | 3개 모두 초록 · 「시리얼 …」 |
| 장치 통신 | 앱 [정보] → 장치 통신 | 6개 「정상」 |
| 관제 서버 | 앱 [정보] → 서버 연결 | 「연결됨 · 승인 대기」 → 대시보드 승인 → 「연결됨」 |
| 측정 기록 업로드 | 앱 [정보] → 서버 연결 · 대시보드 「측정 기록」 | 「정상 · 마지막 hh:mm:ss」 · 표에 1분마다 1줄 |
| 업데이트 | 앱 [정보] → 업데이트 [확인] | 「최신 버전입니다」 |
| 시뮬레이션 꺼짐 | 상단 표시 | 「시뮬레이션」 칩이 없음 |
| 시각 (RTC · NTP) | 앱 [설정] → 시간 · RTC | NTP 「켜짐 · 맞춰짐」 · RTC 시각 있음 · 충전 「켜짐」. 인터넷이 없으면 [시각 맞추기] 로 맞춤 (RTC 에도 기록). 인터넷을 끊고 전원을 뽑았다 켜도 시각이 맞음 |

## 9-1. SD 카드에 먼저 설치했다면 — NVMe 로 옮기기

M.2 가 오기 전에 SD 카드로 설치 · 시험했다면 처음부터 다시 할 필요 없이 그대로 복사합니다. 앱 · 설정 · 관제 서버 등록 정보 · 쌓인 기록이 함께 옮겨집니다.

1. M.2 HAT+ · SSD 장착 (2장) → SD 로 켜서 `lsblk` 에 `nvme0n1` 확인. 부트로더가 오래됐으면 3장의 `rpi-eeprom-update -a` 먼저
2. 앱 멈춤 (기록 파일을 쓰는 도중에 복사되지 않게): `systemctl --user stop methanics-hmi`
3. 메뉴 → 보조 프로그램 → **SD Card Copier** → From `mmcblk0`(SD) → To `nvme0n1`(SSD) → **「New Partition UUIDs」 체크** → Start
4. 부팅 순서 NVMe 우선 (4장) → 재부팅 → `methanics-nvme-check` 가 「결과: 정상」 이면 끝

| 주의 | 이유 |
|---|---|
| **New Partition UUIDs 꼭 체크** | 안 하면 SD 와 SSD 의 파티션 ID 가 같아, SD 를 꽂아 둔 채 켜면 엉뚱한 쪽 루트로 부팅될 수 있음 |
| 같은 Pi 보드에서 | 관제 서버 장비 ID 는 `rpi-<Pi 시리얼>` — 같은 보드면 승인 유지, 다른 보드에 SSD 를 끼우면 새 장비로 다시 승인 |
| 복사 뒤 SD | 그대로 꽂아 둠 (NVMe 고장 때 켜지는 복구용). **계속 동기화(RAID)되지 않음** — 복사한 순간의 상태 그대로라, 설정을 크게 바꾼 뒤(현장 설치 · 교정 계수 확정)에 다시 복사해 둠. 앱 버전은 SD 로 켜진 뒤 OTA 로 올리면 됨 |
| 시뮬레이션 | 책상 시험에서 `simulate: true` 로 바꿨다면 현장 전에 `false` 로 |

## 10. 문제 해결

| 증상 | 확인 |
|---|---|
| `lsblk` 에 nvme 가 없음 | 리본 케이블 방향(Pi 쪽 접점 = USB 쪽, HAT 쪽 접점 = 위) · 잠금쇠 · SSD 나사. 3단계 부트로더 최신화 |
| 계속 SD 카드로 부팅 | `methanics-nvme-check` 의 BOOT_ORDER 첫 자리가 6 인지. NVMe 에 OS 를 썼는지 |
| 무지개 화면에서 멈춤 | 전원 부족 — 27 W 어댑터로 시험, 현장은 5 V 전원을 5.2 V 로 조정 |
| 앱이 안 뜨고 바탕화면만 | `methanics-status`, `journalctl --user -u methanics-hmi -n 50` |
| 포트 열기 실패 (Permission denied) | `groups` 에 dialout 이 있는지 → 재부팅 |
| CH₄ 값이 안 들어옴 | [설정] → 통신 포트의 CH₄ 가 초록인지, `config.txt` 에 `usb_max_current_enable=1` 이 있는지(설치 스크립트가 넣음, 재부팅 필요) |
| 정전 뒤 시각이 틀어짐 | RTC 배터리(J5) 연결 · `methanics-status` 의 RTC 충전이 「켜짐」 인지 (꺼짐이면 `sudo ./install.sh` 다시 + 재부팅). 인터넷이 연결되면 NTP 로 다시 맞음 |
| 관제 서버 「재시도 대기」 | 인터넷 연결, 서버 주소(`iot.server_url`). 「토큰 불일치 (401)」 이면 대시보드 「등록 초기화」 |

---
㈜아이온텍 · Methanics CH₄ 측정 급이기
