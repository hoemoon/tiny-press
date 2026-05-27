# tinypress — CLI 매뉴얼

`tinypress`는 tiny press의 커맨드라인 진입점입니다.

> 상태: `init`, `build`, `preview`는 현재 사용 가능. `serve`(이미 빌드된
> 트리를 watch 없이 서빙)는 추가 예정.

## 설치

### Homebrew (권장)

```bash
brew install hoemoon/tinypress/tinypress
```

### 소스에서 빌드

```bash
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press/core
swift build -c release
cp .build/release/tinypress /usr/local/bin/
```

Xcode 26 / Swift 6.3 toolchain 필요.

## 빠른 시작

```bash
tinypress init my-blog --title "My Blog"
cd my-blog
tinypress build
python3 -m http.server -d _site 8000   # 로컬에서 미리 보기
```

## 명령어

`<!-- BEGIN_HELP:* -->` 블록은 `core/scripts/generate-manual.py`가
`tinypress --help` 출력으로부터 다시 채웁니다. 손으로 편집하지 마세요 —
아래 *매뉴얼 동기화* 섹션 참조.

<!-- BEGIN_HELP:root -->
```
OVERVIEW: tiny press — 작은 정적 사이트 생성기.

USAGE: tinypress <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  init                    지정한 경로에 새 tiny press 사이트를 스캐폴드합니다.
  build                   --source의 사이트를 --output 폴더로 렌더링합니다.
  preview                 사이트를 빌드하고 변경을 감지하면서 로컬에서 라이브 리로드와 함께 서빙합니다.

  See 'tinypress help <subcommand>' for detailed help.
```
<!-- END_HELP:root -->

### `tinypress init <path>`

`<path>`에 새 tiny press 사이트 폴더를 만듭니다. 폴더가 없으면 생성하고,
비어있지 않은 폴더는 덮어쓰지 않습니다.

<!-- BEGIN_HELP:init -->
```
OVERVIEW: 지정한 경로에 새 tiny press 사이트를 스캐폴드합니다.

USAGE: tinypress init <path> [--title <title>]

ARGUMENTS:
  <path>                  새 사이트가 생성될 폴더 경로.

OPTIONS:
  --title <title>         새 사이트의 제목. (default: My Site)
  --version               Show the version.
  -h, --help              Show help information.
```
<!-- END_HELP:init -->

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `<path>` | *(필수)* | 생성할 폴더 경로. |
| `--title <title>` | `My Site` | `tinypress.yml`에 기록할 사이트 제목. |

생성되는 구조:

```
<path>/
├── tinypress.yml                 # SiteConfig (title/theme/language/...)
├── content/
│   ├── posts/hello.md            # frontmatter가 들어간 샘플 포스트
│   └── pages/about.md            # 샘플 페이지
└── static/                       # 정적 에셋, 그대로 복사됨
```

생성된 사이트의 절대 경로를 stdout에 출력하고, 로그는 stderr로 보냅니다.

**예시**

```bash
$ tinypress init ./demo --title "Demo Site"
Created site at /Users/me/demo
Next: cd ./demo && tinypress build
/Users/me/demo
```

### `tinypress build`

`--source`의 사이트를 `--output`으로 렌더링합니다. 같은 입력은 항상 같은
결과 트리를 만듭니다 (멱등).

<!-- BEGIN_HELP:build -->
```
OVERVIEW: --source의 사이트를 --output 폴더로 렌더링합니다.

USAGE: tinypress build [--source <source>] [--output <output>] [--include-drafts]

OPTIONS:
  -s, --source <source>   소스 폴더. 기본값은 현재 디렉터리. (default: .)
  -o, --output <output>   출력 폴더. 기본값은 <source>/_site.
  --include-drafts        draft: true로 표시된 포스트도 포함.
  --version               Show the version.
  -h, --help              Show help information.
```
<!-- END_HELP:build -->

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `-s`, `--source <path>` | `.` | `tinypress.yml`이 들어있는 소스 폴더. |
| `-o`, `--output <path>` | `<source>/_site` | 출력 폴더. 매 빌드마다 비워집니다 (점으로 시작하는 항목은 보존). |
| `--include-drafts` | off | frontmatter에 `draft: true`로 표시된 포스트도 포함. |

동작:

- 빌드 시작 시 출력 폴더를 비웁니다 — `.git`, `.DS_Store` 등
  dot-prefixed 항목은 그대로 유지.
