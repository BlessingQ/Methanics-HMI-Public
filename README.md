# 메타닉스 HMI — 설치 안내서

㈜아이온텍 **메타닉스(Methanics) CH₄ 측정 급이기**의 터치 화면 · 장치 제어 앱을 **Raspberry Pi 5**에 설치하고, 자동으로 시작하고, 원격으로 업데이트하는 저장소입니다.

> 이 저장소에는 **설치 스크립트와 빌드된 앱 패키지(Releases)만** 있습니다. 앱 소스 코드는 들어 있지 않습니다.

처음 설치하는 장비는 **[초기 설정 안내서 (M.2 NVMe)](docs/1_초기설정_M2_NVMe.md)** 를 순서대로 따라 하세요.

## 1. 대상 환경

| 항목 | 요구 사항 |
|---|---|
| 보드 | Raspberry Pi 5 (4 GB 이상) + M.2 HAT+ + NVMe SSD 256 GB (NVMe 부팅) |
| OS | Raspberry Pi OS **64-bit, Desktop** (Bookworm 이상). Lite 는 안 됨 — 화면이 필요 |
| 화면 | 10.1" 1280×800 정전식 터치 (HDMI + USB 터치) |
| 통신 | USB-RS485 3채널 (FUS-1T: Modbus 센서 · BPC-100 · IOC-100) + CH₄ 센서 USB-C 직결 |
| 네트워크 | 설치 · 업데이트 · 관제 서버 연결에 인터넷 (현장은 LTE 라우터). 측정 · 제어는 인터넷 없이 동작 |

## 2. 설치 (한 줄)

Raspberry Pi 5 의 터미널에서:

```bash
curl -fsSL https://raw.githubusercontent.com/BlessingQ/Methanics-HMI-Public/main/bootstrap.sh | bash
sudo reboot
```

이 명령이 하는 일:

1. `git` 설치 → 이 저장소를 `~/Methanics-HMI-Public` 에 클론
2. `install.sh` 를 `sudo` 로 실행
   - 필수 패키지 설치, 사용자를 `dialout` · `gpio` 그룹에 추가, **ModemManager 제거** (CH₄ 센서 USB 포트 보호)
   - `/opt/methanics/` 구성 (`releases/`, `current` 링크, `bin/`, `downloads/`, `health/`), 데이터 `/var/lib/methanics`
   - GitHub **Releases 의 최신 패키지**를 받아 **sha256 검증** 후 설치
   - `/etc/methanics/config.yaml` 설정 파일 생성 (이미 있으면 유지)
   - 시리얼 udev 규칙 템플릿 (`/dev/mtx-*` 고정 이름)
   - `config.txt` 에 `usb_max_current_enable=1` (CH₄ 센서 USB 5 V 전원)
   - 데스크톱 **자동 로그인**, **화면 꺼짐 방지**
   - **systemd 사용자 서비스** → 부팅 때 앱 자동 시작, 죽으면 5초 뒤 재시작
   - 헬스체크 타이머 → 업데이트 뒤 기동 실패가 반복되면 **자동 롤백**, 앱이 멈추면 재시작
3. 재부팅하면 자동 로그인 → 앱이 전체화면으로 시작합니다.

수동 설치도 같습니다:

```bash
git clone https://github.com/BlessingQ/Methanics-HMI-Public.git ~/Methanics-HMI-Public
cd ~/Methanics-HMI-Public
sudo ./install.sh --user $USER
```

| 옵션 | 설명 |
|---|---|
| `--local app.tar.gz` | GitHub 대신 직접 빌드한 패키지를 설치 |
| `--user pi` | 앱을 실행할 데스크톱 사용자 (기본: sudo 를 호출한 사용자) |
| `--no-kiosk` | 자동 로그인 · 화면 꺼짐 설정을 건드리지 않음 |
| `--keep-modemmanager` | ModemManager 를 지우지 않음 |

## 3. 설치 뒤 반드시 할 일

1. **설정 파일** `/etc/methanics/config.yaml` — `device_id` · `admin_pin`(기본 1234 → 바꿈) · `simulate: false`. 고친 뒤 `systemctl --user restart methanics-hmi`.
2. **시리얼 포트 고정** — `methanics-list-serial` 로 확인 → `/etc/udev/rules.d/99-methanics-serial.rules` 수정 → `ls -l /dev/mtx-*`.
3. **관제 서버 승인** — 앱이 IONTEC IoT 관제 서버에 처음 연결하면 대시보드에 「승인 대기」(장치 종류 「메타닉스」)로 나타납니다. 관리자가 승인하면 원격 진단 · 원격 업데이트를 쓸 수 있고, **1분 평균 측정 기록**이 대시보드 「측정 기록」 표에 쌓이기 시작합니다.

