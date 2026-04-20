# Harness 구현 — Task 체크리스트

> **Source**: `harness-plan.md` Draft v9 §13
> **Phase 구조**: `PHASES.md` 참조
> **상태**: ☐ 대기 / ▶ 진행 / ✅ 완료 / ⛔ 차단 / 🔁 재작업

---

## Phase -1: 베이스라인 수집

- [x] **B1.** 측정 스키마 정의 (invocation / decision / cycle time / 수동 fallback / 수동 복붙)
- [ ] **B2.** 정상 경로 task 1 측정
- [ ] **B3.** 정상 경로 task 2 측정
- [ ] **B4.** high-risk 후보 task 1 측정
- [ ] **B5.** 3개 샘플 집계 → Phase 4 비교용 기준선 문서화

---

## Phase 0a: 슬래시 커맨드 실행 모델 검증 ✅ (판정 B)

결과: `phase0/0a-slash-command-model.md`. nested slash 만 불가, shared-logic.sh 로 우회.

- [x] **0a-1~5.** Q0-1~Q0-5 답변 확보 (claude-code-guide 에이전트 조사)
- [x] **0a-6.** 판정 **B** — 설계안 F 유지, Phase 1 에 `.claude/scripts/` 추가 작업 필요

---

## Phase 0b: Codex CLI 명세 확정 ✅

결과: `phase0/0b-codex-cli-spec.md`. JSON 강제 5/5 = 100%, 평균 9초.

- [x] **0b-1~6.** Q1~Q6 전부 확보
- [x] **0b-7.** `$CODEX_CMD="codex exec --cd $(pwd) --output-schema <FILE> --sandbox read-only"` 확정
- 핵심 발견: `--output-schema` **네이티브 JSON Schema 강제 지원** (프롬프트 지시문 불필요). 스키마에 `additionalProperties: false` 필수

---

## Phase 0c: macOS / gh / git 환경 확인 ✅

결과: `phase0/0c-environment.md`. `scripts/timeout_wrapper.py` 작성됨.

- [x] **0c-1.** hard timeout provider — Python wrapper (GNU timeout 미설치)
- [x] **0c-2~4.** `gh 2.88.1` 인증 완료, PeakCart origin/main 확인
- [x] **0c-5.** `.gitignore` 적용 항목 목록 확정 (Phase 1 에 PeakCart 로 전파)
- [x] **0c-6.** state atomic write 규약 문서화
- [x] **0c-7.** 루프 예산 v9 default 채택 (plan=3, work=3, cycle=5)
- [x] **0c-8.** degraded risk threshold v9 default 채택 + PeakCart 경로 매핑

---

## Phase 1: `/plan` 구현 ✅ (PeakCart `0fd29b7`, smoke 5/5 결함 검출)

- [x] **P1-1.** `docs/plans/.gitkeep` 생성 (PeakCart)
- [x] **P1-2.** `docs/plans/.audit/` 디렉토리 및 `.gitkeep` 생성
- [x] **P1-3.** §10-1 계획서 템플릿 확정 (stable id `P1.`, `P2.` 규약 포함)
- [x] **P1-4.** state.json 스키마 구현 (§6-4-2 전 필드, `review_runs[]`, `pending_run`, `session_id`)
- [x] **P1-5.** lock 디렉토리 획득/해제 로직 (§6-4-4 `mkdir` 원자성 + stale 수동 해제)
- [x] **P1-6.** audit log append 로직 (`docs/plans/.audit/<task-id>.md`)
- [x] **P1-7.** `gate-events.tsv` append 로직
- [x] **P1-8.** `.claude/commands/plan.md` 작성 — 처리 단계 12 step (§6-3-1)
- [x] **P1-9.** `$CODEX_CMD` 호출 (§7-1) — RUN_ID 주입 + JSON 스키마 강제
- [x] **P1-10.** 응답 파싱 + run_id 검증 + §7-5-A JSON fallback ladder
- [x] **P1-11.** GP-1 (conditional ADR), GP-2 (conditional P0/P1), GP-2b (degraded) 게이트 구현
- [x] **P1-12.** 루프 판정 (실제 수정 + 명시 재리뷰 + attempts < 3)
- [x] **P1-13.** 가짜 task 로 dry-run → stage 전이 + 산출물 정합 검증
- [x] **P1-14.** 중단 후 재개 (state 기반) 시뮬레이션

