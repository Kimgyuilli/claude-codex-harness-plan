# Phase -1: 베이스라인 수집

> **목적**: 자동화 도입 *전* 수동 워크플로우의 실제 비용을 측정 → Phase 4 에서 "얼마나 개선됐는가" 의 비교 기준선.
> **대상**: PeakCart (`/Users/kimgyuill/dev/projects/PeakCart`)
> **샘플 수**: 3개 (정상 경로 2 + high-risk 후보 1)
> **참조**: `harness-plan.md` §12-1, §12-3 / `TASKS.md` B1~B5

---

## 측정 스키마

모든 task 에 대해 아래 필드를 기록. `task-XX.md` 파일 1개당 1 task.

### 1. Task 메타
| 필드 | 값 | 비고 |
|------|-----|------|
| task_id | | PeakCart `docs/TASKS.md` 의 id |
| task_category | `normal` / `high-risk` | high-risk = auth/security/payment/config/infra 또는 diff ≥ 800 예상 |
| started_at | ISO8601 | 1단계 착수 시각 |
| ended_at | ISO8601 | PR 생성 완료 시각 |
| cycle_time_min | int | ended - started (분) |

### 2. 사용자 부담 지표 (G1)

| 필드 | 의미 | 측정 방법 |
|------|------|----------|
| `invocation_count` | 사용자가 슬래시 커맨드 호출한 횟수 | `/sync`, `/next`, `/done` 등 포함. 자유 대화는 제외 |
| `decision_count` | 사용자가 "예/아니오/선택" 결정을 내린 횟수 | AI 의 질문에 응답한 횟수 |
| `decision_count_ai_prompted` | 위 중 AI 가 명시적으로 물어본 것 | Claude 가 "어떻게 할까요?" 류로 물은 경우 |
| `decision_count_user_initiated` | 위 중 사용자가 스스로 끼어든 것 | 사용자가 "잠깐, 이거 바꿔" 식으로 개입 |
| `context_switch_count` | 두 AI 도구 (Claude ↔ Codex) 사이 전환 횟수 | 터미널 전환 + 복붙 | 

### 3. 수동 fallback / 외부 전환 지표 (G1c, G2)

| 필드 | 의미 |
|------|------|
| `manual_copy_paste_count` | 복붙 (Claude → Codex 또는 Codex → Claude) 횟수 |
| `external_terminal_handoff_count` | 다른 터미널/IDE 로 이동해서 수행한 작업 수 |
| `manual_fallback_reasons[]` | 하네스 바깥으로 나간 이유 메모 (자유 텍스트) |

### 4. 품질 / 리뷰 지표

| 필드 | 의미 |
|------|------|
| `codex_review_count` | Codex 에 리뷰 요청한 총 횟수 (plan + diff) |
| `codex_iteration_count` | "보완 → 재리뷰" 루프 수 |
| `codex_blank_response_count` | Codex 가 무내용 응답 ("괜찮아 보입니다" 류) 한 횟수 |
| `p0_identified_count` | 식별된 P0 (머지 차단) 수 |
| `p0_ignored_count` | 무시하고 진행한 P0 수 |
| `p0_ignored_reasons[]` | 무시 사유 |

### 5. 산출물 지표

| 필드 | 의미 |
|------|------|
| `plan_doc_exists` | 계획서를 실제로 작성했는가 (Y/N) |
| `adr_touched` | ADR 갱신이 필요/발생했는가 |
| `commit_count` | 커밋 수 |
| `commit_mixed_category_count` | feat/fix/refactor 가 섞인 커밋 수 (분할 실패) |
| `pr_body_sections_filled[]` | PR 본문에서 채운 섹션 (Why/What/How/Test plan 등) |

### 6. 정성 평가 (사이클 종료 후)

| 필드 | 의미 |
|------|------|
| `user_control_rating` | 1~5. "내가 통제감을 느꼈는가" (5 = 매우 통제됨) |
| `cognitive_load_rating` | 1~5. "인지 부하가 낮았는가" (5 = 매우 낮음) |
| `okay_automation_count` | "ㅇㅋ" 로 대충 넘긴 결정 추정 수 (자기 신고) |
| `pain_points_observed[]` | 이 사이클에서 느낀 페인 (자유 텍스트) |

---

## 기록 방법

1. 새 task 시작 시 `baseline/task-XX.md` 를 `template.md` 에서 복사
2. **실시간 기록**: 결정/복붙/전환이 발생할 때마다 즉시 append. 사후 재구성은 부정확
3. 종료 시 정성 평가 섹션을 작성
4. 3개 완료 후 `summary.md` 에 집계

## 집계 기준 (B5)

`summary.md` 에 다음을 기록:
- 3개 평균 + p95 + range
- 정상 경로 2개 vs high-risk 1개 비교
- **Phase 4 go/no-go 지표와 직접 비교 가능한 형태**로 정리:
  - invocation_count 평균 (자동화 후 목표: 3)
  - decision_count 평균 (자동화 후 목표: ≤ 4, p95 ≤ 6)
  - manual_copy_paste_count 평균 (자동화 후 목표: 0)
  - cycle_time_min 평균 (자동화 후 목표: 베이스라인 대비 악화 ≤ 20%)

---

## 주의

- **측정 자체가 워크플로우를 왜곡**할 수 있음 (Hawthorne effect). 평소대로 진행하고 기록은 사후 30초 내 반영
- `context_switch_count` 는 터미널 전환 기준이 가장 신뢰도 높음 (주관 판단 최소화)
- "ㅇㅋ" 자동화 카운트는 양심 기반 — 과소 보고 경향에 유의
