# Harness 구현 — Phase 관리

> **Source**: `harness-plan.md` Draft v9 (§12-1, §13)
> **대상**: PeakCart (`/Users/kimgyuill/dev/projects/PeakCart`)
> **총 예상 소요**: 5~6시간 (Phase 5 제외)
> **BLOCKER**: Phase 0a 가 **결과 C** 이면 전 Phase 무효 — 문서 재설계로 전환

---

## 진행 상태 요약

| Phase | 상태 | 예상 시간 | 비고 |
|-------|------|----------|------|
| -1. 베이스라인 | ▶ 진행 | ~30분 | B1 ✅, B2~B4 사용자 참여 대기 |
| 0a. 슬래시 모델 검증 | ✅ 완료 | ~20분 | 판정 **B** (nested slash 만 우회) → `phase0/0a-*.md` |
| 0b. Codex CLI 명세 | ✅ 완료 | ~20분 | JSON 강제 5/5 = 100% → `phase0/0b-*.md` |
| 0c. 환경 확인 | ✅ 완료 | ~20분 | Python timeout wrapper 작성 → `phase0/0c-*.md` + `scripts/` |
| 1. `/plan` 구현 | ✅ 완료 | ~1.5시간 | 의도 결함 5/5 검출, `plan.done` 도달 |
| 2. `/work` 구현 | ✅ 완료 | ~1.5시간 | 의도 결함 4/4 검출, `work.done` 도달, split 헬퍼 검증 |
| 3. `/ship` 구현 | ☐ 대기 | ~1시간 | Phase 2 완료 → 착수 가능 |
| 4. End-to-end | ☐ 대기 | ~1시간 | §12-3 지표 측정 |
| 5. 안정화 (선택) | ☐ 보류 | 1주일 후 | |

상태 표기: ☐ 대기 / ▶ 진행 / ✅ 완료 / ⛔ 차단 / 🔁 재작업

---

## Phase -1: 베이스라인 수집 (~30분)

**목적**: Phase 4 비교 기준선 확보. 자동화 전 수동 방식의 실제 비용을 측정해야 "얼마나 개선됐는가" 를 말할 수 있다.

**입구 조건**: 없음 (착수 시작점)

**출구 조건**:
- 정상 경로 2개 + high-risk 후보 1개, 총 3개 task 샘플 확보
- 동일 스키마로 기록된 invocation/decision/cycle time/수동 fallback/수동 복붙 데이터

**주요 산출물**:
- 베이스라인 측정 시트 (task × metric)

**참조**: `harness-plan.md` §12-1, §12-3

---

## Phase 0: 사전 확인 (~1시간)

> Phase 0 은 0a → 0b → 0c 순서로 직렬. 0a 실패 시 0b/0c 이후 무의미.

### Phase 0a — 슬래시 커맨드 실행 모델 검증 (BLOCKER)

**목적**: 본 설계의 핵심 가정 ("슬래시 커맨드가 다단계 게이트/루프/하위 호출 지원") 을 검증.

**검증 질문** (§11-0):
- Q0-1. 슬래시 커맨드는 단순 프롬프트 확장인가, 다단계 흐름 제어 가능한가
- Q0-2. 커맨드 실행 도중 사용자 입력을 여러 번 받을 수 있는가
- Q0-3. nested slash 호출이 가능한가
- Q0-4. 실행 도중 자유 메시지 인터럽트 동작
- Q0-5. Bash stdout/stderr 가 긴 경우 truncation 정책

**결과 분기**:
- A. 안정 지원 → Phase F 유지, 0b 로 진행
- B. 일부 제약, 우회 가능 → Phase F 유지, §6 우회안 문서화
- **C. 본질적 불가능 → 전 Phase 중단, §5-2 D 재진입 (외부 하네스) 로 문서 재설계**

**출구 조건**: A 또는 B. C 이면 stop.

### Phase 0b — Codex CLI 명세 확정

**목적**: `$CODEX_CMD` 추상명을 실제 인터페이스로 치환.

**검증 항목** (§11-1):
- Q1~Q6, Q6-1 답변 확보
- JSON 출력 강제 5회 호출 성공률 측정 (목표 > 90%)

**출구 조건**: 확정된 `codex` 호출 형태 + non-interactive 플래그 + 작업 디렉토리 지정 방식 + 인증 방식 + JSON 성공률 수치

### Phase 0c — macOS / gh / git 환경 확인

