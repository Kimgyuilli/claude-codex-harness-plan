# Harness v0 Archive

이 디렉터리는 `v0 구축/검증 단계` 문서를 보관한다.

## 포함 내용

- `harness-plan-v0.md`
  - v0 설계 원문
- `TASKS-v0.md`
  - v0 실행 체크리스트
- `SESSION-HANDOFF-v0.md`
  - v0 종료 시점 handoff
- `phase0/`
  - Phase 0 검증 결과
- `baseline/`
  - baseline 측정 문서와 기록
- `scripts/`
  - v0 보조 스크립트 보관 (`cleanup-smoke-pr.sh`, `timeout_wrapper.py`)

## 원칙

1. v0 문서는 보존용이다.
2. v1 작업을 위해 이 문서를 직접 수정하지 않는다.
3. 과거 설계 근거나 검증 결과가 필요할 때만 참조한다.
4. PeakCart는 이 아카이브 스크립트에 의존하지 않는다. 현재 필요한 파일은 PeakCart 내부 복사본만 사용한다.
