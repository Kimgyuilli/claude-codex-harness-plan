# Session Handoff — Claude × Codex Harness 구현

> **역할**: 세션 재개 메모
> **원칙**: 상세 설계와 체크박스는 여기 다시 적지 않는다.

## 현재 위치

- 설계 SSOT: `harness-plan.md`
- 실행 SSOT: `TASKS.md`
- 현재 단계: `Phase 4a` 진입 준비
- 완료 범위: `Phase 0~2`, `Phase 3 scaffold + dry-run smoke`, `B1`
- 병행 대기: `B2~B4` 수동 베이스라인 측정
- 현재 blocker: `gh auth status` 실패로 PR 경로 실행 불가
- 설계 상태: `I1` 해결, `I2` 는 규칙 확정 후 실증만 남음

## 다음에 바로 할 일

1. `TASKS.md`의 `P4a-1 ~ P4a-15`를 기준으로 실행 준비 확인
2. `PeakCart`에서 `task-work-smoke.state.json`, 현재 branch, `gh` 권한 상태 확인
3. `scripts/cleanup-smoke-pr.sh`에 넣을 `PR 번호 / branch / revert SHA` 기록 위치 확정
4. `Phase 4a` 종료 후 이 문서의 현재 위치만 갱신

## 남은 핵심 이슈

- `B0`: GitHub CLI 인증 복구 필요
- `I2`: intent-to-add preflight 가 `/ship` Step 4 에서 설계대로 동작하는지 실증
- `I4`: `B2~B4` 베이스라인 측정 착수

## 기억할 사실

- `Phase 3`은 미착수가 아니라 "구현 완료 + execute 검증 대기" 상태다
- `Phase 4b`는 `Phase 4a` 완료 전 들어가면 안 된다
- smoke PR 은 merge 금지, 종료 후 revert + archive 보존이 원칙이다
- 설계 미결정이 남아 있으면 구현보다 설계 문서 갱신이 먼저다
- base branch 우선순위는 `env > git config > origin/HEAD > main` 으로 고정했다

## 재개 체크리스트

1. `cat README.md`
2. `cat SESSION-HANDOFF.md`
3. `cat TASKS.md`
4. `PeakCart` 현재 브랜치가 `experiment/harness-prototype` 인지 확인
5. `docs/plans/task-work-smoke.state.json` 와 archive 경로 확인
6. `scripts/cleanup-smoke-pr.sh --help` 로 정리 절차 확인
