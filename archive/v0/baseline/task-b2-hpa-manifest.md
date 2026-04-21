# Baseline Task: task-b2-hpa-manifest

> **복사 후 파일명**: `baseline/task-<id>.md`
> **기록**: 실시간 append. 사후 재구성 금지.
> **용도**: `P4b-1` 후보인 HPA 매니페스트 작업의 수동 베이스라인 측정 기록.

## 메타
- **task_id**: `task-b2-hpa-manifest`
- **task_category**: `normal`
- **started_at**:
- **ended_at**:
- **cycle_time_min**:
- **peakcart_ref**: `docs/TASKS.md` → `Task 3-5: HPA 검증`

---

## 실시간 타임라인

> 한 줄당 1 이벤트. 형식: `HH:MM | <event_type> | <detail>`
>
> event_type 예시: `invoke /sync`, `codex paste-in`, `codex paste-out`, `decision`, `terminal switch`, `manual edit`, `commit`, `push`, `PR create`

```
HH:MM | start | baseline 측정 시작
HH:MM | manual review | docs/TASKS.md 의 Task 3-5 요구사항 확인
HH:MM | manual edit | HPA 매니페스트 초안 작성
HH:MM | decision | target CPU / minReplicas / maxReplicas 확정
HH:MM | test | kubectl/kustomize/정적 검증 실행
HH:MM | commit | ...
HH:MM | push | ...
HH:MM | PR create | ...
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
- baseline 수동 측정이므로 필요 시 이유 기록

### 품질 / 리뷰
| 지표 | 카운트 |
|------|--------|
| codex_review_count | 0 |
| codex_iteration_count | 0 |
| codex_blank_response_count | 0 |
| p0_identified_count | |
| p0_ignored_count | |

**p0_ignored_reasons**:
-

### 산출물
| 지표 | 값 |
|------|-----|
| plan_doc_exists | N |
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
- baseline 은 하네스 없이 수동으로 수행한다
