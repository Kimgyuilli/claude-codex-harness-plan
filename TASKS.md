# Harness v1 — Task 체크리스트

> 역할: v1 실행 SSOT
> 범위: 실사용 편의 개선, 토큰 최적화, 다음 실 task 적용

---

## 현재 진행

- 현재 단계: `v1 준비`
- v0 상태: archive 완료
- 다음 실사용 task: `PeakCart/docs/plans/task-hpa-manifest.md`
- 다음 액션: `/plan task-hpa-manifest`

## v1 목표

- 실사용 중 덜 막히는 하네스 만들기
- 의미 손실 없이 토큰 사용 줄이기
- 반복적인 형식 검사를 AI 호출 전 로직으로 처리하기

## v1 작업

### A. 실사용 적용

- [ ] **V1-1.** `task-hpa-manifest`에 `/plan` 적용
- [ ] **V1-2.** 같은 task에 `/work` 적용
- [ ] **V1-3.** 같은 task에 `/ship --execute` 적용
- [ ] **V1-4.** 사용 체감 메모 작성
  - 편했던 점
  - 불편했던 점
  - 다시 쓰고 싶은지

### B. 토큰 최적화

- [x] **V1-5.** `sync/context` 구조화 요약 적용
- [x] **V1-6.** `/plan` 전 계획서 lint 적용
- [x] **V1-7.** `/work` diff 메타데이터 요약 적용
- [ ] **V1-8.** PR 본문 정형 부분 자동화 강화
- [ ] **V1-9.** state 요약 출력 추가
- [ ] **V1-10.** task별 참조 문서 목록화

### C. 운영 정리

- [ ] **V1-11.** `task-hpa-manifest` 실사용 결과를 바탕으로 게이트/출력 길이 조정
- [ ] **V1-12.** 필요하면 baseline을 선택적으로만 보강
- [ ] **V1-13.** v1 종료 시 archive/v1 기준 정리

## 현재 판단

- v0는 완료로 본다
- v1의 1차 성공 기준은 정량 수치보다 실제 사용 체감이다
- 다음부터는 v0 문서를 수정하지 않고 `archive/v0/`를 참조만 한다

## 참조

- v1 로드맵: `V1-ROADMAP.md`
- 세션 재개: `SESSION-HANDOFF.md`
- v0 아카이브: `archive/v0/README.md`