- `draft: true` 페이지는 기본 제외; `--include-drafts`로 포함시킬 수
  있습니다.
- 페이지 단위 에러(잘못된 YAML, 누락된 레이아웃 등)는 해당 페이지만
  실패시키고 빌드 보고서의 warnings에 기록 — 나머지는 계속 진행.
- 동일한 slug 충돌은 빌드를 중단시키는 하드 에러입니다.

성공 시 절대 출력 경로 한 줄을 stdout으로 출력. 실패 시 exit code `1`과
함께 stderr에 메시지가 남습니다.

**예시**

```bash
$ tinypress build --source ./demo --include-drafts
Building /Users/me/demo → /Users/me/demo/_site
Built 4 page(s) and copied 3 asset(s) in 0.123s
/Users/me/demo/_site
```

### `tinypress preview`

사이트를 빌드한 뒤 소스 트리를 감시하면서, 라이브 리로드 기능을 가진
로컬 HTTP 서버로 결과물을 서빙합니다. foreground 프로세스 — Ctrl-C로
중단합니다.

<!-- BEGIN_HELP:preview -->
```
OVERVIEW: 사이트를 빌드하고 변경을 감지하면서 로컬에서 라이브 리로드와 함께 서빙합니다.

USAGE: tinypress preview [--source <source>] [--output <output>] [--port <port>] [--host <host>] [--include-drafts] [--share]

OPTIONS:
  -s, --source <source>   소스 폴더. 기본값은 현재 디렉터리. (default: .)
  -o, --output <output>   출력 폴더. 기본값은 <source>/_site.
  -p, --port <port>       선호 로컬 포트 (사용 중이면 자동으로 다음 빈 포트). (default: 8080)
  --host <host>           바인드 호스트. (default: 127.0.0.1)
  --include-drafts        draft: true로 표시된 포스트도 포함.
  --share                 `tailscale serve`로 tailnet에 프리뷰를 미러링.
  --version               Show the version.
  -h, --help              Show help information.
```
<!-- END_HELP:preview -->

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `-s`, `--source <path>` | `.` | `tinypress.yml`이 들어있는 소스 폴더. |
| `-o`, `--output <path>` | `<source>/_site` | 렌더링 결과가 떨어지는 위치. watcher가 무시. |
| `-p`, `--port <n>` | `8080` | 처음 시도하는 포트. 사용 중이면 자동으로 다음 빈 포트를 찾음. |
| `--host <host>` | `127.0.0.1` | 바인드 인터페이스. LAN 노출은 `0.0.0.0`. |
| `--include-drafts` | off | `draft: true` 포스트도 포함. |
| `--share` | off | `tailscale serve`로 tailnet에 미러링. Tailscale 데몬이 실행 중이고 로그인되어 있어야 합니다. |

동작:

- 첫 빌드는 동기적으로 실행되며, 성공해야 서버가 시작됩니다. 첫 빌드가
  실패하면 exit `1`로 중단.
- watcher는 변경 버스트를 300ms 윈도우로 디바운스합니다. 이후 빌드 에러는
  로그만 남기고 서버를 내리지 않습니다 — 직전 출력이 계속 서빙됩니다.
- HTML 응답에는 작은 `<script>`가 자동 주입되어 `/__tinypress_reload`로
  SSE 연결을 열고, 재빌드 시 push되는 `reload` 이벤트로 브라우저가 자동
  새로고침합니다.
- `--share`는 `tailscale serve`를 셸 호출 (macOS 앱과 CLI가 같은
  `TailscaleServeAdapter`를 공유). 실패 시 fail-closed: 데몬이 없거나
  로그아웃 상태라도 로컬 프리뷰는 계속 동작하고 stderr에 경고만 남깁니다.

stdout에는 로컬 URL 한 줄만 출력하므로, 래퍼 스크립트가 로그를 파싱하지
않고도 URL을 읽을 수 있습니다.

**예시**

```bash
$ tinypress preview --source ./demo --share
Building /Users/me/demo → /Users/me/demo/_site
Preview server listening at http://127.0.0.1:8080/
Tailscale share: https://laptop.tail-scale.ts.net/
Watching for changes — Ctrl-C to stop.
http://127.0.0.1:8080/
```

## 폴더 컨벤션

빌더가 두 가지 레이아웃을 자동 감지합니다.

