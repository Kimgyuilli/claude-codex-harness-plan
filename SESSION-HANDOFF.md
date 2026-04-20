# Session Handoff — Claude × Codex Harness 구현

> **역할**: 세션 재개 메모
> **원칙**: 상세 설계와 체크박스는 여기 다시 적지 않는다.

## 현재 위치

- 설계 SSOT: `harness-plan.md`
- 실행 SSOT: `TASKS.md`
- 현재 단계: `Phase 4b` 준비
- 완료 범위: `Phase 0~2`, `Phase 3 scaffold + dry-run smoke`, `B1`, stale smoke archive, `/ship` drift guard 반영, `Phase 4a` execute mechanics 실증 완료
- 병행 대기: `B2~B4` 수동 베이스라인 측정
- 현재 blocker: 설계 blocker 는 없음. 다음은 베이스라인 측정과 실 task 선정
- 설계 상태: `I1`, `I2` 해결. stale-state 대응 규칙과 execute mechanics 검증 완료

## 다음에 바로 할 일

1. `baseline/template.md` 기준으로 `B2~B4` 측정 착수
2. `P4b-1` 실 task 1건 선정
3. 선정된 task 에 대해 `/plan` → `/work` → `/ship --execute` 전체 사이클 실행
4. `_metrics.tsv`, `gate-events.tsv`, audit log 를 기준으로 KPI 판정

## 남은 핵심 이슈

- `I4`: `B2~B4` 베이스라인 측정 착수
- `P4b`: 실 task 기반 KPI 측정과 go/no-go 판정

## 기억할 사실

- `Phase 3`은 미착수가 아니라 "구현 완료 + execute 검증 대기" 상태다
- `Phase 4a`는 `task-ship-smoke-fresh` 기준으로 성공 완료됐다
- smoke PR 은 merge 금지, 종료 후 revert + archive 보존이 원칙이다
- 설계 미결정이 남아 있으면 구현보다 설계 문서 갱신이 먼저다
- base branch 우선순위는 `env > git config > origin/HEAD > main` 으로 고정했다
- archived state 는 재사용하지 않는다. `Phase 4a` 는 항상 fresh `work.done` state 로 재진입한다
- fresh smoke 후보는 `PeakCart/docs/plans/task-ship-smoke-fresh.md` 로 고정했다
- `Phase 4a` 증적: PR `#21` close, revert `2fa990c`/`69882bc`, archive state 보존

## 재개 체크리스트

1. `cat README.md`
2. `cat SESSION-HANDOFF.md`
3. `cat TASKS.md`
4. `PeakCart` 현재 브랜치가 `experiment/harness-prototype` 인지 확인
5. `baseline/README.md` 와 `baseline/template.md` 확인
6. `PeakCart/docs/plans/.archive/task-ship-smoke-fresh.state.20260420T203433Z.json` 증적 경로 확인