자세한 순서와 확인 체크리스트: [초기 설정 안내서](docs/1_초기설정_M2_NVMe.md) 8 · 9장.

## 4. 설정 파일 `/etc/methanics/config.yaml`

`config/config.example.yaml` 이 처음에 복사됩니다. 업데이트를 해도 이 파일은 덮어쓰지 않습니다. 관리자 PIN 이 들어가므로 앱 사용자만 읽을 수 있습니다(0640).

| 묶음 | 키 | 내용 |
|---|---|---|
| 장비 | `device_id` · `site_id` · `timezone` · `admin_pin` · `simulate` | 장비 번호 · 농장 · 시간대 · 관리자 PIN · 시뮬레이션(현장은 false) |
| 포트 | `ports.modbus` · `ioc` · `bpc` · `ch4` | 기본 `/dev/mtx-*`. `/dev/serial/by-id/...` 고유 경로를 직접 적어도 됨 |
| 업데이트 | `update.repo` · `channel` · `auto` · `check_interval_h` | 기본 이 저장소 · stable · **수동** · 6시간 |
| 관제 서버 | `iot.enabled` · `iot.server_url` · `iot.upload` | 기본 켬 · `wss://iot.ionteclab.com/ws/device` · 1분 평균 측정 기록 업로드 켬 |

측정 · 교정 파라미터(명세 15장)는 예시 파일의 주석을 보세요.

## 5. 운영 명령

| 명령 | 설명 |
|---|---|
| `methanics-status` | 버전 · 서비스 · 헬스 · 포트 · 관제 서버 설정 · 저장 장치 요약 |
| `methanics-nvme-check` | NVMe 부팅 · 부팅 순서 · PCIe 속도 점검 |
| `methanics-list-serial` | USB 시리얼 컨버터 식별 정보 (udev 규칙 작성용) |
| `journalctl --user -u methanics-hmi -f` | 앱 로그 실시간 보기 |
| `systemctl --user restart methanics-hmi` | 앱 재시작 |
| `methanics-fetch-release --activate` | 최신 릴리스 받아 적용 (앱 화면 업데이트 버튼과 같음) |
| `methanics-fetch-release --tag v0.2.0 --activate` | 특정 버전 적용 (되돌리기에도 사용) |
| `methanics-rollback` | 직전 버전으로 되돌리기 |
| `sudo methanics-guard` | 자동 시작 유닛 점검 · 복구 (부팅마다 자동 실행) |
| `sudo ~/Methanics-HMI-Public/uninstall.sh [--purge]` | 제거 (`--purge`: 설정 · 데이터까지) |

## 6. 업데이트 (OTA)

새 버전은 이 저장소의 **Releases** 에 올라옵니다. 기기는 토큰 없이 공개 저장소를 조회합니다. 업데이트 방법은 세 가지이고, 모두 같은 절차로 적용됩니다.

| 방법 | 동작 |
|---|---|
| **현장 화면** (기본) | 앱 [정보] → 업데이트 **[확인] → [받기] → [적용]**. 누르지 않으면 네트워크에 접근하지 않음 |
| **자동** | `update.auto: true` 면 `check_interval_h` 마다 확인 → 받기 → 적용 |
| **원격 (관제 대시보드)** | IONTEC IoT 관제 서버 대시보드에서 장비를 골라 [업데이트] → 버전 선택. 진행률 · 결과(성공 · 롤백)가 대시보드에 남음 |

공통 절차:

1. `methanics-hmi-linux-arm64-vX.Y.Z.tar.gz` 와 `.sha256` 을 받아 검증하고 `/opt/methanics/releases/vX.Y.Z` 에 풉니다.
2. `current` 링크를 바꾸고 앱을 재시작합니다 (약 30초). 재시작 동안 IOC-100 출력은 마지막 상태를 유지하고, 새 앱은 IOC 상태를 읽고 이어 받습니다.
3. 재시작 뒤 90초 안에 정상 기동 마커(`/opt/methanics/health/boot_ok`)가 없으면 **이전 버전으로 자동 롤백**합니다.
4. **교정 중에는 적용하지 않습니다** — 끝난 뒤 다시 합니다.