---

## Phase 2: `/work` 구현 ✅ (PeakCart `98c2b4c`, `e0de2a0`, smoke 4/4 결함 검출 + split 헬퍼 검증)

- [x] **P2-1.** `.claude/commands/work.md` 작성 — 처리 단계 12 step (§6-3-2)
- [x] **P2-2.** base branch discovery 4단 폴백 (§7-2) — `origin/HEAD` → `peakcart.baseBranch` → env → `main` (우선순위 정정 필요 — SESSION-HANDOFF 개선 항목 #1)
- [x] **P2-3.** `git diff $BASE` 로 working tree 변경 캡처 (F2 — `git add -N` 자동 수행으로 untracked 포함)
- [x] **P2-4.** GW-1 (always, 브랜치 명) 게이트 — 사용자 입력 후 state 에 branch 기록
- [x] **P2-5.** HEAD 과 `state.branch` 교차 검증 (불일치 시 자동 진행 금지)
- [x] **P2-6.** §7-4 diff 크기 분기 — 500/2000 줄 임계값, 최대 3 chunk split (synthetic 1230-line 검증 OK)
- [x] **P2-7.** `review_plan` + chunk 상태 추적 (§6-4-2 `chunks[]`)
- [x] **P2-8.** $CODEX_CMD 호출 (§7-2) — RUN_ID + chunk run_id 주입
- [x] **P2-9.** aggregate_result 승격 규칙 (`timeout` > `json_parse_failed` > `empty` > `error`)
- [x] **P2-10.** GW-2 / GW-2b 게이트 구현 (degraded 포함)
- [x] **P2-11.** §7-5-B timeout fallback ladder — 1회/2회/3회 단계별 행동
- [x] **P2-12.** high-risk degraded default 선택지 `중단/재시도` 적용
- [x] **P2-13.** stable id 기반 `completed_plan_items[]` 갱신 (§10-1)
- [x] **P2-14.** 작은 실제 task 로 dry-run + 재개 시뮬레이션 (task-work-smoke single-review)

---

## Phase 3: `/ship` 구현 ▶ (scaffold 완료 — PeakCart `cda4f3d`, dry-run smoke PASS. execute-mode smoke 는 Phase 4 E2E 로 이관)

판정: 구현 자체는 완료. 남은 것은 execute-mode 실전 검증이며, 이는 Phase 4a 체크리스트에서 관리.

- [x] **P3-1.** `.claude/commands/ship.md` 작성 — 처리 단계 11 step (§6-3-3). dry-run / --execute 플래그 분리
- [x] **P3-2.** `bash docs/consistency-hints.sh` 실행 + GS-1 conditional 게이트 (`hpx_consistency_precheck`)
- [x] **P3-3.** §7-5-E consistency 실행 실패 분기 — `status=script_error` 브랜치 + `unavailable` 은 skip
- [x] **P3-4.** §10-3 커밋 분할 제안 로직 (`hpx_commit_plan_group` TSV 출력 + ship.md §10-3 규약 Claude 판단)
- [x] **P3-5.** `commit_plan[]` 원자 저장 + GS-2 게이트 (always) — ship.md 에 구조 명시. execute-mode 실행은 Phase 4
- [x] **P3-6.** 파일 명시 커밋 (`git add -A` 금지) + sha 를 state 에 append + 재커밋 방지 교차 확인 — ship.md Step 4 문서화
- [x] **P3-7.** §10-2 PR 본문 생성 + `.cache/pr-body-<task-id>.md` 저장 (`hpx_ship_pr_body_data` 데이터 번들)
- [x] **P3-8.** P0 무시 사유 (audit log) PR 본문에 자동 포함 (Q19 default) — `p0_ignores[]` 파싱 반영
- [x] **P3-9.** GS-3 게이트 (always, PR 본문 미리보기) — ship.md Step 6
- [x] **P3-10.** `git push -u origin <branch>` + §7-5-C push fallback ladder — ship.md Step 7
- [x] **P3-11.** `gh pr list --head <branch>` 선조회 + 없으면 `gh pr create --body-file` — ship.md Step 8 (`hpx_base_branch_name` 으로 --base)
- [x] **P3-12.** §7-5-D PR 생성 실패 ladder (본문 재사용) — ship.md Step 8
- [x] **P3-13.** `/done` 로직 인라인 — TASKS `🔄`→`✅`, progress, ADR 갱신 (**PR 성공 후에만**). 판단 영역이 많아 bash 헬퍼 추출하지 않고 ship.md Step 9 에 Claude-led 로 둠
- [x] **P3-14.** state.json archive (Q24 default=archive) — `docs/plans/.archive/` + `.gitignore` 추가
- [x] **P3-15.** 재진입 매트릭스 (§6-3-3) 각 stage 별 동작 — ship.md 표로 정리 (검증은 Phase 4 execute smoke)
- [x] **P3-16.** 중복 PR 생성 방지 — Step 8 `gh pr list --head` 선조회 규약

---

## Phase 4: End-to-end (2단 분할, 2026-04-20 결정)

**분할 근거**: Phase 3 dry-run 에서 Steps 1/2/3/5 검증 완료. 가짜 task (`task-work-smoke`) 로는 execute mechanics (Steps 4/7/8/9/10) 만 정확 타겟팅 가능. KPI (G1b/G1c/cycle time) 는 실 task 에서만 의미 있어 분리.

### Phase 4a: execute mechanics 실증 (A안 — `task-work-smoke` roll-forward)

- [ ] **P4a-1.** `task-work-smoke.state.json` 현재 상태 재확인 (stage=`work.done`, branch match)
- [ ] **P4a-2.** `/ship --execute` 진입 — Step 2 precheck 통과 확인
- [ ] **P4a-3.** Step 3 GS-2 게이트 — commit_plan partition 승인 (src / test 2개)
- [ ] **P4a-4.** Step 4 커밋 생성 — `git add -A` 미사용, 파일 명시 커밋 2개, `created_commits[]` sha 기록
- [ ] **P4a-5.** Step 5 PR 본문 생성 — `.cache/pr-body-task-work-smoke.md` 확인
- [ ] **P4a-6.** Step 6 GS-3 게이트 — PR body 승인
- [ ] **P4a-7.** Step 7 push — **origin/experiment/harness-prototype 최초 푸시** (4개 기존 + 2개 신규 커밋)
- [ ] **P4a-8.** 의도적 재진입 1건 — Step 7 완료 직후 lock 제거 → 재호출 → cursor=`pr.pending` 에서 Step 8 재개 확인
- [ ] **P4a-9.** Step 8 `gh pr create` — `gh pr list --head` 선조회 규약 동작, PR URL 확보
- [ ] **P4a-10.** Step 9 `/done` — smoke task 라 TASKS/ADR 갱신은 skip 경로 확인 (또는 smoke 전용 no-op 기록)
- [ ] **P4a-11.** Step 10 archive — `docs/plans/.archive/task-work-smoke.state.<ts>.json` 이관 확인
- [ ] **P4a-12.** state.json `stage=ship.done`, `done_applied=true`, `pr_url` 존재 확인
- [ ] **P4a-13.** audit log + `gate-events.tsv` 기록 완전성 점검
- [ ] **P4a-14.** PR 사후 정리 — PR close + revert commit 1개 (`experiment/harness-prototype` 위에 `Revert ...` 2개) + archive 보존
- [ ] **P4a-15.** §7-5-C/D ladder 발동 시나리오 중 1건 이상 실측 (예: push 의도 실패 주입 — origin URL 일시 오기입)

### Phase 4b: KPI 측정 (실 task — B2 와 병행)

**입구 조건**: Phase 4a 통과. 실 task 1건 선정 완료.

- [ ] **P4b-1.** 실 task 1개 선정 (후보: P1-E PromQL NaN 가드 / B2 와 겹침) + 계획서 초안 확인
- [ ] **P4b-2.** B2 수동 베이스라인 측정 (사용자 수행, 하네스 사이클 **전**) — `baseline/template.md` 양식
- [ ] **P4b-3.** `/plan` → `/work` → `/ship --execute` 전체 사이클 실행
- [ ] **P4b-4.** invocation 수 측정 (목표 3)
- [ ] **P4b-5.** decision prompt 수 측정 (평균 ≤ 4, p95 ≤ 6)
- [ ] **P4b-6.** 수동 fallback / 수동 복붙 수 측정 (목표 0)
- [ ] **P4b-7.** `_metrics.tsv` 15컬럼 전부 누락 없이 기록 확인
- [ ] **P4b-8.** `gate-events.tsv` 기록 확인
- [ ] **P4b-9.** audit log 가독성 평가
- [ ] **P4b-10.** go/no-go 지표 점검
  - [ ] JSON 파싱 실패율 < 10%
  - [ ] high-risk degraded 승인율 ≤ 20%
  - [ ] 자동 통과율 60~85%
  - [ ] soft cap 초과 cycle ≤ 20%
- [ ] **P4b-11.** 베이스라인 대비 cycle time 악화 ≤ 20% 확인 (B2 와 직접 비교)
- [ ] **P4b-12.** 사용자 통제감 self-rating (≥ 4.0/5.0)
- [ ] **P4b-13.** §14 Lessons Learned 작성

---

## Phase 5 (선택, 1주일 사용 후)

- [ ] **P5-1.** 1주일 실사용 로그 집계
- [ ] **P5-2.** 무내용 응답 패턴 분석 → 프롬프트 보강
- [ ] **P5-3.** 게이트 default 재조정
- [ ] **P5-4.** 비용 soft cap 재조정
- [ ] **P5-5.** degraded risk threshold 재조정

---

## 크로스 컷팅 — Open Questions 결정 필요

> Phase 별 작업과 병행해 채워야 하는 사항. 답 없이 진행 시 드리프트 위험.

- [x] **Q0-1~Q0-5** (Phase 0a 에서 해결)
- [x] **Q1~Q6** (Phase 0b 에서 해결)
- [x] **Q7~Q8** 계획서 템플릿 섹션 구성 — Phase 1 전 확정
- [x] **Q9~Q10** 브랜치 명 컨벤션 (PeakCart `git log` 확인) — Phase 2 전 확정
- [x] **Q11~Q13** PR 본문 톤/양식 — Phase 3 전 확정
- [x] **Q14~Q15-1** 비용 예산 + 루프 상한 — Phase 0c 에서 확정
- [x] **Q16~Q17** 게이트 UX 5분기 적정성 / P0 무시 사유 강제 — Phase 1 전 확정
- [x] **Q18** raw JSON git 저장 여부 — v9 default 유지 (gitignore)
- [x] **Q19** P0 무시 사유 PR 본문 자동 포함 — v9 default 유지 (포함)
- [x] **Q20 / Q20-1** fallback 기준 (장애 유형별) — §5-3 v8 표 채택 여부
- [x] **Q21** ADR 인덱스 inline vs 본문 inline — Phase 0b 성공률 결과 후 결정
- [x] **Q22** 무내용 응답 fallback 임계 (1/3/5회) — v9 default (3회) 검증
- [x] **Q23** lock session_id 구현 수준 — v7 default 채택
- [x] **Q24** `/ship` 후 state.json 처리 — archive
- [x] **Q25** PR 생성 실패 시 자동 재시도 vs 수동 — v3 default (수동 + 본문 재사용)
- [x] **Q26** 게이트 always/conditional 분리 — v4 default 채택 완료
- [ ] **Q27** 수동 amend/rebase 후 sha 불일치 처리 — v7 default (사용자 확인)
- [ ] **Q28** 범용화 — DEFERRED (Phase 4 후 재평가)
- [x] **Q29** degraded risk 차등 — v9 default 채택 (`diff >= 800` / path regex)

---

## 현재 문제 목록

- [ ] **I1.** `hpx_base_branch_discover` 우선순위 정정 여부 결정 (`origin/HEAD` 우선 문제)
- [ ] **I2.** `git add -N` intent-to-add 가 `/ship` Step 4 와 충돌 없는지 Phase 4a 에서 실증
- [ ] **I3.** Phase 4a 사후 정리 스크립트(`scripts/cleanup-smoke-pr.sh`) 존재 여부 및 실행 준비 확인
- [ ] **I4.** B2~B4 베이스라인 측정 착수
