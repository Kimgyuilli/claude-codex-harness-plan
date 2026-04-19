# Baseline Summary — 3 task 집계

> **작성 시점**: 3개 task 측정 완료 후 (B5)
> **용도**: Phase 4 end-to-end 결과와의 비교 기준선
> **참조**: `harness-plan.md` §12-3 go/no-go 기준

---

## 개별 task 요약

| 필드 | task-A (normal) | task-B (normal) | task-C (high-risk) |
|------|-----------------|-----------------|--------------------|
| task_id | | | |
| cycle_time_min | | | |
| invocation_count | | | |
| decision_count | | | |
| context_switch_count | | | |
| manual_copy_paste_count | | | |
| codex_review_count | | | |
| codex_iteration_count | | | |
| p0_identified_count | | | |
| p0_ignored_count | | | |
| commit_count | | | |
| user_control_rating | | | |
| cognitive_load_rating | | | |

---

## 집계 (평균 / p95 / range)

| 지표 | 평균 | p95 | min~max | Phase 4 목표 |
|------|------|-----|---------|--------------|
| invocation_count | | | | **3** |
| decision_count | | | | **≤ 4 (p95 ≤ 6)** |
| manual_copy_paste_count | | | | **0** |
| context_switch_count | | | | 감소 (수치는 Phase 4 에서 결정) |
| cycle_time_min | | | | 베이스라인 대비 악화 ≤ 20% |
| codex_iteration_count | | | | 유지 또는 감소 |
| codex_blank_response_count | | | | < 10% (호출 대비) |

---

## 정상 경로 vs high-risk 비교

| 지표 | 정상 2개 평균 | high-risk 1개 | 비고 |
|------|---------------|---------------|------|
| cycle_time_min | | | |
| decision_count | | | high-risk 는 p95 ≤ 8 까지 허용 (§3-1 G1b) |
| p0_identified_count | | | high-risk 가 더 많아야 정상 |

---

## 관찰된 페인 포인트 (3개 task 공통)

-

## Phase 4 비교 시 주의사항

- task 난이도 편차 → `task_category` 로 계층화 비교
- 측정 자체가 워크플로우 왜곡 → Hawthorne 보정은 불가, 주관 편향 기록
- "ㅇㅋ" 자동화 카운트는 과소 보고 가능성 — 절대값보다 Phase 4 와의 상대 변화가 중요

## 다음 단계

Phase 0a 로 진행 — 슬래시 커맨드 실행 모델 검증 (BLOCKER)
