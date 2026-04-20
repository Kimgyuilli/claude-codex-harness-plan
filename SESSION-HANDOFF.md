# Session Handoff — Claude × Codex Harness 구현

> **마지막 세션**: 2026-04-20 (Phase 2 `/work` 프로토타입 완료)
> **다음 세션 진입 시 이 문서부터 읽을 것.**

## 현재 위치

- **설계 문서**: `harness-plan.md` Draft v10 (Phase 0 검증 반영)
- **관리 문서**: `PHASES.md`, `TASKS.md`
- **완료**: Phase -1 B1, Phase 0 (0a/0b/0c), Draft v10, **Phase 1 `/plan` 프로토타입**, **Phase 2 `/work` 프로토타입**
- **다음**: Phase 3 `/ship` 구현 (commit plan / push / PR 생성 / done 로직 통합)
- **병행 대기**: Phase -1 B2~B4 (사용자 PeakCart 수동 측정)

## Phase 2 실행 결과 (2026-04-20)

### 산출물 (PeakCart `experiment/harness-prototype` 브랜치)
- `98c2b4c` feat(harness): Phase 2 /work scaffold + smoke fixture plan
- `e0de2a0` feat(harness): Phase 2 /work smoke — Codex 4/4 결함 검출 + 수정 반영

### 파일
- `.claude/commands/work.md` — 12-step `/work` 절차 (§6-3-2)
- `.claude/scripts/shared-logic.sh` 확장:
  - `hpx_base_branch_discover` — origin/HEAD → git config → env → main
  - `hpx_diff_capture` — `git add -N` + `git diff BASE` → `.cache/diffs/*.patch`
  - `hpx_diff_lines`, `hpx_diff_files`
  - `hpx_risk_classify` — diff_large_800 / auth_touch / payment_touch / config_infra_touch
  - `hpx_diff_split` — 우선순위(exec > test > docs/config) + 균등 line 분배 3-chunk
- `docs/plans/task-work-smoke.md` — /work 전용 smoke 계획
- `src/main/java/com/peekcart/global/cache/HarnessSmokeTtl.java` — TTL 유틸 (수정 적용됨)
- `src/test/java/com/peekcart/global/cache/HarnessSmokeTtlTest.java` — 3 case 확장
- `docs/plans/.audit/task-work-smoke.md` — GW-2 결정 감사 로그

### Smoke 검증 (task-work-smoke, single-review)
- 의도적 결함 **4/4 검출** (P1×3 + P2×1)
  - D1 (P1 bug): null 가드 누락 → `Objects.requireNonNull` 적용
  - D2 (P1 convention): `System.out` → `@Slf4j log.info`
  - D3 (P1 test): zero-TTL + null 케이스 누락 → 3 test 추가
  - D4 (P2 convention): 미사용 import — 사용자 deferred (smoke 증거물)
- `run_id` 왕복 match (`work:20260420T102603Z:<sid>:1`)
- JSON Schema 구조 검증 OK (`--output-schema` + additionalProperties 준수)
- stage 전이: `plan.done` → `work.impl.inprogress` → `work.impl.completed` → `work.review.completed` → `work.done`
- attempts: plan=1, work=1; cycle_total=2
- Codex wall ~3분, tokens=17,997 (Phase 1 대비 절반 — diff 작고 ADR 탐색 제한적)
- audit log + `_metrics.tsv` + `gate-events.tsv` 기록 OK

### Split 헬퍼 검증 (synthetic 1230-line patch, live Codex 호출은 생략)
- 5 파일 (exec ×2, test ×1, docs ×1, config ×1) → 3 chunk (406/462/362 lines)
- risk_classify: **high** (`diff_large_800, split_review_candidate, payment_touch`)
- 우선순위 boundaries: c1=OrderService.java, c2=PaymentService+OrderServiceTest, c3=ADR+build.gradle

### 새로 발견된 제약 / 개선 필요

1. **`hpx_base_branch_discover` 우선순위 정정 검토**:
   - 현재: `origin/HEAD` > `git config peakcart.baseBranch` > `PEAKCART_BASE_BRANCH` > `main`
   - 문제: `origin/HEAD` 가 존재하면 env/config override 가 무시됨. 실험 브랜치에 로컬 commit 쌓인 상태에서 base 오버라이드 불가
   - 권장: harness-plan §6-3-2 Step 4 에 "env 변수 최우선" 옵션 추가 검토 (또는 helper 에 `HPX_BASE_OVERRIDE` 파라미터 신설)
