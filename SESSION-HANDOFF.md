# Session Handoff — Claude × Codex Harness 구현

> **마지막 세션**: 2026-04-19
> **다음 세션 진입 시 이 문서부터 읽을 것.**

## 현재 위치

- **설계 문서**: `harness-plan.md` Draft v9 (PeakCart 전용 reference design)
- **관리 문서**: `PHASES.md`, `TASKS.md`
- **Phase -1 B1, Phase 0 (0a/0b/0c) 완료** — 결과는 `phase0/0a-*.md`, `phase0/0b-*.md`, `phase0/0c-*.md`
- **Phase 1 착수 가능** (PeakCart 에 실제 파일 생성 필요 → 사용자 승인 후)
- **Phase -1 B2~B4 대기** (사용자가 PeakCart 에서 실제 task 3개 수동 측정 필요 — Phase 1 과 병행 가능)

## Phase 0 핵심 발견 (harness-plan.md 반영 필요 — Draft v10 후보)

### 1. `codex exec --output-schema <FILE>` 네이티브 JSON Schema 강제 지원
- **영향**: `harness-plan.md` §7-1/§7-2 의 "프롬프트로 JSON 강제 지시" 부분이 과잉. 프롬프트는 보조, 실제는 파일 스키마로 강제
- **제안**: 스키마 파일을 `.claude/schemas/plan-review.json`, `diff-review.json` 로 분리 저장
- **제약**: 모든 `object` 에 `additionalProperties: false` **필수** (OpenAI Structured Outputs 스펙). 빠뜨리면 `invalid_json_schema` 에러 + exit 1
- **검증 결과**: 5회 호출 5/5 JSON 파싱 성공 (100%), 평균 wall clock 9초, setup 60초 timeout 여유로움

### 2. nested slash 호출 불가능
- `/plan` 안에서 `/sync` 호출 불가. `.claude/scripts/shared-logic.sh` 로 추출 필요
- **이미 harness-plan.md v7 에서 "로직 재사용 / 인라인" 으로 설계 반영됨** — 구현 시 shared script 패턴 채택
- **Phase 1 선행 작업**: `.claude/scripts/shared-logic.sh` 에 `sync`, `next`, `done` 로직 추출

### 3. GNU timeout 미설치 환경
- `timeout`, `gtimeout` 모두 macOS 기본 PATH 에 없음
- **해결**: `scripts/timeout_wrapper.py` 작성 완료 (playground 에 있음, Phase 1 착수 시 PeakCart 로 복사)
- 검증: 3 시나리오 (정상/SIGTERM 처리/SIGTERM 무시) 전부 정상 동작
- 대안: 사용자 선택에 따라 `brew install coreutils` 도 가능 (아직 미설치)

### 4. Codex 비용 추적
- **tokens**: stderr 에 `tokens used\n<숫자>` **두 줄**로 노출 → 파싱 시 `grep -A1 "tokens used"` 필요
- **USD 비용**: CLI 가 직접 제공 X → 모델별 pricing table 로 환산 필요 (프록시 지표)
- `codex exec --json` JSONL 이벤트 스트림이 더 풍부한 metadata 제공 가능성 — 후속 검증 대상

### 5. Codex 인증
- 사용자는 **ChatGPT 로그인 사용 중** (`~/.codex/auth.json`, API key env 아님)
- `codex login status` 로 확인 가능

## 베이스라인 측정 (B2~B4) 제안

PeakCart Phase 3 "리뷰 개선 5건" 중 선정:
| # | Task | 구분 |
|---|------|------|
| A | **P1-E** PromQL NaN 가드 | normal |
| B | **P1-F** 대시보드 SSOT | normal |
| C | **P0-A** Outbox Slack 격리 | **high-risk** (크로스 도메인, infra) |

기록 방식: **엄격 측정** (매 이벤트 실시간 기록, 사후 재구성 금지). 템플릿 = `baseline/template.md`.

## Phase 1 착수 시 해야 할 것

1. PeakCart 에 파일 생성 승인 받기 (`/Users/kimgyuill/dev/projects/PeakCart`)
2. `scripts/timeout_wrapper.py` 를 PeakCart 로 복사
3. `.gitignore` 에 `docs/plans/*.state.json`, `docs/plans/*.lock/`, `.cache/` 추가
4. `.claude/scripts/shared-logic.sh` 작성 (`sync`/`next`/`done` 로직 추출)
5. `.claude/schemas/plan-review.json`, `diff-review.json` 작성 (`additionalProperties: false` 주의)
6. `.claude/commands/plan.md` 작성 — §6-3-1 12 step, `--output-schema` 사용
7. state.json 원자 write (`tmp` + `mv`) 구현

## 드리프트 주의

- `harness-plan.md` §7-1/§7-2 는 아직 "프롬프트 JSON 강제" 기반. Phase 1 구현 시 실제로는 `--output-schema` 쓰게 됨 → 문서 정합 위해 Draft v10 필요 (사용자 결정 대기)
- harness-plan.md §7-3 출력 스키마에 `additionalProperties: false` 명시 안 됨 → v10 에서 추가 필요

## 커밋 이력 (세션 중)

- `f1f2bca` docs: add Phase/Task management for harness implementation
- `0372d49` feat: complete Phase -1 B1 + Phase 0 (0a/0b/0c)

## 미결정 (사용자 선택 대기)

다음 세션 시작 시 사용자에게 물어볼 것:
1. **Phase 1 즉시 시작** vs **B2~B4 베이스라인 먼저** vs **harness-plan.md Draft v10 정정 먼저** 중 선택
2. timeout: Python wrapper 유지 vs `brew install coreutils` 도입
3. Phase 1 착수 시 PeakCart 에 파일 생성 승인

## 현재 task (세션 내 생성, 새 세션에서 재생성 필요)

- ✅ #1 Phase -1 B1: 베이스라인 측정 스키마 정의
- ⏸ #2 Phase -1 B2~B4: 실제 task 3개 측정 (사용자 참여 대기)
- ⏸ #3 Phase -1 B5: 3개 샘플 집계 (#2 blocked)
- ✅ #4 Phase 0a: 슬래시 커맨드 실행 모델 검증 (판정 B)
- ✅ #5 Phase 0b: Codex CLI 명세 확정 (100% JSON 성공률)
- ✅ #6 Phase 0c: macOS/gh/git 환경 확인
