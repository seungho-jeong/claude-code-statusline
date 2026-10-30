[English](README.en.md) | **한국어**

# claude-code-statusline

> **흘끗 보기만 하면 됩니다.**  
> [Claude Code](https://www.anthropic.com/claude-code)의 사용량 한도, 컨텍스트, 로그인 계정을 화면 아래에 항상 띄워 줍니다.

`/usage`, `/context`, `claude auth status`를 치느라 작업을 끊을 필요가 없습니다.

## 미리보기

**개인 계정 (비용 경고 표시 중)**

![개인 계정 렌더링](docs/images/personal.png)

**팀 계정 (linked worktree에서 실행)**

![팀 계정 렌더링](docs/images/team.png)

## 한눈에 보기

- **`5h` 한도**: 사용률 bar와 %, 리셋까지 남은 시간. 15분 미만이면 `!`를 붙입니다.
- **`Week` 한도**: 사용률 bar와 %, 리셋까지 남은 시간(일/시간 단위).
- **`✦` 컨텍스트**: 모델명(effort 단계가 있으면 괄호로 덧붙임), bar, %, 토큰 수. 토큰 수는 캐시를 포함한 입력 토큰 기준이라 Claude Code의 `used_percentage`와 같은 값입니다. 50%와 80%에서 색이 바뀌고 90%를 넘으면 `!`를 붙입니다. 1M 이상은 `1.2M`처럼 줄여 씁니다.
- **`⚡` 캐시**: 프롬프트 캐시 상태(`warm` / `cold`)와 적중률. Claude Code가 값을 보내는 세션에서만 나타납니다.
- **`@` 계정**: 개인 계정은 `@ 이름`, 팀 계정은 `@ 이름 (조직명)`. 계정을 여러 개 오갈 때 지금 어느 계정인지 바로 알 수 있습니다.
- **`$` 비용**: 세션 누적 비용. $2와 $5에서 색이 바뀌고 $5를 넘으면 `!`를 붙입니다.
- **`Spend` 한도**: 사용률 bar와 %, 사용 금액/한도 금액, 리셋까지 남은 시간. 지출 한도가 설정된 계정에서만 나타납니다(Claude Code 2.1.251 이상, 금액은 2.1.284 이상).
- **cwd, `⎇` git**: 현재 디렉터리, 브랜치, 변경 사항 유무. worktree 안이면 `⌥`와 이름을 붙이고(24자를 넘으면 `…`로 줄임), 열린 PR이 있으면 `#12 approved` 같은 배지를 붙입니다(GitLab MR은 `!12`). vim 모드는 Claude Code가 기본으로 그리는 `-- INSERT --`에 맡기고 따로 표시하지 않습니다.

## 설치

### Claude Code에 붙여 넣기

설치를 Claude Code에 맡기려면 아래 문단을 그대로 붙여 넣으세요.

```text
https://github.com/seungho-jeong/claude-code-statusline 를 내 환경에 설치해 줘.
README의 설치 절을 읽고, 내 OS에 맞는 설치 스크립트를 실행하고, Node 18 이상이 없으면
먼저 설치해 줘. 끝나면 ~/.claude/settings.json의 statusLine 항목을 보여 주고, 임시로
받은 파일은 지우고, Claude Code를 재시작하라고 알려 줘.
```

### 요구 사항

Node 18 이상이 PATH에 있어야 합니다. macOS는 `brew install node`, Windows는 `winget install OpenJS.NodeJS.LTS`, 그 외에는 [nodejs.org](https://nodejs.org)에서 받으면 됩니다. Node가 없거나 버전이 낮으면 설치 스크립트가 오류를 내고 멈춥니다.

Windows는 Windows 10 1809 이상에서 **Windows Terminal** + Git for Windows 조합을 지원합니다. Windows PowerShell 창이나 `cmd.exe` 같은 기존 콘솔(conhost)은 색은 입히지만 글꼴 폴백이 없어서 `⎇ ✦ ▰▱` 같은 글리프가 네모로 나오고, `·`와 `⚡`의 폭을 잘못 계산해 뒤 숫자가 겹쳐 보입니다. Claude Code 자체 아이콘도 마찬가지입니다. Windows 10에는 Windows Terminal이 기본으로 들어 있지 않으니 `winget install Microsoft.WindowsTerminal`로 설치하고 그 안에서 Claude Code를 실행하세요.

런타임은 `statusline.js` 하나입니다. 어느 플랫폼에서나 같은 파일이 돌고, npm 패키지는 쓰지 않습니다.

설치 스크립트는 `~/.claude/statusline.{sh,js}`와 `~/.claude/settings.json`이 이미 있으면 먼저 `*.bak.<YYYYMMDD-HHMMSS>`로 백업하고, 끝날 때 백업 경로를 알려 줍니다.

### macOS / Linux / WSL2

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh
```

### Windows (PowerShell 5.1+)

```powershell
iwr -useb https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.ps1 | iex
```

### 직접 설치

`statusline.js`를 `~/.claude/statusline.js`(Windows는 `%USERPROFILE%\.claude\statusline.js`)에 두고 `~/.claude/settings.json`에 다음을 추가합니다.

```json
{
  "statusLine": {
    "type": "command",
    "command": "node ~/.claude/statusline.js",
    "padding": 0,
    "refreshInterval": 30
  }
}
```

`refreshInterval`을 30으로 두면 메시지를 보내지 않는 동안에도 30초마다 다시 그려서 `5h` 남은 시간이 계속 줄어듭니다.

Windows에서는 `command`를 `node %USERPROFILE%\\.claude\\statusline.js`로 바꿉니다.

### sh에서 js로 옮기기

처음 MVP로 만들었던 shell 런타임 `statusline.sh`는 v0.2.0까지 들어 있었고 v0.3.0에서 뺐습니다. `--runner sh`로 설치했다면 설치 스크립트를 한 번 더 실행하세요.

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh
```

스크립트가 `~/.claude/statusline.sh`를 백업하고 `statusLine.command`를 Node 런타임으로 바꿉니다. 옛 파일은 지우지 않습니다.

## 설정

임계값은 모두 `CCSL_*` 환경변수로 바꿀 수 있습니다.

| 변수 | 기본값 | 의미 |
|---|---|---|
| `CCSL_BAR_WIDTH` | `10` (`COLUMNS` < 100이면 `5`) | bar 칸 수. 따로 지정하지 않으면 좁은 터미널에서 자동으로 줄어듭니다 |
| `CCSL_CTX_WARN` | `50` | 컨텍스트 %가 노란색으로 바뀌는 기준 |
| `CCSL_CTX_CRIT` | `80` | 컨텍스트 %가 빨간색으로 바뀌는 기준 |
| `CCSL_FIRE_THRESHOLD` | `90` | 컨텍스트에 `!`를 붙이는 기준 |
| `CCSL_LIMIT_WARN_MIN` | `15` | 5시간 리셋에 `!`를 붙이는 기준(분) |
| `CCSL_COST_WARN` | `2.0` | 비용이 노란색으로 바뀌는 기준($) |
| `CCSL_COST_CRIT` | `5.0` | 비용이 빨간색으로 바뀌는 기준($) |
| `CCSL_GIT_TIMEOUT` | `1` | git 호출을 기다리는 최대 시간(초) |

예: `CCSL_CTX_WARN=30 claude`

## 동작 방식

- **계정 정보**는 `~/.claude.json`의 `oauthAccount`에서 바로 읽습니다. CLI를 호출하지 않으므로 세션을 여러 개 띄워도 값이 흔들리지 않습니다. 개인/팀 구분은 파일에 `organizationType`과 `seatTier`가 있으면 그 값으로 하고(Claude Code 2.1.x), 없는 옛 파일에서는 자동 생성된 조직명 패턴으로 합니다.
- **부담이 작습니다.** 입력은 `JSON.parse`로 처리하고 외부 프로세스는 `git` 하나만 띄웁니다. git 결과는 디렉터리별로 5초 동안 캐시하므로 30초 갱신마다 `git` 실행은 한 번뿐입니다.
- **빠진 정보가 있어도 됩니다.** `rate_limits`, `~/.claude.json`, `git` 중 무엇이 없든 그 부분만 비우고 나머지는 그대로 그립니다.

## 테스트

```sh
./tests/run.sh                          # 스냅샷 비교 (plain)
./tests/run.sh --mode ansi              # ANSI 색상까지 포함해 비교
./tests/run.sh --update                 # 스냅샷 다시 생성
./tests/perf.sh                         # 콜드 스타트 평균 80ms 미만인지 확인
./tests/integration-no-git.sh           # git이 없을 때
./tests/integration-no-home.sh          # HOME이 없거나 비어 있을 때
./tests/integration-install-backup.sh   # install.sh가 기존 파일을 백업하는지
./tests/integration-install-settings.sh # install.sh가 statusLine 항목을 쓰는지 (신규 + 병합)
./tests/integration-worktree.sh         # ⌥ worktree 이름 줄이기
./tests/integration-pr-badge.sh         # 2번째 줄 PR / MR 배지
./tests/integration-narrow.sh           # COLUMNS에 따른 bar 폭, CCSL_BAR_WIDTH 우선
./tests/integration-tenancy.sh          # @ 개인/팀 구분 (organizationType + seatTier)
```

테스트는 임시 디렉터리에서 격리해 실행하므로 사용 중인 git / HOME / 캐시를 건드리지 않습니다.

## 의존성

- **statusline.js**: Node 18 이상. npm 패키지 없음. `git`은 없어도 되며, 없으면 2번째 줄에 `(no git repo)`가 나옵니다.
- **install.sh / install.ps1**: `curl`(Windows는 `Invoke-WebRequest`). `jq`는 없어도 되지만, 없으면 settings.json을 자동으로 고치지 않습니다.

## 라이선스

MIT. [LICENSE](LICENSE)를 보세요.
