# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다. 형식은
[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 버전은
[Semantic Versioning](https://semver.org/lang/ko/)을 사용합니다.

## [Unreleased]

## [0.3.0] - 2026-10-30

### 제거
- **Breaking:** 레거시 `statusline.sh` 런타임과 `install.sh --runner sh` /
  `install.ps1 -Runner sh` 옵션. `statusline.sh`는 처음 개발할 때 MVP로
  만든 구현이고, Node 포트 `statusline.js`로 옮긴 뒤로는 역할이 끝나
  제거합니다. v0.2.0이 sh 런타임을 포함하는 마지막 릴리스입니다.
  `--runner sh`로 설치했던 환경은 설치 스크립트를 다시 실행하면 Node
  런타임으로 전환됩니다.

### 변경
- README: 한국어 문장을 번역투 없이 다듬었습니다. Windows 안내(기존 콘솔에서
  색은 나오지만 글리프가 네모로 깨짐, Windows Terminal 설치 방법)를 두 README
  모두 설치 절 앞쪽에 두었습니다. Windows 10 22H2 실기기로 확인했습니다.
  설치를 Claude Code에 맡기는 붙여 넣기용 프롬프트 소절을 추가했습니다.

### 수정
- `install.ps1`이 `settings.json`을 BOM 없는 UTF-8로 읽고 씁니다. PowerShell
  5.1의 `Get-Content -Raw`가 BOM 없는 파일을 시스템 코드페이지(한국어 Windows는
  cp949)로 읽어 한글 값이 깨지던 문제. PR #1(@Yeosangho)의 수정을 가져왔습니다.

## [0.2.0] - 2026-10-29

Claude Code 2.1.292의 status line 페이로드에 맞춰 상태줄을 최신화했습니다.
CLI에서 실제로 캡처한 페이로드로 검증했고, 두 런타임의 출력은 바이트 단위로
동일합니다.

### 추가
- 모델명 뒤에 `(high)` 같은 effort 단계 표시. `effort.level`에서 읽습니다.
- 3번째 줄에 `⚡ warm 65%` / `⚡ cold` 프롬프트 캐시 세그먼트.
  `prompt_cache.warm`과 `hit_ratio`에서 읽습니다.
- 4번째 줄에 지출 한도가 걸린 계정용 `Spend` 블록(bar, %, `$사용/$한도`,
  리셋까지 남은 시간). `rate_limits.spend_limit`에서 읽습니다.
- 2번째 줄 끝에 `#12 approved` / `!12 draft` PR·MR 배지. `pr.number`,
  `pr.review_state`, `pr.kind`에서 읽고, git 캐시 밖에서 그려 리뷰 상태
  변화가 바로 반영됩니다.
- `COLUMNS`가 100 미만이면 bar 폭을 10칸에서 5칸으로 자동 축소.
  `CCSL_BAR_WIDTH`를 명시하면 그 값을 우선합니다.
- 설치 스크립트가 `statusLine.refreshInterval: 30`을 기록해 메시지가 없어도
  `5h` 카운트다운이 줄어듭니다.
- 개인/팀 계정 판별을 `~/.claude.json`의 `oauthAccount.organizationType`과
  `seatTier`로 수행. 두 필드가 없는 구버전 파일은 기존 조직명 패턴을 씁니다.
- 실 페이로드 픽스처(`10-cc2-session-start`, `11-cc2-after-response`)와
  통합 테스트 5개(`install-settings`, `worktree`, `pr-badge`, `narrow`,
  `tenancy`).

### 변경
- 컨텍스트 토큰 수를 입력 토큰만으로 계산(`total_input_tokens`, 캐시
  읽기·쓰기 포함). Claude Code의 `used_percentage`와 같은 기준이 됩니다.
  이전에는 출력 토큰까지 더했습니다.
- 24자를 넘는 worktree 이름은 앞 22자 + `…`로 축약. `workspace.git_worktree`
  필드와 git-dir fallback 모두에 적용됩니다.
- README: Node 설치 안내, "마이그레이션 (sh → js)" 섹션, 새 스크린샷, 새
  세그먼트 설명. 한국어 README가 기본이 되고 영어판은 `README.en.md`로
  이동했습니다.

### 제거
- `❯ NORMAL` / `❯ INSERT` vim 세그먼트. Claude Code가 자체로 `-- INSERT --`를
  그리므로 중복이었습니다.

## [0.1.0] - 2026-04-30

### 추가
- 4줄 상태줄 초기 버전: cwd, git 브랜치와 더티 상태(worktree 표시 포함),
  모델과 컨텍스트 bar, 세션 비용, 5시간·주간 한도, `~/.claude.json` 기반 계정
  표시.
- Node 포트 `statusline.js`(Node ≥18, npm 의존성 없음)를 정식 런타임으로,
  `statusline.sh`는 바이트 일치 레퍼런스 구현으로 유지.
- `install.sh`(macOS / Linux / WSL2)와 `install.ps1`(Windows). 기존 자산은
  타임스탬프 백업 후 교체.
- 스냅샷 테스트 러너(plain·ANSI 모드), 콜드 스타트 perf 게이트, git 없음 /
  HOME 없음 / 설치 백업 통합 테스트.
- 영어·한국어 README.

[Unreleased]: https://github.com/seungho-jeong/claude-code-statusline/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/seungho-jeong/claude-code-statusline/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/seungho-jeong/claude-code-statusline/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/seungho-jeong/claude-code-statusline/releases/tag/v0.1.0