2. **`git diff` 는 untracked 미포함**:
   - 현재 해결: `hpx_diff_capture` 가 `git add -N` 를 자동 수행
   - 주의: 이는 working tree 에 intent-to-add 엔트리를 남김. /ship Step 4 의 `git add <files>` 와 충돌하지 않는지 Phase 3 검증 필요

### 3 pending decisions 재확인 (v9 default 유지)
1. timeout provider: Python wrapper ✓ — 180s 기본 (§7-1 권장)
2. attempts 상한: plan=3, work=3, cycle_total=5 ✓
3. risk threshold: diff_lines≥800, split_review, auth/security/payment/config/infra touch ✓

## Phase 3 진입 계획 (`/ship` 구현)

**격리**: 동일 브랜치 `experiment/harness-prototype`. 누적 smoke fixture 재사용 가능.

**예상 순서** (harness-plan §6-3-3 기반):
1. `.claude/commands/ship.md` 작성
2. `hpx_consistency_precheck` — `docs/consistency-hints.sh` wrap
3. `hpx_commit_plan_build` — 파일 그룹핑 + 예상 메시지 생성 (§10-3)
4. `hpx_ship_pr_body` — PR 본문 템플릿 (§10-2)
5. stage 전이: `work.done` → `ship.precheck` → `ship.partition.previewed` → `ship.commits.created` → `ship.pushed` → `ship.pr.created` → `ship.done`
6. 재진입 매트릭스 (§6-3-3 v4) 대로 각 단계 재개 검증
7. Push/PR 실패 ladder (§7-5-C/D) 실전 검증

**Phase 3 착수 전 오픈 질문**:
- smoke 가 local only 인 상태에서 push/gh pr create 를 실제로 돌릴지, dry-run 모드로 분리할지
- `/done` 로직 (TASKS.md / progress / ADR 갱신) 을 shared-logic.sh 로 추출하는 범위
- consistency-hints.sh 가 PeakCart 에 없을 때 폴백 (§7-5-E 실행 실패 분기)

## Phase 0/1 참조용 (변경 없음)

- Phase 0b: `codex exec --output-schema <FILE>` 네이티브 강제, `additionalProperties: false` 필수
- Phase 0a: nested slash 불가 → `shared-logic.sh` 패턴
- macOS timeout 부재 → Python wrapper (`scripts/timeout_wrapper.py`)
- Codex stderr `tokens used\n<숫자>` 2줄 포맷
- Codex 인증: ChatGPT 로그인 (`~/.codex/auth.json`)

## 베이스라인 측정 (B2~B4) 제안 (Phase 3 과 병행 가능)

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
- `8064166` docs: SESSION-HANDOFF — Phase 1 완료, Phase 2 진입 준비
- (다음 예정) docs: SESSION-HANDOFF — Phase 2 완료, Phase 3 진입 준비

### PeakCart (`experiment/harness-prototype`)
- `0fd29b7` feat(harness): Phase 1 /plan prototype
- `98c2b4c` feat(harness): Phase 2 /work scaffold + smoke fixture plan
- `e0de2a0` feat(harness): Phase 2 /work smoke — Codex 4/4 결함 검출 + 수정 반영

## 새 세션 진입 체크리스트

1. `cat SESSION-HANDOFF.md` (이 문서)
2. `cat PHASES.md TASKS.md` — Phase 3 task 분해 확인/갱신
3. PeakCart 브랜치 확인: `cd ~/dev/projects/PeakCart && git branch --show-current` → `experiment/harness-prototype`
4. smoke fixture 잔존물 확인: `ls docs/plans/task-*-smoke*`
5. Phase 3 착수 전 오픈 질문 3건 사용자와 합의
6. harness-plan §6-3-3, §7-5-C/D/E, §10-2, §10-3 선독

## 현재 task (세션 내 생성, 새 세션에서 재생성)

- ✅ #1 Phase -1 B1: 베이스라인 측정 스키마 정의
- ⏸ #2 Phase -1 B2~B4: 실제 task 3개 측정 (사용자 참여 대기)
- ⏸ #3 Phase -1 B5: 3개 샘플 집계 (#2 blocked)
- ✅ #4 Phase 0a: 슬래시 커맨드 실행 모델 검증 (판정 B)
- ✅ #5 Phase 0b: Codex CLI 명세 확정 (100% JSON 성공률)
- ✅ #6 Phase 0c: macOS/gh/git 환경 확인
- ✅ #7 Phase 1: `/plan` 프로토타입 + smoke 검증 (5/5 결함 검출)
- ✅ #8 Phase 2: `/work` 프로토타입 + smoke 검증 (4/4 결함 검출) + split 헬퍼 검증
- ⏭ #9 Phase 3: `/ship` 구현 (다음 세션)
