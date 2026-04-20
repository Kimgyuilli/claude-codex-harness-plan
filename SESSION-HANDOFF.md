# Session Handoff — Claude × Codex Harness 구현

> **마지막 세션**: 2026-04-20 (Phase 4 진입 직전 — A안 + 2단 분할 확정)
> **다음 세션 진입 시 이 문서부터 읽을 것.**

## 현재 위치

- **설계 문서**: `harness-plan.md` Draft v10 (Phase 0 검증 반영)
- **관리 문서**: `PHASES.md`, `TASKS.md` (Phase 4 → 4a/4b 분할 반영 완료)
- **완료**: Phase -1 B1, Phase 0 (0a/0b/0c), Draft v10, Phase 1 `/plan` 프로토타입, Phase 2 `/work` 프로토타입, **Phase 3 `/ship` scaffold (dry-run smoke PASS)**
- **다음**: **Phase 4a — A안** (`task-work-smoke` roll-forward 로 `/ship --execute` 실증). Phase 4b 는 별도 세션에서 실 task 로 KPI 측정.
- **병행 대기**: Phase -1 B2~B4 (사용자 PeakCart 수동 측정 — Phase 4b 진입 **전** 수행 권장)

## 현재 문제 요약

다음 4건이 현재 세션 기준 핵심 이슈다.

1. **문서 정합성**
- B1 완료 여부, Phase 3 상태, Open Questions 체크 상태가 문서마다 어긋났었음
- 이번 정리 기준: B1 완료, Phase 3 은 "구현 완료 + execute 검증 대기", 현재 포커스는 Phase 4a

2. **베이스라인 공백**
- B2~B4 미측정
- 따라서 KPI 해석은 아직 잠정적임

3. **실행 전 기술 리스크**
- `hpx_base_branch_discover` override 우선순위 문제
- `git add -N` intent-to-add 가 `/ship` commit 흐름과 충돌할 가능성

4. **Phase 4a 사후 정리 준비**
- smoke PR close
- revert commit 2개
- archive 보존
- cleanup script 점검 필요

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
   - 주의: 이는 working tree 에 intent-to-add 엔트리를 남김. /ship Step 4 의 `git add <files>` 와 충돌하지 않는지 **Phase 4a execute 경로에서 실증 필요**

### 3 pending decisions 재확인 (v9 default 유지)
1. timeout provider: Python wrapper ✓ — 180s 기본 (§7-1 권장)
2. attempts 상한: plan=3, work=3, cycle_total=5 ✓
3. risk threshold: diff_lines≥800, split_review, auth/security/payment/config/infra touch ✓

## Phase 3 실행 결과 (2026-04-20)

### 산출물 (PeakCart `experiment/harness-prototype` 브랜치)
- `cda4f3d` feat(harness): Phase 3 /ship scaffold + helpers

### 파일
- `.claude/commands/ship.md` — 11-step `/ship` (§6-3-3). `--dry-run` default / `--execute` opt-in
- `.claude/scripts/shared-logic.sh` 확장:
  - `hpx_consistency_precheck` — `ok` / `warnings` / `unavailable` / `script_error` 4분기
  - `hpx_commit_plan_group` — diff → {adr, docs, test, chore, src} TSV
  - `hpx_ship_pr_body_data` — PR 본문 데이터 번들 (commits/accepted/p0_ignores/ADR mentions)
  - `hpx_base_branch_name` — 표시/gh --base 전용 (discover 는 merge-base SHA 유지)
- `.gitignore` — `docs/plans/.archive/` 추가 (Step 10 state archive)

### 오픈 질문 3건 처리 결과
1. **push/gh pr create dry-run 분리**: `--execute` 플래그로 opt-in. 기본 dry-run 에서는 Steps 1–2 실행 + Steps 3/5 미리보기만 생성, state 미갱신, 부작용 없음
2. **`/done` 헬퍼 추출 범위**: **bash 헬퍼로 추출하지 않음**. 기존 `/done` (PeakCart `.claude/commands/done.md`) 이 ADR 분류/Layer 1 영향 판단 등 Claude 판단 영역이 많아 기계적 헬퍼로 분리 부적합. ship.md Step 9 를 Claude-led inline 으로 유지
3. **consistency-hints.sh 부재 폴백**: 확인 결과 PeakCart 에 존재. 그럼에도 `unavailable` 분기는 helper 에 포함 (스크립트 삭제/권한 문제 대비). 사용자 프롬프트 없이 skip + audit 기록

### dry-run smoke 검증 (task-work-smoke fixture)
- Step 1 state.branch ↔ HEAD match OK (`experiment/harness-prototype`)
- Step 2 precheck → `ok` (warnings 0, auto-pass)
- Step 3 grouping → 2 partitions (`src: HarnessSmokeTtl.java` / `test: HarnessSmokeTtlTest.java`)
- Step 5 PR body data → accepted 3건 (P1×3), ADR-0001 언급, commits 3개 (branch-ahead-of-main)
- 모든 헬퍼 bash -n syntax PASS

### 미검증 (Phase 4 E2E 이관)
- execute-mode 실제 실행 (Steps 4/7/8/9/10)
- 재진입 매트릭스 각 stage 실전 재개
- §7-5-C push 실패 ladder / §7-5-D PR 실패 ladder 실측
- Step 9 `/done` 의 ADR 분류 판단 경로
- state archive + lock 해제 순서

## Phase 4 진입 계획 — 2단 분할 (2026-04-20 확정, A안)

### 결정 요약

