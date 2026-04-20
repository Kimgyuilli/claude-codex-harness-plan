# Session Handoff — Claude × Codex Harness 구현

> **마지막 세션**: 2026-04-20 (Phase 1 `/plan` 프로토타입 완료)
> **다음 세션 진입 시 이 문서부터 읽을 것.**

## 현재 위치

- **설계 문서**: `harness-plan.md` Draft v10 (Phase 0 검증 반영)
- **관리 문서**: `PHASES.md`, `TASKS.md`
- **완료**: Phase -1 B1, Phase 0 (0a/0b/0c), Draft v10 정정, **Phase 1 `/plan` 프로토타입**
- **다음**: Phase 2 `/work` 구현 (diff 캡처 / diff-split / work stage 전이)
- **병행 대기**: Phase -1 B2~B4 (사용자 PeakCart 수동 측정)

## Phase 1 실행 결과 (2026-04-20)

### 산출물 (PeakCart `experiment/harness-prototype` 브랜치, commit `0fd29b7`)
- `.claude/commands/plan.md` — 12-step /plan 절차 (§6-3-1)
- `.claude/scripts/shared-logic.sh` — `hpx_*` 공용 함수 (lock/state/run_id/metrics/tokens)
- `.claude/schemas/plan-review.json`, `diff-review.json` — Structured Outputs 스키마
- `scripts/timeout_wrapper.py` — macOS GNU timeout 부재 대응
- `docs/plans/task-harness-smoke.md` — 의도적 결함 fixture
- `docs/plans/.audit/task-harness-smoke.md` — GP-2 감사 로그 (영구, git-tracked)
- `.gitignore` — `*.state.json`, `*.lock/`, `.cache/` 제외

### Smoke 검증 (task-harness-smoke)
- 의도적 결함 **5/5 검출** (P1×3 + P2×2)
- `run_id` 왕복 무결성 OK (예약 → 프롬프트 주입 → 응답 → state append 일치)
- state.json 원자 write (`tmp` + `os.replace`) OK
- lock 획득/해제 (mkdir atomicity) OK, 세션 재진입 경로 검증
- audit log + `_metrics.tsv` + `gate-events.tsv` 기록 OK
- stage 전이: `plan.draft.created` → `plan.review.completed` → `plan.done`

