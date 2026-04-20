# Phase 4a Readiness

> **목적**: `task-work-smoke` 기준 `Phase 4a` 실행 직전 준비 상태를 고정한다.
> **범위**: 실행 전 확인, 남은 선결정, 실행 순서, 사후 정리.
> **기준 시점**: 2026-04-21

---

## 현재 판단

- `Phase 0`, `Phase 1`, `Phase 2` 는 완료
- `Phase 3` 는 scaffold 구현과 dry-run smoke 까지 완료
- 다음 실제 작업은 `Phase 4a`
- 아직 `Phase 4b` 로 가면 안 된다

이유:
- execute mechanics 검증이 먼저다
- 베이스라인 `B2~B4` 가 비어 있어 KPI 해석이 아직 불완전하다

---

## 이미 준비된 것

- `TASKS.md` / `PHASES.md` / `SESSION-HANDOFF.md` 상태 정합화 완료
- `Phase 4a` 체크리스트 분해 완료
- smoke 정리 정책 확정:
  - PR 은 merge 금지
  - smoke commits 는 revert
  - archive 는 보존
- `scripts/cleanup-smoke-pr.sh` 초안 준비

---

## 다음 단계 진입 전 필수 확인

아래 6개가 확인되면 `Phase 4a` 진입 준비 완료로 본다.

1. `PeakCart` 현재 브랜치가 `experiment/harness-prototype` 인지 확인
2. `docs/plans/task-work-smoke.state.json` 가 존재하고 `stage=work.done` 인지 확인
3. `state.branch` 와 현재 `HEAD` 브랜치가 일치하는지 확인
4. `scripts/cleanup-smoke-pr.sh` 사용법과 입력값(`--pr`, `--branch`, `--revert`) 확정
5. `gh auth status` 와 `origin` push 권한 재확인
6. `Phase 4a` 종료 후 바로 정리할 revert 대상 commit 2개를 기록할 위치 확정

---

## 남은 선결정

### D1. base branch override

문제:
- 현재 `origin/HEAD` 가 env/config override 보다 우선한다

영향:
- 실험 브랜치에서 base override 가 필요할 때 원하는 기준 branch 를 강제하기 어렵다

이번 단계 판단:
- `Phase 4a` 진입 자체를 막는 blocker 는 아님
- 다만 `Phase 4b` 전에는 결정 또는 helper 수정이 필요하다

### D2. `git add -N` 후속 영향

문제:
- `/work` 에서 untracked 포함을 위해 intent-to-add 를 남긴다

영향:
- `/ship` Step 4 의 파일 명시 커밋 흐름과 충돌할 가능성이 있다

이번 단계 판단:
- `Phase 4a` 에서 반드시 실증한다
- 결과가 안전하면 `I2` 종료
- 충돌하면 `/ship` 전처리 규칙 보강 후 재시도

---

## 실행 순서

`Phase 4a` 는 아래 순서로 진행한다.

1. 상태 확인
2. `--execute` 진입
3. commit 2개 생성
4. PR body 생성/승인
5. push
6. 재진입 1건 실증
7. PR 생성
8. `/done` skip/no-op 경로 확인
9. archive 확인
10. PR close + revert 2개 + archive 보존

---

## 실행 중 기록해야 할 것

- 생성된 commit SHA 2개
- 생성된 PR URL
- 재진입 시점의 state cursor
- push 실패 ladder 를 주입했다면 실패 시 state 값
- 정리 후 revert commit SHA

이 값들은 `SESSION-HANDOFF.md` 와 `TASKS.md` 에 바로 반영한다.

---

## Phase 4a 완료 조건

아래가 모두 충족되면 `Phase 4a` 종료다.

- `P4a-1 ~ P4a-15` 전부 완료
- `I2` 실증 결과 기록 완료
- cleanup 스크립트 또는 동등 절차로 smoke 정리 완료
- `SESSION-HANDOFF.md` 다음 위치가 `Phase 4b` 로 갱신됨

---

## Phase 4b 진입 조건

- `Phase 4a` 완료
- `B2` 수동 베이스라인 측정 완료
- 실 task 1건 선정 완료
- KPI 기록 위치(`_metrics.tsv`, `gate-events.tsv`, audit log`) 확인 완료
