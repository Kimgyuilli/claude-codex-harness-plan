# Phase 0c: macOS / gh / git 환경 검증 결과

> **실행일**: 2026-04-19
> **참조**: `harness-plan.md` §2-2, §13 Phase 0c

## 통과 판정 ✅

timeout provider 확보 + gh 인증 + git remote/권한 정상. Phase 1 진행 가능.

---

## 1. Hard timeout provider (필수 계약)

### 발견
| provider | 상태 |
|----------|------|
| `timeout` (GNU coreutils) | ❌ NOT FOUND |
| `gtimeout` (Homebrew coreutils) | ❌ NOT FOUND |
| `python3` | ✅ 사용 가능 |

### 해결: Python wrapper 작성
- **경로**: `scripts/timeout_wrapper.py` (playground 에 작성, Phase 1 에 PeakCart `scripts/timeout_wrapper.py` 로 복사)
- **동작 검증** (3 시나리오 전부 통과):
  1. 정상 종료: exit=0
  2. SIGTERM 처리 가능한 프로세스: exit=124 (grace 내 종료)
  3. SIGTERM 무시 프로세스: exit=124 (2s 후 SIGKILL)
- **특징**:
  - `start_new_session=True` + `killpg` → 자식 프로세스 트리 전체 종료
  - GNU timeout 과 동일한 exit code 124 사용
  - 외부 의존성 없음 (Python 표준 라이브러리만)

### Phase 0c timeout provider 계약
harness-plan.md §2-2 패턴 그대로 유효:
```bash
if command -v timeout >/dev/null; then T="timeout 60"
elif command -v gtimeout >/dev/null; then T="gtimeout 60"
else T="python3 scripts/timeout_wrapper.py 60"
fi
```
→ 현재 환경은 **세 번째 분기** 로 동작. 향후 `brew install coreutils` 하면 자동으로 `gtimeout` 분기로 전환.

### 사용자 선택 (열려 있음)
- 옵션 1: **Python wrapper 그대로 사용** (추천 — 이식성)
- 옵션 2: `brew install coreutils` → `gtimeout` 사용 (추가 의존성, 다만 표준 도구)

## 2. gh CLI

| 항목 | 값 |
|------|-----|
| `gh --version` | 2.88.1 (2026-03-12) ✅ |
| 인증 | `Kimgyuilli` (keyring) ✅ |
| protocol | https |
| token scopes | `gist`, `read:org`, `repo`, `workflow` ✅ |

`/ship` 에서 사용하는 기능 요구사항 충족:
- `gh pr list --head <branch>` (PR 선조회)
- `gh pr create --body-file <file>` (PR 생성)
- 필요 scope `repo` 보유

## 3. git 환경 (PeakCart)

| 항목 | 값 |
|------|-----|
| origin | `https://github.com/Kimgyuilli/PeakCart.git` ✅ |
| current branch | `main` |
| origin/HEAD | `origin/main` ✅ (stale 아님) |

base branch discovery 4단 폴백의 1단계 (`origin/HEAD`) 정상 동작.

---

## 4. 적용 필요 (Phase 1 착수 시 PeakCart 로 전파)

### 4-1. `scripts/timeout_wrapper.py` 복사
- **from**: `/Users/kimgyuill/dev/playground/temp/scripts/timeout_wrapper.py`
- **to**: `/Users/kimgyuill/dev/projects/PeakCart/scripts/timeout_wrapper.py`
- chmod +x

### 4-2. `.gitignore` 갱신 (PeakCart)
```
docs/plans/*.state.json
docs/plans/*.lock/
.cache/
```

### 4-3. state atomic write 규약 (Phase 1 구현 시)
```bash
STATE="docs/plans/${TASK_ID}.state.json"
TMP="${STATE}.tmp.$$"
render_state_json > "$TMP" && mv "$TMP" "$STATE"
```
→ Phase 1 에서 `.claude/commands/plan.md` 작성 시 포함.

---

## 5. 루프 예산 / 위험 임계값 확정

### 5-1. 루프 예산 (v9 default 채택)
| 변수 | 값 | 근거 |
|------|-----|------|
| `attempts_by_command.plan` | `3` | v9 default, 대화 피로 vs 품질 균형 |
| `attempts_by_command.work` | `3` | v9 default |
| `codex_attempts_cycle_total` | `5` | plan 1 + work split 최대 3 + 재시도 여유 1 |

→ Phase -1 베이스라인 집계 후 재조정 가능 (soft cap).

### 5-2. degraded risk threshold (v9 default 채택)
```
risk_level = "high" if (
    diff_lines >= 800
    or split_review == true
    or touched_path ~= /auth|security|payment|config|infra/
) else "low"

# /plan 추가 조건
if command == "plan" and adr_boundary_change:
    risk_level = "high"
```

→ PeakCart 기존 디렉토리 매핑:
- `auth` → `src/main/java/com/peekcart/user/`, `global/jwt/`, `global/config/SecurityConfig.java`
- `security` → `global/config/SecurityConfig.java`, 위 + `WebhookService` HMAC
- `payment` → `src/main/java/com/peekcart/payment/`
- `config` → `src/main/resources/application*.yml`, `global/config/`
- `infra` → `k8s/`, `docker-compose.yml`, `Dockerfile`, `build.gradle`, `.github/workflows/`

→ Phase 1 구현 시 정규식 패턴을 `.claude/scripts/shared-logic.sh` 또는 커맨드 내부에 고정.

---

## Phase 0c 완료 확인

- [x] hard timeout provider 확보 (`python3 scripts/timeout_wrapper.py`)
- [x] `gh --version` / `gh auth status` 통과
- [x] PeakCart origin remote + push 권한 확인
- [x] `.gitignore` 적용 항목 목록 확정
- [x] state atomic write 규약 문서화
- [x] 루프 예산 숫자 확정 (v9 default)
- [x] degraded risk threshold 확정 (v9 default)

## 다음 단계

**Phase 0 전체 완료**. Phase 1 (`/plan` 구현) 진행 가능. 단, Phase -1 베이스라인 수집 (B2~B4) 은 여전히 사용자 참여 대기 — Phase 1 과 병행 가능.