### Structured (전통 방식)

```
my-site/
├── tinypress.yml                 # SiteConfig
├── content/
│   ├── posts/                    # Page.Kind.post — 파일명에서 slug 추출
│   │   └── 2026-01-01-hello.md
│   ├── pages/                    # Page.Kind.page
│   │   └── about.md
│   └── index.md                  # Page.Kind.index (옵션)
└── static/                       # 출력 루트로 그대로 복사됨
    └── images/
```

### Flat (Obsidian 호환 / naverp 아카이브 호환)

```
my-channel/                       # tinypress.yml 없어도 동작
├── index.md                      # 옵션 — 홈페이지
├── 260124144615127ua.md          # 루트의 모든 .md는 기본적으로 post
├── 260124144615127ua/            # .md와 같은 이름의 형제 폴더 = 자산 사이드카
│   ├── 01.png
│   └── 02.jpg
├── 260303233251216jo.md
└── about.md                      # frontmatter에 `kind: page` 두면 page로 분류
```

자동 감지 규칙: `posts/` 또는 `pages/` 디렉터리가 콘텐츠 루트에 없으면
**flat 모드**. 사이트 루트에 `content/` 서브폴더가 없으면 사이트 루트
자체를 콘텐츠 루트로 간주.

Flat 모드에서:

- 모든 `.md` 가 post (frontmatter `kind: page` 로 옵아웃 가능)
- `<basename>.md` 옆의 `<basename>/` 폴더 내용물은 글 출력 디렉터리로 복사
- 본문의 `![](./<basename>/X)` 링크는 빌드 시 `![](./X)` 로 재작성되어
  발행 URL에서 그대로 동작 (원본 markdown은 Obsidian에서도 그대로 열림)
- 사이드카는 `permalinkStyle: pretty` 일 때만 동작. `file` 스타일은 경고
  남기고 사이드카 복사 건너뜀

이 레이아웃 덕분에 `tinypress build --source ~/Documents/Naverp/wave`
같이 별도 변환 단계 없이 naverp 아카이브를 그대로 사이트로 빌드합니다.

콘텐츠 작성 가이드(frontmatter 필드, 테마 오버라이드)는
[`docs/CONTENT.md`](docs/CONTENT.md)와
[`docs/THEMING.md`](docs/THEMING.md)에 있습니다.

## Exit code

| 코드 | 의미 |
|---|---|
| 0 | 성공. |
| 1 | 빌드 또는 스캐폴드 실패 (메시지는 stderr). |
| 2 | 인자 파싱 에러 (ArgumentParser 기본). |
| 64 | `--help` / `--version` 출력 후 종료 (ArgumentParser 관례). |

## 로깅

상태/에러 메시지는 모두 **stderr**로 갑니다 (info는 prefix 없음, error는
`error: ` prefix). **stdout** 한 줄은 결과 경로이므로, `tinypress`를 셸
파이프라인에 안전하게 끼워 쓸 수 있습니다:

```bash
output=$(tinypress build --source ./demo)
rsync -av "$output/" user@host:/var/www/demo/
```

## 매뉴얼 동기화

`<!-- BEGIN_HELP:* -->` 블록은 `core/scripts/generate-manual.py`가
서브커맨드별 `tinypress --help` 출력을 캡처해 마커 사이에 다시 채워
넣습니다. 두 가지 호출 경로:

- **Claude Code 안에서** — `/menual` 스킬을 호출하거나, "매뉴얼
  갱신해줘" 같은 자연어로 요청. 스킬이 스크립트를 실행하고 변경 여부를
  보고합니다.
- **셸에서 직접** — 저장소 루트에서
  `python3 core/scripts/generate-manual.py`. `--check`는 파일을 쓰지
  않고 drift만 감지(drift 시 exit 1) — 본인 push 전 검증용.

CLI 플래그를 변경한 사람이 같은 커밋에 `core/MANUAL.md` diff를 함께
stage할 책임을 갖습니다 — 이를 강제하는 자동화는 두지 않았습니다.

새 서브커맨드를 자동 채움 대상에 추가하려면 `generate-manual.py` 상단의
`COMMANDS` 매핑에 이름을 추가하고, 이 파일에 대응하는
`<!-- BEGIN_HELP:<name> -->` / `<!-- END_HELP:<name> -->` 마커 쌍을
넣어주세요.