- **A안 채택** (`task-work-smoke` roll-forward). C안 (신규 가짜 task 생성) 은 pay-off 낮아 기각.
- **Phase 4 → Phase 4a + 4b 분할**. 가짜 task 로 KPI 왜곡되는 한계를 분할로 해소.
- B2 수동 베이스라인은 Phase 4b **전** 사전 수행 (사용자 합의).
- 첫 `git push -u origin experiment/harness-prototype` 가 Phase 4a 에서 발생 — 누적 4개 기존 커밋(`0fd29b7 / 98c2b4c / e0de2a0 / cda4f3d`) + 2개 신규 (smoke src/test) 가 origin 에 공개됨 (사용자 합의).

### Phase 4a 목표 (execute mechanics 실증)

Step 범위: 4 (commit) / 7 (push) / 8 (PR) / 9 (/done) / 10 (archive) + 재진입 1건 + §7-5-C/D ladder 1건.

Phase 3 dry-run 에서 이미 검증된 Steps 1 / 2 / 3 / 5 는 자연 재실행. TASKS.md Phase 4a 체크리스트 (P4a-1 ~ P4a-15) 참조.

### Phase 4a 재진입 시나리오 (의도적 주입)

1. **기본 full path**: Step 1 → 10 순차 완주
2. **재진입 주입**: Step 7 (push 성공) 직후 프로세스 중단 시뮬레이션 (lock 수동 삭제) → `/ship --execute` 재호출 → 재진입 매트릭스 `ship.pushed` 행에 따라 Step 8 부터 재개 (PR 선조회 → 없음 → 생성)
3. **ladder 주입**: Step 7 에서 origin URL 일시 오기입 (e.g., `git remote set-url origin bogus` → push 실패 → `push_status=failed` + cursor=`push.failed` 기록 확인 → origin 복원 → 재호출 → 재시도 성공 → 정상 경로)

### Phase 4a 사후 정리 (smoke 는 실 머지 금지)

- 테스트 PR 은 **머지 금지** — `gh pr close <pr>` 로 close
- origin 의 smoke commits 2개는 **revert commit 2개** 로 원복 (`git revert <sha>` × 2, `experiment/harness-prototype` 위에 쌓기)
- archive 는 보존 (`docs/plans/.archive/task-work-smoke.state.<ts>.json`) — 감사 증거
- `HarnessSmokeTtl.java` / `HarnessSmokeTtlTest.java` 는 revert 로 파일 삭제 상태
- 정리 스크립트 초안: `scripts/cleanup-smoke-pr.sh` (Phase 4a 진입 전 작성, 실행은 Phase 4a 완료 후)

### Phase 4b 진입 조건

- Phase 4a P4a-1 ~ P4a-15 전부 ✅
- B2 수동 베이스라인 측정 완료 (사용자 수행)
- 실 task 선정 (현재 후보: P1-E PromQL NaN 가드 / 정상 경로 / diff < 500 / ADR 영향 없음)

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
- `cda4f3d` feat(harness): Phase 3 /ship scaffold + helpers (dry-run smoke PASS)

## 새 세션 진입 체크리스트

1. `cat SESSION-HANDOFF.md` (이 문서)
2. `cat PHASES.md TASKS.md` — Phase 4a/4b 체크 상태 확인
3. PeakCart 브랜치 확인: `cd ~/dev/projects/PeakCart && git branch --show-current` → `experiment/harness-prototype`
4. smoke fixture 잔존물 확인: `ls docs/plans/task-*-smoke*` + `docs/plans/.archive/` 확인
5. harness-plan §6-3-3 재진입 매트릭스 + §7-5-C/D ladder 재숙지
6. Phase 4a 정리 스크립트 (`scripts/cleanup-smoke-pr.sh`) 존재 여부 + 실행 권한

## 현재 task (세션 내 생성, 새 세션에서 재생성)

- ✅ #1 Phase -1 B1: 베이스라인 측정 스키마 정의
- ⏸ #2 Phase -1 B2~B4: 실제 task 3개 측정 (Phase 4b 전 사전 수행 예정)
- ⏸ #3 Phase -1 B5: 3개 샘플 집계 (#2 blocked)
- ✅ #4 Phase 0a: 슬래시 커맨드 실행 모델 검증 (판정 B)
- ✅ #5 Phase 0b: Codex CLI 명세 확정 (100% JSON 성공률)
- ✅ #6 Phase 0c: macOS/gh/git 환경 확인
- ✅ #7 Phase 1: `/plan` 프로토타입 + smoke 검증 (5/5 결함 검출)
- ✅ #8 Phase 2: `/work` 프로토타입 + smoke 검증 (4/4 결함 검출) + split 헬퍼 검증
- ✅ #9 Phase 3: `/ship` scaffold + dry-run smoke (헬퍼 3건 live 검증)
- ▶ #10 Phase 4a: A안 — `task-work-smoke` roll-forward 로 `/ship --execute` 실증 (재진입 1건 + ladder 1건)
- ⏭ #11 Phase 4b: 실 task 1건 (P1-E 후보) + B2 수동 베이스라인 병행 + KPI 전수 측정

## 다음 세션에서 바로 확인할 것

- `PHASES.md`, `TASKS.md` 가 이 handoff 와 같은 상태를 가리키는지 먼저 확인
- `scripts/cleanup-smoke-pr.sh` 존재 여부 확인
- Phase 4a 전에 smoke state / branch / archive 경로 확인
- 베이스라인 B2 착수 시점을 Phase 4b 이전으로 고정