## 7. 릴리스 패키지 규격 (빌드 담당자용)

```
methanics-hmi-linux-arm64-v0.2.0.tar.gz
├── manifest.json   {"version":"0.2.0","min_from":"0.1.0","notes":"","built":"…","arch":"linux-arm64","commit":"abc1234"}
└── bundle/         flutter build linux --release 의 bundle 폴더 그대로
    ├── methanics_hmi   실행 파일
    ├── lib/            libflutter_linux_gtk.so, libserialport.so 등
    └── data/
methanics-hmi-linux-arm64-v0.2.0.tar.gz.sha256   (sha256sum 출력 형식)
```

Release 태그는 `vX.Y.Z` (prerelease 는 `vX.Y.Z-beta.N`, `update.channel: beta` 기기만 받음). 자산 이름이 `methanics-hmi-linux-arm64-*.tar.gz` 가 아니면 기기가 찾지 못합니다.

## 8. 문제 해결

| 증상 | 확인 |
|---|---|
| 상단에 빨간 「SD 부팅」 | NVMe 대신 SD 카드로 켜짐 = NVMe 고장 · 빠짐 · 부팅 순서. `methanics-nvme-check`. SD 는 복사 당시 상태라 설정 · 버전 확인 (SD 로만 시험하는 장비는 `expect_nvme: false`) |
| 부팅 뒤 바탕화면만 보임 | `methanics-status` → `current` 링크, `journalctl --user -u methanics-hmi -n 50` |
| 서비스가 **masked** / 유닛 파일 0바이트 | 전원 급차단 흔적. `sudo methanics-guard` (재부팅 때 자동) |
| 앱이 멈췄다가 저절로 재시작 | 정상 동작 — 1 Hz 제어 틱이 5분 넘게 멈추면 헬스체크가 재시작 (`/opt/methanics/health/hang_restarts.log`) |
| 업데이트 뒤 이전 버전으로 돌아감 | 새 버전이 정상 기동하지 않아 자동 롤백 (`/opt/methanics/health/rollback.log`). 로그 확인 후 다시 시도 |
| 포트 열기 실패 (Permission denied) | `groups` 에 dialout → 재부팅 |
| `/dev/mtx-*` 가 없음 | 3장 udev 규칙. `methanics-list-serial` 로 값 재확인 |
| 터치 · 전체화면이 안 됨 | `sudo raspi-config` → Advanced → Wayland → X11 로 바꿔 재부팅 |
| 관제 서버 「재시도 대기」 | 인터넷, `iot.server_url`. 「토큰 불일치 (401)」 이면 대시보드 「등록 초기화」 |
| 측정 기록 업로드 「승인 뒤 시작」 | 대시보드에서 장비 승인. 「서버에 운전 기록 API 없음 (404)」 이면 서버 v0.8.0 이상 필요 |

## 9. 저장소 구성

```
bootstrap.sh                 curl 한 줄 설치 진입점
install.sh                   설치 스크립트
uninstall.sh                 제거
docs/1_초기설정_M2_NVMe.md    처음 설치 안내서 (M.2 HAT+ 장착 → NVMe 부팅 → 앱 설치 → 현장 설정)
scripts/
  methanics-fetch-release.sh   Releases 다운로드 · sha256 검증 · 설치
  methanics-apply-update.sh    current 링크 교체 · 재시작 · 헬스 대기 · 실패 시 롤백
  methanics-rollback.sh        직전 버전 복귀
  methanics-healthcheck.sh     2분 타이머 — 기동 실패 반복 시 롤백, 하트비트 5분 정지 시 재시작
  methanics-run.sh             디스플레이 준비 대기 후 앱 실행 (systemd ExecStart)
  methanics-guard.sh           부팅 때 자동 시작 유닛 점검 · 복구 (root)
  methanics-status.sh          상태 요약
  methanics-nvme-check.sh      NVMe 부팅 점검
  methanics-list-serial.sh     USB 시리얼 식별 정보
config/
  methanics-hmi.service          systemd 사용자 서비스
  methanics-healthcheck.service / .timer
  methanics-guard.service        root 보호 서비스
  99-methanics-serial.rules      udev 템플릿
  config.example.yaml            설정 초기값
```

---
㈜아이온텍 (IONTEC Co., Ltd.) · 메타닉스 CH₄ 측정 급이기
