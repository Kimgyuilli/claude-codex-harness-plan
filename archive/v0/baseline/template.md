# Baseline Task: <task-id>

> **복사 후 파일명**: `baseline/task-<id>.md`
> **기록**: 실시간 append. 사후 재구성 금지.

## 메타
- **task_id**:
- **task_category**: `normal` / `high-risk`
- **started_at**:
- **ended_at**:
- **cycle_time_min**:
- **peakcart_ref**: `docs/TASKS.md` 링크 or 해당 섹션

---

## 실시간 타임라인

> 한 줄당 1 이벤트. 형식: `HH:MM | <event_type> | <detail>`
>
> event_type 예시: `invoke /sync`, `codex paste-in`, `codex paste-out`, `decision`, `terminal switch`, `manual edit`, `commit`, `push`, `PR create`

```
HH:MM | invoke /sync | ...
HH:MM | decision | 계획서에 Phase 3-4 추가
HH:MM | terminal switch | Codex 터미널 열기
HH:MM | codex paste-in | 계획서 전체 복붙
HH:MM | codex paste-out | 리뷰 결과 Claude 로 복붙
HH:MM | decision | P0 1건 반영
...
```

---

## 집계 (사이클 종료 후)

### 사용자 부담 (G1)
| 지표 | 카운트 |
|------|--------|
| invocation_count | |
| decision_count | |
| decision_count_ai_prompted | |
| decision_count_user_initiated | |
| context_switch_count | |

### fallback / 외부 전환 (G1c, G2)
| 지표 | 카운트 |
|------|--------|
| manual_copy_paste_count | |
| external_terminal_handoff_count | |

**manual_fallback_reasons**:
-

### 품질 / 리뷰
| 지표 | 카운트 |
|------|--------|
| codex_review_count | |
| codex_iteration_count | |
| codex_blank_response_count | |
| p0_identified_count | |
| p0_ignored_count | |

**p0_ignored_reasons**:
-

### 산출물
| 지표 | 값 |
|------|-----|
| plan_doc_exists | Y / N |
| adr_touched | Y / N |
| commit_count | |
| commit_mixed_category_count | |

**pr_body_sections_filled**:
- [ ] Why
- [ ] What
- [ ] How
- [ ] Test plan
- [ ] 관련

---

## 정성 평가

- **user_control_rating** (1~5):
- **cognitive_load_rating** (1~5, 5 = 부하 낮음):
- **okay_automation_count** (대충 넘긴 결정 수, 자기 신고):

**pain_points_observed**:
-

**notes** (이 사이클에서 특이한 점):
-