**필수 확보**:
- **hard timeout provider**: `timeout` / `gtimeout` / `python3 scripts/timeout_wrapper.py` 중 **하나는 반드시** (§2-2)
- `gh --version`, `gh auth status`, origin remote, push 권한
- `.gitignore` 갱신: `docs/plans/*.state.json`, `docs/plans/*.lock/`, `.cache/`
- state atomic write (`tmp` + `mv`) 규약 검증
- `attempts_by_command.*`, `codex_attempts_cycle_total`, degraded risk threshold 숫자 확정

**출구 조건**: 위 전부 ✅. timeout provider 없으면 **Phase 0c 실패 → 구현 착수 금지**.

---

## Phase 1: `/plan` 구현 (~1.5시간)

**입구 조건**: Phase 0a/0b/0c 전부 통과

**산출물**:
- `docs/plans/.gitkeep`
- `.claude/commands/plan.md`
- §10-1 계획서 템플릿 적용
- §6-4 state.json + audit log + lock 통합

**출구 조건**:
- 가짜 task 1개로 한 사이클 dry-run
- 산출물 (`docs/plans/<task-id>.md`, `<task-id>.state.json`, `.audit/<task-id>.md`) 정합 확인
- stage: `plan.draft.created` → `plan.review.completed` → `plan.done` 전이 확인
- lock 획득/해제 동작 확인

**참조**: §6-3-1, §7-1, §10-1

---

## Phase 2: `/work` 구현 (~1.5시간)

**입구 조건**: Phase 1 통과

**산출물**:
- `.claude/commands/work.md`
- base branch discovery 4단 폴백 검증
- `git diff $BASE` 가 첫 구현 직후에도 변경분 캡처 확인 (F2)
- §7-4 diff 분기 임계값 (500/2000) 검증
- split review 시 `review_plan.chunks[]` 상태 추적

**출구 조건**:
- 작은 실제 task 로 branch + diff + 리뷰 1사이클
- 중단 후 재개 시뮬레이션 (state 기반 이어받기)
- stage: `work.impl.completed` → `work.review.completed` → `work.done` 확인

**참조**: §6-3-2, §7-2, §7-4

---

## Phase 3: `/ship` 구현 (~1시간)

**입구 조건**: Phase 2 통과

**산출물**:
- `.claude/commands/ship.md`
- §10-2 PR 템플릿
- §10-3 커밋 분할 로직
- GS-2/GS-3 always 게이트 배치

**출구 조건**:
- `/done` 이 **PR 생성 성공 후** 에만 동작하는지 검증 (F4)
- PR 생성 실패 시 TASKS.md 미갱신 유지 확인
- 재진입 매트릭스 (§6-3-3) stage 별 동작 확인
- PR URL 반환 성공

**참조**: §6-3-3, §7-5-C/D/E, §10-2, §10-3

---

## Phase 4: End-to-end (~1시간)

**입구 조건**: Phase 1~3 전부 통과

**검증**:
- 실제 PeakCart Phase 3 task 1개로 전체 사이클
- §12-3 정량 지표 측정 (G1a/b/c 전부)
  - invocation 수 (목표 3)
  - decision prompt 평균 ≤ 4, p95 ≤ 6
  - 수동 fallback/복붙 수 0
- audit log 가독성 평가
- `_metrics.tsv`, `gate-events.tsv` 누락 없이 기록됐는지

**go / no-go 기준** (§12-3):
- JSON 파싱 실패율 ≥ 10% → rollout 중단
- high-risk degraded 승인율 > 20% → 게이트 정책 재설계
- decision prompt 평균 > 4 → 피로 절감 미달
- 자동 통과율 > 90% → 통제권 약화 경고
- soft cap 초과 cycle > 20% → 비용 정책 재설계
- 사용자 통제감 설문 < 4.0/5.0 → UX 재설계

**출구 조건**: 위 go/no-go 전부 통과 + §14 회고 작성

---

## Phase 5: 안정화 (1주일 사용 후, 선택)

**입구 조건**: Phase 4 통과 + 1주일 실사용

**활동**:
- 프롬프트 보강 (무내용 응답 패턴 분석)
- 게이트 default 조정
- 비용 상한 재조정
- degraded risk threshold 재조정

**출구 조건**: 없음 (지속적 개선 루프)

---

## Phase 전환 게이트 (공통)

각 Phase → 다음 Phase 전환 전 확인:
1. 해당 Phase 출구 조건 전부 ✅
2. `harness-plan.md` 의 관련 §에 드리프트 없음
3. 이전 Phase 에서 발견한 이슈가 차기 Phase 설계에 반영됨
4. state/audit/metrics 파일이 의도대로 갱신됨
