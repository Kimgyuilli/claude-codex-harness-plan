# Harness v0 Archive

이 디렉터리는 `v0 구축/검증 단계` 문서를 보관한다.
루트 `v1` 문서와 분리된 읽기 전용 아카이브로 취급한다.

## 빠른 구조

- `harness-plan-v0.md`
  - v0 설계 원문 SSOT
- `TASKS-v0.md`
  - v0 실행 체크리스트
- `SESSION-HANDOFF-v0.md`
  - v0 종료 시점 handoff
- `phase0/`
  - Phase 0 사전 검증 결과
- `baseline/`
  - baseline 측정 문서, 템플릿, 기록
- `scripts/`
  - v0 보조 스크립트 보관

## 언제 무엇을 보면 되는가

- 전체 설계 근거를 다시 보고 싶을 때:
  - `harness-plan-v0.md`
- v0에서 실제로 무엇을 완료했는지 보고 싶을 때:
  - `TASKS-v0.md`
- v0 종료 시점의 다음 액션과 판단을 보고 싶을 때:
  - `SESSION-HANDOFF-v0.md`
- 왜 이런 구조/명령/환경 제약이 생겼는지 초기 검증 근거를 보고 싶을 때:
  - `phase0/README.md`
- baseline이 왜 있었고 어떤 양식/기록이 남았는지 보고 싶을 때:
  - `baseline/README.md`
- 예전 보조 스크립트를 찾고 싶을 때:
  - `scripts/README.md`

## 상세 인덱스

### 루트 문서

- `harness-plan-v0.md`
  - v0 설계 전체
  - state 모델, fallback, gate, phase 구조 원문
- `TASKS-v0.md`
  - v0 시점 실행 체크리스트
  - Phase 0~4a 진행 기록 포함
- `SESSION-HANDOFF-v0.md`
  - v0 마지막 정리 시점 메모

### 하위 디렉터리

- `phase0/`
  - `0a-slash-command-model.md`
  - `0b-codex-cli-spec.md`
  - `0c-environment.md`
- `baseline/`
  - `README.md`
  - `template.md`
  - `summary.md`
  - `task-b2-hpa-manifest.md`
- `scripts/`
  - `cleanup-smoke-pr.sh`
  - `timeout_wrapper.py`

## 관리 원칙

1. v0 문서는 보존용이다.
2. v1 작업을 위해 이 문서를 직접 수정하지 않는다.
3. 과거 설계 근거나 검증 결과가 필요할 때만 참조한다.
4. PeakCart는 이 아카이브 스크립트에 의존하지 않는다. 현재 필요한 파일은 PeakCart 내부 복사본만 사용한다.
5. v0 내용을 재사용해야 하면 복사 또는 요약해서 v1 문서에 새로 반영한다. 아카이브 원문을 활성 문서처럼 되돌려 쓰지 않는다.
