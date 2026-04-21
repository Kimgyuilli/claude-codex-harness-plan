# v0 Scripts Archive

이 디렉터리는 `v0`에서 사용하거나 준비했던 보조 스크립트를 보관한다.

## 파일

- `cleanup-smoke-pr.sh`
  - v0 smoke PR 정리 보조 스크립트
- `timeout_wrapper.py`
  - macOS에서 GNU `timeout` 부재 시 쓰던 Python wrapper

## 현재 원칙

- 이 스크립트들은 보존용이다.
- PeakCart는 이 디렉터리의 파일에 의존하지 않는다.
- 현재 필요한 파일은 PeakCart 내부 복사본 또는 PeakCart 자체 구현만 사용한다.

## 언제 참조하는가

- v0 smoke 정리 절차를 다시 확인할 때
- timeout wrapper의 원형 구현을 다시 보고 싶을 때
