---
name: menual
description: Regenerate `core/MANUAL.md` so it stays in sync with the live `tinypress --help` output. The manual must be entirely in Korean (한글). Invoke after editing files under `core/Sources/tinypress-cli/`, when the user asks to refresh, sync, rebuild the CLI manual, or 매뉴얼 갱신해달라고 요청할 때. Skip when only `core/Sources/TinyPressKit/` changed — kit edits don't affect the CLI surface.
---

# menual — sync MANUAL.md (한글)

`core/MANUAL.md`는 손글씨 산문과 `<!-- BEGIN_HELP:* -->` 자동 채움
블록의 혼합입니다. 이 스킬은:

1. `generate-manual.py`를 실행해 자동 블록을 현재 `tinypress --help`
   출력으로 다시 채웁니다.
2. **MANUAL.md 전체가 한글로 작성되어 있는지** 점검·보정합니다.

CLI 자체의 `abstract` / `help: "..."` 문자열이 한글로 작성되어 있으므로
(`core/Sources/tinypress-cli/`의 각 Command 파일 참고), 스크립트가
캡처하는 `--help` 출력도 자연스레 한글입니다. 따라서 산문과 자동 블록
양쪽이 모두 한글이 되는 것이 정상입니다.

## 언어 정책

| 매뉴얼 요소 | 언어 |
|---|---|
| 제목, 본문, 표 헤더/설명 | 한글 |
| 옵션·플래그 이름 (`--source`, `-p` 등) | 영문 그대로 |
| 코드 블록 (셸 명령, 파일 경로, 코드 샘플) | 영문 그대로 |
| `<!-- BEGIN_HELP:* -->` 블록 | 한글 (CLI가 한글 help를 출력하므로 자동) |
| ArgumentParser 자체 문자열 (`USAGE:`, `OPTIONS:`, `Show help information.` 등) | 영문 그대로 (라이브러리 내장) |

만약 자동 블록에 영문이 섞여 나오면 그건 누군가 CLI 소스의
`help: "..."`를 영문으로 추가한 것이므로, **스킬은 그 한글 번역까지
함께 수정**해서 일관성을 회복해야 합니다.

## 호출 시점

CLI 표면을 바꾸거나 매뉴얼에 영문이 섞일 수 있는 모든 변경 후:

- `core/Sources/tinypress-cli/`의 `.swift` 파일 편집
- 서브커맨드 추가/제거 (이 경우 `core/scripts/generate-manual.py`의
  `COMMANDS`도 갱신하고 MANUAL.md에 마커 쌍 추가)
- 사용자가 "매뉴얼 갱신", "manual refresh", "MANUAL.md 다시 써줘"
  같은 요청
- 직전 편집이 매뉴얼 중간에 영문 단락을 남긴 경우

`TinyPressKit`만 건드린 경우는 호출하지 않음 — `swift build`가
~1초 낭비됩니다.

## 실행

저장소 루트에서:

```bash
python3 core/scripts/generate-manual.py
```

스크립트 동작:

1. `tinypress` 바이너리를 debug로 빌드 (incremental — 첫 실행 후엔
   1초 미만).
2. `COMMANDS` 매핑의 각 서브커맨드에 대해 `tinypress --help`를
   캡처.
3. 일치하는 `<!-- BEGIN_HELP:<name> -->` / `<!-- END_HELP:<name> -->`
   마커 쌍 사이를 캡처한 출력으로 덮어씀.

스크립트 종료 후 **반드시 산문도 훑어보세요**. 최근 커밋이 영문
단락을 남겼다면(새 서브커맨드가 영어로 합쳐져 들어온 경우 등),
의미·구조·서식은 그대로 두고 한글로 번역. 코드 예시·플래그 이름·자동
블록은 절대 손대지 말 것.

스크립트 출력:

- `core/MANUAL.md already up to date` — 자동 블록 변경 없음. 그래도
  산문에 영문 회귀가 있는지 한 번 더 확인.
- `updated core/MANUAL.md` — 자동 블록이 다시 쓰여짐. CLI 변경과
  같은 커밋에 함께 stage.

`--check`는 파일을 쓰지 않고 drift만 감지 (drift 시 exit 1).

## 실행 후

`core/MANUAL.md`를 stage:

```bash
git diff core/MANUAL.md     # 산문 번역과 자동 블록 변경 둘 다 검토
git add core/MANUAL.md
```

스크립트 실패 시:

- *swift build failed* — `xcode-select`가 CommandLineTools를 가리키는
  경우. `DEVELOPER_DIR=/Applications/Xcode-26.4.1.app/Contents/Developer`
  를 설정하고 다시 실행.
- *MANUAL.md references unknown help block* — MANUAL.md에 있는
  `BEGIN_HELP:<name>` 마커가 `COMMANDS`에 없음. 매핑에 추가하거나
  마커를 제거.