### 새로 발견된 제약 (Phase 2 진입 전 반영 필요)
- **Codex wall clock 78s / tokens 39,865** — Phase 0b 단순 baseline 9s 대비 8~9배
  - 원인: ADR-grounded 리뷰는 docs/adr/*, docs/01~07 다수 파일 탐색 필요
  - 조치: **timeout 기본값 60s → 90~180s 권상** (harness-plan §7-1/7-2 후속 반영)
  - 이번 세션 1차 60s 호출 exit 124 → 180s 재시도 성공 기록 있음
- **Bash 도구 zsh/bash 차이** — `set -euo pipefail` + `source` 조합에서 이상 동작
  - 조치: 모든 shared-logic.sh 호출은 `bash -c '...'` 서브셸로 감싸기 (plan.md 규칙화 완료)
- **다단계 실행 패턴** — 인라인 heredoc 복잡도 높으면 `/tmp/plan-*.sh` 로 분리

### 3 pending decisions 확정 (이번 세션 중)
1. **timeout provider**: Python wrapper 유지 (v9 default)
2. **attempts 상한**: plan=3, work=3, cycle_total=5 (v9 default)
3. **risk threshold**: diff_lines≥800, split_review, auth/security/payment/config/infra touch (v9 default)

## Phase 0 핵심 발견 (이미 Draft v10 반영, 참조용 유지)

1. `codex exec --output-schema <FILE>` 네이티브 강제 지원, `additionalProperties: false` 필수
2. nested slash 호출 불가 → `.claude/scripts/shared-logic.sh` 패턴
3. macOS `timeout`/`gtimeout` 부재 → Python wrapper
4. stderr `tokens used\n<숫자>` 2줄 포맷
5. Codex 인증: ChatGPT 로그인 (`~/.codex/auth.json`)

## Phase 2 진입 계획 (`/work` 구현)

**격리**: 동일 브랜치 `experiment/harness-prototype`, smoke fixture 재사용

**예상 순서**:
1. `.claude/commands/work.md` 작성 — harness-plan §6-3-2 기반
2. diff 캡처 로직 (§7-2) — `git diff` → `.cache/diffs/<task>-<ts>.patch`
3. diff-split (§7-4) — large diff 자동 청크
4. shared-logic.sh 확장:
   - `hpx_diff_capture <task_id>`
   - `hpx_diff_split <patch_path> <threshold>`
   - `hpx_commit_plan_build <task_id>` (§6-6 commit plan)
5. state stage 전이: `work.impl.inprogress` → `work.impl.completed` → `work.review.completed` → `work.done`
6. `degraded_accepted` 경로 (risk threshold 발동) 검증
7. smoke fixture 를 의도적 결함 수정 → /work 로 재리뷰 → accepted/rejected 사이클 검증
8. work 완료 후 commit plan 실행 여부 결정

**Phase 2 착수 전 오픈 질문**:
- commit plan 실행을 /work 안에 포함할지, 별도 /ship (Phase 3) 로 분리할지
- diff-split 청크별 리뷰 결과 merge 전략 (`items[].id` 재번호 vs 청크 prefix)

## 베이스라인 측정 (B2~B4) 제안 (Phase 1 과 병행 가능)

| # | Task | 구분 |
|---|------|------|
| A | P1-E PromQL NaN 가드 | normal |
| B | P1-F 대시보드 SSOT | normal |
| C | P0-A Outbox Slack 격리 | high-risk |

엄격 측정, 템플릿 = `baseline/template.md`.

## 커밋 이력

### playground/temp
- `f1f2bca` docs: add Phase/Task management for harness implementation
- `0372d49` feat: complete Phase -1 B1 + Phase 0 (0a/0b/0c)
- `2150d5e` docs: add SESSION-HANDOFF for next session pickup
- `587d285` docs: harness-plan Draft v10 — Phase 0 검증 결과 반영
- `5ab0287` docs: update SESSION-HANDOFF for Draft v10 completion + Phase 1 path
- (다음 예정) docs: SESSION-HANDOFF — Phase 1 완료, Phase 2 진입 준비

### PeakCart (`experiment/harness-prototype`)
- `0fd29b7` feat(harness): Phase 1 /plan prototype — in-command state machine + Codex review

## 새 세션 진입 체크리스트

1. `cat SESSION-HANDOFF.md` (이 문서)
2. `cat PHASES.md TASKS.md` — Phase 2 task 분해 확인/갱신
3. PeakCart 브랜치 확인: `cd ~/dev/projects/PeakCart && git branch --show-current` → `experiment/harness-prototype`
4. smoke fixture 잔존물 확인: `ls docs/plans/task-harness-smoke*`
5. Phase 2 착수 전 오픈 질문 2건 사용자와 합의
6. harness-plan §6-3-2, §7-2, §7-4, §6-6 선독

## 현재 task (세션 내 생성, 새 세션에서 재생성)

- ✅ #1 Phase -1 B1: 베이스라인 측정 스키마 정의
- ⏸ #2 Phase -1 B2~B4: 실제 task 3개 측정 (사용자 참여 대기)
- ⏸ #3 Phase -1 B5: 3개 샘플 집계 (#2 blocked)
- ✅ #4 Phase 0a: 슬래시 커맨드 실행 모델 검증 (판정 B)
- ✅ #5 Phase 0b: Codex CLI 명세 확정 (100% JSON 성공률)
- ✅ #6 Phase 0c: macOS/gh/git 환경 확인
- ✅ #7 Phase 1: `/plan` 프로토타입 + smoke 검증 (5/5 결함 검출)
- ⏭ #8 Phase 2: `/work` 구현 (다음 세션)
