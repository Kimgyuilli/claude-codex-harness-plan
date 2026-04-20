# Harness Docs

이 디렉터리의 문서는 아래 4개 역할로만 유지한다.

## 문서 구조

- `harness-plan.md`
  - 설계 SSOT
  - 구조, 규약, fallback, 지표, open question의 원문 기준

- `TASKS.md`
  - 실행 SSOT
  - 현재 진행 상태, phase 체크리스트, 남은 이슈, 다음 액션 관리

- `SESSION-HANDOFF.md`
  - 세션 재개 메모
  - "지금 어디까지 왔고 다음에 무엇을 확인할지"만 짧게 기록

- `baseline/`
  - 측정 전용 문서
  - `README.md`: 측정 기준
  - `template.md`: 개별 task 기록 양식
  - `summary.md`: 집계 결과

## 보조 자료

- `phase0/`
  - 사전 검증 결과 보관
- `scripts/`
  - 운영 보조 스크립트

## 운영 원칙

중복을 줄이기 위해 아래 원칙을 지킨다.

1. 설계 설명은 `harness-plan.md`에만 둔다.
2. 실행 상태와 체크박스는 `TASKS.md`에만 둔다.
3. `SESSION-HANDOFF.md`에는 상세 설계나 긴 회고를 다시 적지 않는다.
4. 새 문서를 만들기 전에 기존 4개 역할 중 어디에 흡수할 수 있는지 먼저 판단한다.
