# Claude × Codex 하이브리드 워크플로우 하네스 — 설계 문서

> **상태**: Draft v3 — 2차 리뷰 반영 완료, 재리뷰 대기
> **작성**: 2026-04-18
> **대상 프로젝트**: PeakCart (`/Users/kimgyuill/dev/projects/PeakCart`) — **본 문서는 PeakCart 전용 reference design**. 범용 하네스로의 추상화는 §3-2 의 비목표로 명시됨. 다른 프로젝트 재사용은 본 안 검증 후 별도 문서에서 다룸.
> **이 문서의 용도**: 여러 차례 리뷰/개선을 거친 후 구현. 지금은 **합의 형성용 설계 문서**이며 구현 명령서가 아님.
> **핵심 가정의 미검증 상태 (F1 Blocker)**: 본 설계 전반은 "슬래시 커맨드가 다단계 게이트/루프/하위 호출을 지원한다" 는 가정 위에 서 있으며, 이 가정이 거짓이면 §6~§13 대부분이 무효. Phase 0a (§13) 검증 전까지 본 문서는 **실행 명세가 아닌 가설 설계**.

---

## 0. 리뷰어를 위한 안내

### 0-1. 이 문서를 어떻게 읽어야 하는가
- **§1~3 (Why)** 부터 합의: 문제 정의와 목표가 맞는가
- **§4~5 (What)** 다음 합의: 해결안의 방향성이 맞는가
- **§6~9 (How)** 마지막 검토: 구체적 설계 — 가장 자주 바뀔 영역
- **§11 (Open Questions)** 은 리뷰어가 명시적으로 답해야 할 항목

### 0-2. 가장 비판적으로 봐주셨으면 하는 부분
1. **§1-2 의 페인 포인트** 가 실제로 비용이 큰가, 아니면 자동화 욕심인가
2. **§3 의 비목표 (Non-goals)** 가 너무 보수적이거나 너무 야심찬가
3. **§5 의 대안 비교** 에서 빠진 옵션이 있는가
4. **§6-2 의 사용자 게이트 위치** — 너무 많이 묻는가, 너무 적게 묻는가
5. **§9 의 위험 식별** 이 충분한가

### 0-3. 용어 정의
| 용어 | 의미 |
|------|------|
| 사이클 | 한 task 의 계획 수립부터 PR 생성까지의 한 바퀴 |
| 게이트 | 자동 진행을 멈추고 사용자 결정을 기다리는 지점 |
| 루프 | 같은 단계를 만족할 때까지 반복하는 구간 (예: 리뷰 → 보완 → 재리뷰) |
| 하네스 | 도구들을 묶어 워크플로우를 자동화하는 얇은 오케스트레이션 층 |
| Codex | OpenAI Codex CLI (다른 모델 패밀리, 본 프로젝트에서 리뷰어 역할) |
| Claude | Claude Code (본 프로젝트에서 계획·구현 주체) |

---

## 1. 문제 정의

### 1-1. 현재 워크플로우 (있는 그대로)

PeakCart 프로젝트 한 task 진행 시 사용자가 수동으로 수행하는 8단계:

| # | 단계 | 주체 | 도구 | 비고 |
|---|------|------|------|------|
| 1 | 프로젝트 상태 파악 | Claude | `/sync` 슬래시 커맨드 | 이미 자동화됨, 사용자가 invoke |
| 2 | 다음 task 확인 + 계획서 작성 요청 | 사용자 ↔ Claude | 자유 대화 | 템플릿 강제 없음 |
| 3 | Codex 터미널 열기 → 계획 복붙 → 리뷰 요청 → 결과 복붙 | 사용자 | 별도 터미널 + 복사·붙여넣기 | 컨텍스트 전환, 정보 손실 가능 |
| 3.1 | 리뷰 결과를 Claude 에 전달 → 보완 요청 → 만족할 때까지 반복 | 사용자 ↔ Claude ↔ Codex | 두 도구 양방향 복붙 | 사용자가 두 AI 대화의 동기화를 책임 |
| 4 | 브랜치 이동 + 계획서대로 구현 | Claude | Claude Code | |
| 5 | diff 를 Codex 에 리뷰 요청 → 결과 Claude 에 전달 → 보완 → 반복 | 사용자 ↔ Claude ↔ Codex | 동일 패턴 (diff 가 더 큼) | 큰 diff 는 복붙 자체가 부담 |
| 6 | 진행 상황 반영 | Claude | `/done` 슬래시 커맨드 | 이미 자동화됨 |
| 7 | 작업별 커밋 | Claude | 자유 대화로 지시 | 분할 기준 매번 다름 |
| 8 | 리뷰어 친화적 PR 생성 | Claude | 자유 대화로 지시 | 톤/구조 매번 다름 |

### 1-2. 페인 포인트

| 페인 | 빈도 | 비용 | 근거 |
|------|------|------|------|
| 두 AI 도구 간 컨텍스트 전환 | 사이클당 4~10회 | 사용자 인지 부하 | 단계 3, 3.1, 5 가 매번 발생 |
| 복붙으로 인한 정보 손실 | 큰 diff 일수록 발생 | 리뷰 정확도 저하 | 터미널 스크롤백 한계, 클립보드 truncation |
| 사용자가 두 AI 대화의 동기화 책임 | 매 사이클 | 인지 부하 + 일관성 저하 | 어느 쪽이 최신 정보를 가지고 있는지 사용자가 추적 |
| 리뷰 피드백의 감사 흔적 부재 | 매 사이클 | "왜 이 결정을 했는지" 추적 불가 | 리뷰 결과는 터미널 기록으로만 남음 |
| 루프 피로 ("그냥 ㅇㅋ" 함정) | 사이클이 길수록 | 리뷰 품질 저하 | 3.1, 5 의 반복이 사용자 의지력에 의존 |
| 사이클의 일관성 저하 | 사용자 컨디션에 따라 | 산출물 품질 편차 | 같은 워크플로우가 매번 다르게 실행됨 |

### 1-3. 문제의 본질

이 워크플로우는 **두 AI 모델을 비대칭적으로 사용**하고 있음 — Claude 는 IDE 통합/대화/도구 호출이 풍부하지만 자기 산출물에 대한 sycophancy bias 가 있고, Codex 는 다른 모델 패밀리라 독립적 시각을 제공하지만 PeakCart 프로젝트 컨텍스트가 매번 zero 에서 시작. 사용자는 두 모델을 **수동으로 직렬 연결하는 미들웨어 역할**을 하고 있음.

자동화의 핵심은 미들웨어 역할을 사용자에게서 도구로 옮기되, **결정권은 사용자에게 남기는 것**.

---

## 2. 컨텍스트 및 제약 조건

### 2-1. 사용자가 명시한 제약
1. **Codex 를 반드시 사용해야 함** — 계획자(Claude) 와 다른 모델 패밀리의 리뷰가 본 워크플로우의 핵심 가치
2. **Claude 와 Codex 둘 다 로컬 파일/diff 를 직접 읽을 수 있어야 함** — 복붙 의존을 끊어야 함
3. **Claude Code 기반 인프라에 한정되지 않아도 됨** — 필요하면 별도 하네스 가능

### 2-2. 환경 제약
- OS: macOS (Darwin 25.3.0)
- Shell: zsh
- Claude Code: 현재 사용 중 (슬래시 커맨드/Bash/Edit/Write 도구 보유)
- Codex CLI: 사용자가 별도 터미널에서 사용 중 (정확한 명령 명세는 §11-1 에서 확정 필요)
- Git: 로컬 + GitHub 원격

**macOS 도구 portability 주의** (v2 추가 — F7 대응):
- `timeout` 은 macOS 기본 PATH 에 없음 (GNU coreutils 의존). 본 문서의 `timeout 60s ...` 호출은 다음 패턴으로 표준화:
  ```bash
  if command -v timeout >/dev/null; then TIMEOUT="timeout 60"
  elif command -v gtimeout >/dev/null; then TIMEOUT="gtimeout 60"
  else TIMEOUT=""  # 없으면 무한 대기 + 사용자 경고
  fi
  ```
- 또는 Python wrapper (`python3 -c "import signal; ..."`) 표준화. Phase 0 에서 사용자 환경 확인 후 결정.

### 2-3. 자산
| 자산 | 위치 | 활용 |
|------|------|------|
| `.claude/commands/sync.md` | PeakCart | 그대로 유지, `/plan` 내부 호출 |
| `.claude/commands/next.md` | PeakCart | 그대로 유지, `/plan` 인자 없을 때 호출 |
| `.claude/commands/done.md` | PeakCart | 그대로 유지, `/ship` 내부 호출 |
| `.claude/settings.json` | PeakCart | `codex@openai-codex` 플러그인 활성화돼 있으나 본 안에서는 사용 안 함 (§5 참조) |
| `docs/TASKS.md` | PeakCart | task 상태의 SSOT |
| `docs/adr/` | PeakCart | 결정 근거 reference |
| `docs/01~07-*.md` | PeakCart | 현재 상태 reference |
| `docs/consistency-hints.sh` | PeakCart | `/ship` 사전 점검에 활용 |

---

## 3. 목표 및 비목표

### 3-1. 목표 (Goals)

**기능적 목표** (v2 — F5 대응으로 G1 분할)
- **G1a. invocation 횟수**: 진입 슬래시 커맨드 호출 수 = **8회 → 3회** (`/plan`, `/work`, `/ship`)
- **G1b. decision prompt 횟수**: 사용자 게이트 응답 횟수 = **베이스라인 측정 + 의식적 통제** (목표치는 Phase 4 후 확정. 현 §6-2 추정 5~7회)
- **G1c. context switch 횟수**: 사용자가 Claude ↔ Codex 도구 사이를 직접 전환한 횟수 = **0회**
- **G2. 복붙 횟수**: 사용자가 한쪽 출력을 다른 쪽 입력으로 복붙한 횟수 = **0회** (G1c 와 짝)
- **G3. 감사 흔적 보존**: 리뷰 요약 + 사용자 결정 + P0 무시 사유는 **재부팅/정리에 영향받지 않는 위치** (§6-4 참조)
- **G4. 사용자 결정 흐름 유지**: 자동 무시 X, 매 게이트 default 가 안전 옵션

> G1a 만 보면 자동화 효과가 과대평가될 수 있음. **G1a + G1b 를 함께 보고**, G1b 가 8회보다 의미 있게 줄지 않으면 사용자 피로 절감 효과 미미로 판정.

**비기능적 목표** (v2 — F6 대응으로 N4 보강)
- N1. 신규 인프라/외부 서비스 추가 없음
- N2. 셋업 총 시간: ≤ 5시간
- N3. 기존 `/sync`, `/next`, `/done` 단독 호출이 영향받지 않음
- **N4. 비용 측정 가능성**:
  - 1순위: codex CLI 가 토큰/비용 메타데이터 노출 시 그 값 사용
  - **fallback (CLI 미노출 시)**: 호출 수, 입력 byte/lines, 출력 byte 를 프록시 지표로 측정 (§12-3 참조)

### 3-2. 비목표 (Non-Goals) — 의도적 제외

| 비목표 | 제외 사유 |
|--------|----------|
| 사용자 게이트의 완전 제거 | 결정권은 사용자가 보유. "ㅇㅋ 자동화" 함정 회피 |
| 멀티 모델 (3개 이상) 앙상블 | 2축 검증의 효용을 먼저 확인. Gemini 등은 후속 단계에서 검토 |
| CI/CD 와의 통합 | 본 안은 로컬 사이클만. PR push 후의 CI 는 별도 |
| 비동기/백그라운드 리뷰 | 사용자 게이트가 동기 흐름이라 비동기의 효용이 작음 |
| Claude Code 외 다른 IDE 지원 | 사용자가 Claude Code 단일 환경 |
| 외부 모델 (Gemini, GPT 등) 추가 | Codex 만으로 §3-1 목표 달성 가능 |
| 자체 UI/대시보드 구축 | 터미널 출력으로 충분 |

### 3-3. 명시적으로 보류 (Deferred)
- **호출 비용의 자동 budget 통제** — Phase 4 후 베이스라인을 봐야 정함
- **리뷰 raw JSON 의 git 영구 저장** — `docs/plans/` 와 요약 audit log 는 git 추적, raw JSON 은 gitignore 캐시 (§6-4 참조. v2 에서 변경: 더 이상 `/tmp` 휘발 아님)
- **코어/어댑터/프로젝트 3층 분리 및 범용화** (v3 추가 — F9~F11 대응) — 본 안은 PeakCart 단일 프로젝트 reference design. Phase 4 end-to-end 검증 후 다음 프로젝트 적용 니즈가 생기면 그때 재구조화 여부를 결정. 지금은 **의도적으로 단층 설계** — 조기 추상화는 (a) 현 단계 과잉 (b) 검증 전 가정이 옳은지 모름 (c) 기존 Layer 1/ADR 컨벤션을 어댑터로 빼는 순간 인라인 주입의 이점 상실. Q28 참조.

---

## 4. 해결안 개요

### 4-1. 한 줄 요약
**Claude Code 의 슬래시 커맨드 안에서 Codex CLI 를 Bash subprocess 로 호출**하여 두 모델의 협업을 자동화하고, 결정 게이트만 사용자에게 남긴다.

### 4-2. 신규 슬래시 커맨드 3종

| 커맨드 | 흡수하는 기존 단계 | 책임 |
|--------|-------------------|------|
| `/plan [<task-id>]` | 1, 2, 3, 3.1 | 계획 수립 + Codex 리뷰 루프 |
| `/work` | 4, 5 | 구현 + diff Codex 리뷰 루프 |
| `/ship` | 6, 7, 8 | 진행 반영 + 작업별 커밋 + PR 생성 |

### 4-3. 핵심 메커니즘
- **Codex 호출**: `codex exec --cd $(pwd)` 형태로 Bash subprocess 실행, 출력은 파일로 redirect
- **컨텍스트 주입**: 코덱스에게 "프로젝트 루트에서 ADR/계획서를 직접 읽으라" 고 경로만 전달 (복붙 X)
- **출력 강제 형식**: JSON 스키마 강제 → Claude 가 파싱해 사용자에게 정형 표로 제시
- **사용자 게이트**: 매 리뷰 결과마다 5분기 선택지 (전체/일부/무시/종료 등)
- **루프 상한**: 한 슬래시 커맨드 내 codex 호출 최대 3회, 초과 시 명시 확인

### 4-4. 기존 워크플로우와의 호환
- `/sync`, `/next`, `/done`, `consistency-hints.sh` 는 변경 없음
- 신규 커맨드는 기존 커맨드를 **포함**하는 관계 (대체 아님)
- 사용자가 신규 커맨드 대신 기존 워크플로우를 그대로 써도 무방

---

## 5. 대안 비교

> 각 대안에 대해 채택/기각 사유를 기록. 리뷰 시 "왜 이 옵션은 안 되는가" 를 빠르게 판단할 수 있도록.

| # | 대안 | 장점 | 단점 | 결정 |
|---|------|------|------|------|
| A | Claude 서브에이전트만 사용 | 인프라 0, 병렬 실행 가능 | **같은 모델 패밀리 → 사용자 제약 §2-1 위배** | **기각** |
| B | Codex 플러그인 (`.claude/settings.json` 의 `codex@openai-codex`) | Claude Code UI 통합 | 일반적으로 슬래시 형태라 사용자 입력 대기 → **자동 파이프라인 조립 어려움** | 기각 (단, fallback 카드로 보존) |
| C | MCP 서버로 codex 래핑 | 도구 호출이 first-class | 별도 서버 작성/유지 부담, Bash 호출 대비 이득 미미 | 기각 (과잉) |
| D | 외부 Python/Node 하네스 (Claude Agent SDK + codex subprocess) | 상태 머신/비용 추적 풍부, 양 모델 동등 다룸 | Claude Code IDE UX 상실, 구현 비용 큼 | 기각 (현 단계 과잉) |
| E | GitHub Actions 통합 | CI 와 일원화 | 피드백 루프 느림 (push → 결과 대기), 로컬 반복에 부적합 | 기각 (목적 불일치) |
| F | **Claude Code 슬래시 커맨드 + Bash 로 codex CLI 호출** | 신규 인프라 0, 양 도구 모두 로컬 파일 직접 접근, 출력 캡처 자유, IDE UX 보존 | 슬래시 커맨드 내부에서 출력 파싱/루프 관리 → 복잡도 일부 증가 | **채택** |

### 5-1. 후속 진화 경로 (참고)
F → D 진화는 가능. 하네스가 복잡해지거나 멀티 모델로 확장 시 Python/Node 하네스로 이전. 본 안은 **그 시점이 오기 전까지의 최소 충분 해**.

### 5-2. 조건부 D 재진입 경로 (v2 추가 — F1 / A3 대응)
대안 D 의 기각 사유는 "현 단계 과잉" 인데, 이는 **F (슬래시 커맨드) 가 작동한다는 가정** 위에 성립. Phase 0 의 슬래시 커맨드 실행 모델 검증 (§13 Phase 0) 이 다음 결과를 내면 D 를 다시 검토:
- **검증 결과 A — 슬래시 커맨드가 다단계 게이트/루프/하위 호출을 안정적으로 지원** → F 채택 유지
- **검증 결과 B — 일부 제약 있지만 우회 가능** → F 채택, 우회 방법을 §6 에 명시
- **검증 결과 C — 슬래시 커맨드가 본질적으로 한 번의 프롬프트 확장이라 본 설계 불가능** → **D 재검토 필수**. 본 문서를 v3 로 전면 개정.

이 분기는 §13 Phase 0 의 산출물에 따라 결정.

---

## 6. 상세 설계

### 6-1. 컴포넌트 흐름

```
[사용자] ─ /plan <task-id> ─▶ [Claude Code: 오케스트레이터]
                                   │
                                   ├─ Step 1: /sync 로직 → 다음 task 파악
                                   ├─ Step 2: 계획서 작성 → docs/plans/<task>.md
                                   ├─ Step 3: Bash 호출
                                   │           codex exec --cd $(pwd) <<EOF
                                   │             [프롬프트 + 경로 명시]
                                   │           EOF > /tmp/codex-plan-review-<ts>.json
                                   │                                  │
                                   │                                  ▼
                                   │                       ┌────────────────────┐
                                   │                       │  Codex CLI         │
                                   │                       │  (독립 모델)        │
                                   │                       │   - ADR 직접 읽기   │
                                   │                       │   - 계획서 직접 읽기 │
                                   │                       │   - JSON 출력       │
                                   │                       └────────────────────┘
                                   │                                  │
                                   │       ┌──────── /tmp/codex-plan-review-<ts>.json
                                   │       ▼
                                   ├─ Step 4: JSON 파싱 + 사용자 화면 정형 표
                                   ├─ Step 5: 사용자 게이트 (5분기)
                                   └─ Step 6: 보완 적용 → Step 3 재호출 (최대 3회)
```

### 6-2. 사용자 게이트의 위치 (전체 사이클)

| 게이트 | 위치 | 묻는 내용 |
|--------|------|----------|
| GP-1 | `/plan` 의 ADR 작성 선행 판단 직후 | "ADR 먼저 작성할까요?" |
| GP-2 | `/plan` 의 codex 리뷰 결과 후 (반복 가능) | 리뷰 항목 중 어떤 것을 반영할지 |
| GW-1 | `/work` 의 브랜치 명 제안 후 | "이 브랜치 명으로 생성?" |
| GW-2 | `/work` 의 codex diff 리뷰 후 (반복 가능) | 리뷰 항목 중 어떤 것을 적용할지 |
| GS-1 | `/ship` 의 `consistency-hints.sh` 결과 후 | 깨진 ADR 참조 등 발견 시 진행 여부 |
| GS-2 | `/ship` 의 커밋 분할 미리보기 후 | "이 분할로 커밋?" |
| GS-3 | `/ship` 의 PR 본문 미리보기 후 | "이 본문으로 push + PR?" |

총 7개 게이트. 평균적으로 사이클당 5~7회 사용자 개입 — 기존 8회보다 적고, 결정 가치가 더 높은 지점에 집중.

### 6-3. 슬래시 커맨드별 상세 명세

#### 6-3-1. `/plan [<task-id>]`

**전제**: 없음 (사이클 시작점)
**산출물** (v2 — F3 대응으로 영속화 위치 변경):
- `docs/plans/<task-id>.md` (영구, git 추적)
- `docs/plans/.audit/<task-id>.md` (영구, git 추적, 사용자 결정 audit log — §6-4)
- `docs/plans/<task-id>.state.json` (영구, gitignore — 재개용 상태 — §6-4)
- `.cache/codex-reviews/plan-<task-id>-<ts>.json` (영구, gitignore — raw JSON dump)

**처리 단계**:
1. 인자 파싱: 있으면 그 task, 없으면 `/next` 로 자동 선택
2. `/sync` 로직 실행: 현재 Phase, ADR 상태, 진행 중 task
3. **state 파일 확인** (`docs/plans/<task-id>.state.json`): 존재 시 어느 단계에서 중단됐는지 확인 후 사용자에게 재개 제안
4. ADR 작성 선행 판단: 새 환경/외부 의존성/아키텍처 경계 변경 여부
   - 필요하면 → **GP-1 게이트** → "예" 시 종료, "아니오" 시 진행
5. 계획서 초안 작성 (템플릿은 §10-1 참조)
6. Codex 리뷰 호출 (§7-1 호출 규약)
7. 결과 파싱 후 사용자 표 제시 (§7-3) — 동시에 raw JSON 은 `.cache/...` 에 저장
8. **GP-2 게이트** — 사용자 결정은 `docs/plans/.audit/<task-id>.md` 에 append
9. 선택 항목 계획서에 반영, state 갱신
10. Step 6로 루프 (최대 3회 또는 사용자가 [4]/[5] 선택 시 종료)
11. 종료 시 state 파일에 `stage: "plan.done"` 기록

**중단 후 재개**: `<task-id>.state.json` 의 `stage` 와 `loop_count` 로 재진입 지점 결정

---

#### 6-3-2. `/work`

**전제**: `docs/plans/<task-id>.md` 가 존재, state.json 의 `stage` 가 `plan.done` 이상
**산출물** (v2 변경):
- 새 브랜치 + working tree 변경
- `docs/plans/.audit/<task-id>.md` 에 diff 리뷰 결정 append
- `<task-id>.state.json` 갱신 (stage: `work.review` → `work.done`)
- `.cache/codex-reviews/diff-<task-id>-<ts>.json` (raw JSON)
- `.cache/diffs/diff-<task-id>-<ts>.patch` (diff 백업)

**처리 단계** (v3 — F3/F6 대응):
1. **state 파일 확인**: 진행 중이면 어느 단계에서 멈췄는지 확인. TASKS.md `🔄` 와 교차 검증
2. 브랜치 결정:
   - state 에 branch 정보 있으면 그대로 사용
   - 없으면 브랜치 명 제안 (예: `feat/task-3-4-loadtest`) → **GW-1 게이트** → state 에 기록
3. 계획서 항목 순회하며 구현. 항목 완료 시 state 의 `completed_plan_items[]` 에 append
4. `git diff --stat "$BASE"` 로 변경 규모 보고 (BASE 해석은 Step 5)
5. **diff 캡처** (v3 — F6 대응으로 base branch discovery 명세화):
   ```bash
   # base branch discovery: origin/HEAD → repo config → 환경변수 override → 'main'
   BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
   BASE_BRANCH="${BASE_BRANCH:-$(git config --get peakcart.baseBranch 2>/dev/null)}"
   BASE_BRANCH="${BASE_BRANCH:-${PEAKCART_BASE_BRANCH:-main}}"
   BASE=$(git merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null \
        || git merge-base HEAD "$BASE_BRANCH" 2>/dev/null \
        || echo "$BASE_BRANCH")
   git diff "$BASE" > ".cache/diffs/diff-${TASK_ID}-${TS}.patch"
   ```
   - `git diff <BASE>` 는 working tree (커밋 안 된 변경 포함) vs base 비교 → **첫 구현 직후에도 변경분 캡처 가능**
   - `origin/HEAD` 가 stale 해도 폴백 경로가 있음
6. Codex diff 리뷰 호출 (§7-2 호출 규약, diff 크기 분기는 §7-4)
7. 결과 파싱 후 표 제시 — raw JSON 은 `.cache/...` 에 저장
8. **GW-2 게이트** — 결정은 `docs/plans/.audit/<task-id>.md` 에 append
9. 선택 항목 적용. state 의 `accepted_review_items[]` / `rejected_review_items[]` / `deferred_review_items[]` 로 분리 기록 → Step 6로 루프 (최대 3회)
10. 종료 시 state 파일에 `stage: "work.done"` 기록

**중단 후 재개**: state 의 `stage`, `loop_count`, `completed_plan_items`, `accepted_review_items`, `branch` 로 재진입

> **F3 반영**: 기존 `applied_items` 는 "계획서 항목 진행" 과 "리뷰 항목 수용" 두 의미가 섞여 있어 재개 시 어느 것을 이미 구현했는지 / 어느 리뷰를 수용했는지를 구분할 수 없었음. v3 에서 분리.

---

#### 6-3-3. `/ship`

**전제**: `/work` 완료, working tree 에 변경 존재, state.json 의 `stage` 가 `work.done`
**산출물**:
- 작업별 git 커밋 (여러 개)
- 원격 push (사용자 명시 동의 후)
- GitHub PR
- TASKS/progress/ADR 갱신 (PR 생성 성공 후)

**처리 단계** (v3 — F2 대응으로 state 세분화):
1. **state 파일 확인 + lock**: 다른 세션이 같은 task 진행 중인지 확인 (§6-4 참조). state 의 `ship.*` stage 를 읽어 이어받을 지점 결정 (아래 재진입 표 참조)
2. stage=`ship.precheck`: `bash docs/consistency-hints.sh` 실행 → **GS-1 게이트** (깨진 참조 발견 시) → 통과 시 `ship.partition.previewed` 준비
3. stage=`ship.partition.previewed`: 커밋 분할 제안 (분할 기준은 §10-3) → **GS-2 게이트** 분할 미리보기 확인
4. stage=`ship.commits.created`: 그룹별 `git add <files>` + `git commit` 순차 실행 (`-A` 금지, 파일 명시). 각 커밋 생성 후 sha 를 state 의 `created_commits[]` 에 append. 중단 후 재진입 시 이 배열과 `git log` 를 비교해 **재커밋 방지**
5. PR 본문 생성 (템플릿은 §10-2). `docs/plans/.audit/<task-id>.md` 의 P0 무시 사유가 있으면 본문에 포함 (Q19 의 default — 리뷰에서 결정). 본문을 `.cache/pr-body-${TASK_ID}.md` 에 저장 (PR 생성 실패 시 재사용)
6. **GS-3 게이트**: 본문 미리보기 확인
7. stage=`ship.pushed`: `git push -u origin <branch>`
   - 성공 시 state 의 `push_status: "pushed"`, `remote_branch: "<branch>"` 기록
   - `git push` 가 이미 up-to-date 이면 바로 다음 단계 (멱등)
8. stage=`ship.pr.created`: `gh pr create --body-file .cache/pr-body-${TASK_ID}.md ...`
   - 성공 시 state 의 `pr_url`, `stage: "ship.pr.created"` 기록
   - **실패 ladder** (§7-5 fallback ladder 참조): (a) PR 본문 `.cache/pr-body-*.md` 는 이미 저장돼 있음 → (b) 원인 보고 (인증, API 한도, forge 장애) → (c) 사용자에게 "재시도 / 수동 처리 / 종료" 선택. 자동 재시도 없음
9. stage=`ship.done`: `/done` 로직 실행 (TASKS `🔄`→`✅`, progress, ADR 갱신). 성공 시 state 의 `done_applied: true` 기록
   - 실패 시 사용자에게 보고하고 종료 (TASKS 는 미갱신, PR 은 이미 생성됨 → 다음 호출 시 `/done` 만 재시도)
10. state.json archive (또는 삭제 — Q24)
11. PR URL 반환

**중단 후 재진입 매트릭스**:

| 현재 stage | 확인할 것 | 재진입 지점 |
|-----------|----------|------------|
| `ship.precheck` | — | Step 2 부터 |
| `ship.partition.previewed` | — | Step 3 부터 (분할 재제안 후 GS-2) |
| `ship.commits.created` | `created_commits[]` vs `git log` 교차 확인 | 남은 커밋만 재생성 |
| `ship.pushed` | `git ls-remote origin <branch>` | push 재시도 (이미 up-to-date 면 skip) |
| `ship.pr.created` | `pr_url` 존재 여부 | PR 만 재생성 (`.cache/pr-body-*.md` 재사용) |
| `ship.done` | `done_applied` 플래그 | `/done` 로직만 재시도 |

> **순서의 의미**: `/done` 이 PR 생성 성공 후로 옮겨져 TASKS.md SSOT 는 깨지지 않음. v3 에서는 stage 를 6단계로 세분화해 "어디서 끊겼는지" 가 파일 시스템 상태(커밋/remote/PR)와 **교차 검증 가능**. 이전 v2 는 `ship.commit/ship.pr` 두 단계뿐이라 중복 커밋/중복 push 위험이 있었음 (F2 지적).

---

### 6-4. 상태 영속화 / 재개 / 동시성 (v2 신설 — F3, F8, A1 대응)

**문제**: G3 (감사 흔적 보존) 와 중단 후 재개 모두 영속화된 위치가 필요. 또한 동시 호출 (다른 세션) 방지.

#### 6-4-1. 파일 위치 표

| 파일 | 위치 | git | 수명 | 용도 |
|------|------|-----|------|------|
| 계획서 | `docs/plans/<task-id>.md` | 추적 | 영구 | 계획 본문 |
| 결정 audit log | `docs/plans/.audit/<task-id>.md` | 추적 | 영구 | 매 게이트 사용자 결정 + P0 무시 사유 (G3) |
| state | `docs/plans/<task-id>.state.json` | gitignore | task 완료까지 | 재개용 상태 머신 |
| lock | `docs/plans/<task-id>.lock` | gitignore | 슬래시 커맨드 실행 중만 | 동시 호출 방지 |
| raw 리뷰 JSON | `.cache/codex-reviews/{plan,diff}-<task-id>-<ts>.json` | gitignore | 영구 (수동 정리 전까지) | 감사 / 디버깅 |
| diff 백업 | `.cache/diffs/diff-<task-id>-<ts>.patch` | gitignore | 영구 | 디버깅 |

`.gitignore` 에 다음 추가 필요:
```
docs/plans/*.state.json
docs/plans/*.lock
.cache/
```

#### 6-4-2. state.json 스키마

```json
{
  "task_id": "task-3-4",
  "stage": "work.review",
  "loop_count": 2,
  "completed_plan_items": [1, 2],
  "accepted_review_items": [1, 3],
  "rejected_review_items": [2],
  "deferred_review_items": [4],
  "branch": "feat/task-3-4-loadtest",
  "created_commits": [],
  "push_status": null,
  "remote_branch": null,
  "pr_url": null,
  "done_applied": false,
  "last_diff_path": ".cache/diffs/diff-task-3-4-1745000000.patch",
  "last_review_path": ".cache/codex-reviews/diff-task-3-4-1745000000.json",
  "started_at": "2026-04-18T10:00:00Z",
  "updated_at": "2026-04-18T10:30:00Z"
}
```

`stage` 가능 값 (v3 — F2/F3 반영):
- `plan.draft` → `plan.review` → `plan.done`
- `work.impl` → `work.review` → `work.done`
- `ship.precheck` → `ship.partition.previewed` → `ship.commits.created` → `ship.pushed` → `ship.pr.created` → `ship.done` (이후 archive)

필드 의미 (v3 신규/분리):
- `completed_plan_items[]`: 계획서 §2 체크리스트 중 구현 완료 항목 번호
- `accepted_review_items[]`: Codex 리뷰 항목 중 수용해 반영한 것
- `rejected_review_items[]`: 명시적으로 거부한 것 (audit log 에 사유)
- `deferred_review_items[]`: "다음 task 로 미룸" 등 연기 결정 항목
- `created_commits[]`: `/ship` 에서 생성한 커밋 sha 배열 (중복 커밋 방지)
- `push_status`: `null` | `"pushed"` | `"failed"` (원격 반영 여부)
- `remote_branch`: push 성공 시 원격 브랜치 명 (ls-remote 로 검증 가능)
- `pr_url`: PR 생성 성공 시 URL. 미생성이면 `null`
- `done_applied`: `/done` 로직 (TASKS/progress/ADR 갱신) 실행 완료 여부

#### 6-4-3. review.md 형식 (audit log)

매 게이트 결정마다 append:
```markdown
## 2026-04-18 14:23 — GP-2 (loop 1)
- 리뷰 항목: 3건 (P0:1, P1:1, P2:1)
- 사용자 선택: [1] P0/P1만 반영 (1, 2)
- raw: .cache/codex-reviews/plan-task-3-4-1745000000.json

## 2026-04-18 14:30 — GP-2 (loop 2)
- 리뷰 항목: 1건 (P2:1)
- 사용자 선택: [4] 무시
- raw: .cache/codex-reviews/plan-task-3-4-1745001000.json

## 2026-04-18 16:10 — GW-2 (loop 1)
- 리뷰 항목: 5건 (P0:1, P1:2, P2:2)
- 사용자 선택: [3] 1,2,4
- P0 무시 (3번): "본 task 범위 밖 — 별도 task 로 분리"
- raw: .cache/codex-reviews/diff-task-3-4-1745005000.json
```

#### 6-4-4. 동시성 제어 (lock) — v3 원자성 보강 (F5 대응)

**문제**: `[ -f $LOCK ] + echo $$ > $LOCK` 은 두 단계 사이 race — 두 세션이 동시에 확인 단계를 통과하면 둘 다 lock 획득. 이를 `mkdir` 의 원자성으로 해결.

```bash
LOCK_DIR="docs/plans/<task-id>.lock"   # 디렉토리 기반 lock (파일 아님)
PID_FILE="$LOCK_DIR/pid"

# mkdir 은 원자적: 디렉토리가 이미 있으면 실패
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # stale 검사: 내부 pid 가 살아있는지 확인
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "다른 세션이 진행 중 (pid=$PID). 중단 후 재시도하세요."
      exit 1
    fi
  fi
  echo "이전 세션의 stale lock 발견 (pid=${PID:-unknown}). 제거 후 재시도합니다."
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || { echo "lock 재획득 실패"; exit 1; }
fi
echo $$ > "$PID_FILE"
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
```

> v2 의 `[ -f ] + echo >` 는 **TOCTOU (time-of-check to time-of-use)** race 가 있음. `mkdir` 은 커널이 원자성 보장. stale 처리는 별도로 내부 pid 파일로 판단 후 재획득.
>
> 단일 사용자 전제에서는 race 가 드물지만, 터미널 두 개에서 실수로 동시 호출하는 흔한 경우를 막기 위해 필요. 더 강한 보장 (NFS 등) 이 필요하면 `flock(1)` 검토 (macOS 기본 미포함).

#### 6-4-5. archive 정책

`/ship` 성공 후:
- state.json → `docs/plans/.archive/<task-id>.state.json` 으로 이동 (또는 삭제 — Q24 에서 결정)
- `docs/plans/.audit/<task-id>.md` 는 그대로 유지 (영구 audit)
- `.cache/` 는 자동 정리 X (사용자가 디스크 압박 시 수동 정리)

---

## 7. Codex 호출 규약 (계약)

### 7-1. 입력 프로토콜 (계획 리뷰)

(v3 — F4 대응으로 heredoc quoting 통일 + §7-2 와 변수 주입 방식 일치)

```bash
TS=$(date +%s)
TASK_ID="<task-id>"   # 실제 호출부에서 주입
mkdir -p .cache/codex-reviews

# F7: timeout 명령 portability
if command -v timeout >/dev/null; then T="timeout 60"
elif command -v gtimeout >/dev/null; then T="gtimeout 60"
else T=""  # 없으면 사용자에게 경고 출력 후 무한 대기
fi

# heredoc 은 quote 없이 (unquoted EOF) — ${TASK_ID} 등 변수 치환 허용
# 문서 내 placeholder 가 실제 경로로 확장되어야 codex 가 파일을 읽을 수 있음
$T codex exec --cd "$(pwd)" <<EOF > ".cache/codex-reviews/plan-${TASK_ID}-${TS}.json"
[역할] PeakCart 프로젝트의 시니어 아키텍처 리뷰어
[참조 가능 파일] docs/adr/, docs/01-project-overview.md ~ docs/07-roadmap-portfolio.md
[원칙]
  - Layer 1 = What, ADR = Why (결정 근거는 ADR 인용)
  - Phase Exit Criteria 와의 정합성 우선
  - 추측 금지. 파일을 직접 읽고 인용
[ADR 인덱스 핵심] (A2 대응 inline 주입)
  - ADR-0001: 4-Layered + DDD
  - ADR-0002: 모놀리식 → MSA 단계적 진화
  - ADR-0004: Phase 3 GCP/GKE 전환 (Accepted)
  - ADR-0005: Kustomize base/overlays (Partially Superseded)
  - ADR-0006: Monitoring 스택 환경 분리
  - ADR-0007: YAML 프로파일 병합 원칙
  (전체 인덱스: docs/adr/README.md)
[리뷰 대상] docs/plans/${TASK_ID}.md
[체크 항목]
  - ADR 결정과의 충돌
  - 누락된 작업 항목 (테스트, 마이그레이션, 문서)
  - 트레이드오프 누락
  - 검증 방법의 구체성
[출력 형식] 아래 JSON 스키마. 다른 텍스트/주석 금지.
[스키마] (§7-3 참조)
EOF
```

> **F4 수정 핵심**: v2 는 `<<'EOF'` (quoted) 였는데, quote 가 있으면 변수 치환이 차단돼 본문의 `<TASK_ID>` 가 placeholder 그대로 전달됨 → codex 가 존재하지 않는 파일을 찾게 됨. v3 는 `<<EOF` (unquoted) 로 통일해 `${TASK_ID}` 로 실제 경로를 주입. §7-2 와도 일관.

### 7-2. 입력 프로토콜 (diff 리뷰)

(v3 — F6 base branch discovery 명세화 + $T 정의 추가 + §7-1 과 일관)

```bash
TS=$(date +%s)
TASK_ID="<task-id>"
mkdir -p .cache/codex-reviews .cache/diffs

# F7: timeout portability (§7-1 과 동일)
if command -v timeout >/dev/null; then T="timeout 60"
elif command -v gtimeout >/dev/null; then T="gtimeout 60"
else T=""
fi

# F6: base branch discovery (§6-3-2 Step 5 와 동일)
BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
BASE_BRANCH="${BASE_BRANCH:-$(git config --get peakcart.baseBranch 2>/dev/null)}"
BASE_BRANCH="${BASE_BRANCH:-${PEAKCART_BASE_BRANCH:-main}}"
BASE=$(git merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null \
     || git merge-base HEAD "$BASE_BRANCH" 2>/dev/null \
     || echo "$BASE_BRANCH")

DIFF_PATH=".cache/diffs/diff-${TASK_ID}-${TS}.patch"
git diff "$BASE" > "$DIFF_PATH"

# diff 비어 있으면 호출 자체를 스킵
if [ ! -s "$DIFF_PATH" ]; then
  echo "변경사항이 없습니다. 구현 후 다시 호출하세요."
  exit 0
fi

$T codex exec --cd "$(pwd)" <<EOF > ".cache/codex-reviews/diff-${TASK_ID}-${TS}.json"
[역할] PeakCart 프로젝트의 시니어 코드 리뷰어
[참조 가능 파일] ${DIFF_PATH}, docs/plans/${TASK_ID}.md, docs/adr/
[체크 항목]
  - 계획서 의도와의 일치
  - 버그, race condition, null/empty 처리
  - 시큐리티 (입력 검증, 권한, 시크릿 노출)
  - 테스트 커버리지
  - 컨벤션 (네이밍, 패키지 위치)
[ADR 인덱스 핵심] (§7-1 동일 inline 주입)
[출력 형식] (§7-3 참조)
EOF
```

> **F2 수정 핵심** (v2 에서 유지): 기존 `git diff main...HEAD` 는 "main 과 HEAD 의 공통 조상부터 HEAD 까지 커밋된 변경" 만 잡음. 첫 구현 직후 working tree 만 수정된 상태에선 빈 결과. 변경된 `git diff "$BASE"` 는 working tree 변경 + 미커밋 + 미스테이징 모두 포함.
>
> **F6 수정 핵심** (v3 신규): v2 는 `origin/main` 하드코딩. main 이 아니거나 (master, develop 등) origin/HEAD 가 stale 하면 diff 자체가 잘못됨. v3 는 origin/HEAD → git config (`peakcart.baseBranch`) → 환경변수 (`PEAKCART_BASE_BRANCH`) → 폴백 'main' 순서로 발견.

### 7-3. 출력 프로토콜 (강제 JSON 스키마)
```json
{
  "summary": "한 줄 종합 코멘트",
  "items": [
    {
      "id": 1,
      "severity": "P0",
      "category": "architecture",
      "file": "src/main/java/.../OrderService.java",
      "line": 42,
      "finding": "재고 차감과 결제 호출이 같은 트랜잭션 안",
      "suggestion": "결제 호출 트랜잭션 분리 + Outbox (ADR-0007)"
    }
  ]
}
```

| 필드 | 필수 | 값 |
|------|------|------|
| `summary` | ✓ | 1줄 |
| `items[].id` | ✓ | 정수 (사용자 선택용) |
| `items[].severity` | ✓ | `P0` (머지 차단) / `P1` (강력 권고) / `P2` (nit) |
| `items[].category` | ✓ | `architecture` / `bug` / `security` / `test` / `doc` / `style` / `convention` |
| `items[].file` | diff 리뷰만 | 경로 |
| `items[].line` | diff 리뷰만 | 정수 |
| `items[].finding` | ✓ | 1~2줄 |
| `items[].suggestion` | ✓ | 1~2줄, ADR/문서 인용 권장 |

### 7-4. diff 크기 분기 (`/work` 의 codex 호출)
| diff 크기 | 처리 |
|-----------|------|
| ~500줄 | 단일 호출, 전체 리뷰 |
| 500~2000줄 | 사용자에게 "파일별 분할 리뷰?" 확인 후 분할 (각 파일별 1회 호출) |
| 2000줄+ | "task 가 너무 큽니다. 분할 검토 권장" 안내, 그래도 진행하면 단계 분할 |

### 7-5. Fallback Ladder (v3 — F8 대응으로 운영 가능 수준으로 확장)

"운영 가능" 이란 실패 시 사용자에게 "어떻게 할까요?" 만 던지는 게 아니라 **표준 복구 경로**가 있는 것. 모든 ladder 는 (a) 실패 감지 → (b) 자동 복구 시도 → (c) 여전히 실패 시 사용자 개입의 3단.

#### 7-5-A. JSON 파싱 실패 ladder
1. **재파싱**: 출력이 ```json ... ``` 블록으로 감싸졌을 가능성 → 코드블록만 추출해 재파싱 1회
2. **raw 요약**: 그래도 실패 시 raw 출력 앞 3KB 만 사용자에게 제시, 전체는 `.cache/codex-reviews/*.raw.txt` 에 저장
3. **자연어 게이트**: 사용자가 "1, 3번만 반영" 같이 지시 → Claude 가 해석
4. **다음 호출 강화**: 다음 프롬프트 맨 앞에 `[이전 출력이 JSON 이 아니었음. JSON 스키마 외 텍스트 금지]` 삽입
5. **연속 2회 실패** → §7-7 임계치 발동

#### 7-5-B. Codex timeout ladder
1. **1회 timeout**: 경고만 표시, 재호출
2. **2회 timeout**: diff 가 큰지 확인 (`wc -l`). 500줄 초과면 §7-4 분할 제안
3. **3회 timeout** → `review skip mode`: 리뷰 없이 GW-2/GP-2 게이트로 직행, 사용자에게 "codex 응답 없음. 리뷰 건너뛰고 진행?" 확인. audit log 에 `review_skipped: timeout` 기록

#### 7-5-C. Push 실패 ladder (`/ship` Step 7)
1. **감지**: `git push` exit code ≠ 0
2. **분류**:
   - `fetch first` / non-fast-forward → `git fetch origin` 후 사용자에게 rebase 여부 확인 (자동 rebase X)
   - auth failure → 사용자에게 인증 갱신 요청, 자동 재시도 X
   - network → 30초 후 1회 재시도
3. 실패 상태 state 에 `push_status: "failed"` 기록 → 다음 호출 시 Step 7 부터 재진입

#### 7-5-D. PR 생성 실패 ladder (`/ship` Step 8)
1. **본문 보존**: PR 본문은 이미 Step 5 에서 `.cache/pr-body-${TASK_ID}.md` 에 저장됨 → 재시도 시 재사용 (재생성 금지)
2. **분류**:
   - `gh auth` 만료 → 사용자에게 `gh auth login` 안내 + 재시도 선택
   - API rate limit → `Retry-After` 헤더 확인 후 대기 시간 고지, 수동 재시도
   - 네트워크/5xx → 60초 후 1회 재시도
3. 재시도 시 `gh pr create --body-file .cache/pr-body-${TASK_ID}.md` 로 동일 본문 유지
4. 3회 실패 시 사용자에게 "수동 PR 생성 안내 (본문 파일 경로 제시) / 종료" 선택. TASKS 는 미갱신

#### 7-5-E. Consistency-hints 실패 ladder (`/ship` Step 2 / GS-1)
1. 깨진 참조 목록 제시
2. 사용자 선택: (a) 지금 수정 (편집 후 재실행) / (b) 무시하고 진행 (사유 필수 입력) / (c) 종료
3. (b) 선택 시 사유는 audit log 에 append, PR 본문에 "Skipped consistency checks" 섹션 자동 추가

### 7-6. 비용/빈도 제어 (v2 — F6 / N4 fallback 보강)
- 한 슬래시 커맨드 내 codex 호출 상한: **3회**
- 상한 도달 시 사용자에게 "더 호출할까요?" 명시 확인
- **비용 측정**:
  - **1순위**: codex CLI stdout/stderr 의 토큰/비용 metadata 파싱
  - **fallback** (CLI 미노출 시) — 프록시 지표 자동 기록:
    - 호출 수
    - 입력 byte (heredoc 본문 + diff/계획서 파일 크기)
    - 입력 lines (diff 줄 수)
    - 출력 byte (응답 JSON 크기)
    - 응답 시간 (초)
  - 호출별 1줄 로그를 `.cache/codex-reviews/_metrics.tsv` 에 append
- 큰 diff 분할로 호출 횟수 부풀리는 것 회피 — "task 분할" 신호로 해석

### 7-7. 실패 임계치 (v2 신설 — A4 대응)
codex 가 연속 실패 시 정책:
- **연속 2회 JSON 위반** → 다음 호출 시 프롬프트 강화 (§7-5 fallback)
- **연속 3회 무내용 응답** ("괜찮아 보입니다" 등 finding 0건이지만 P0 후보가 명백한 경우) → 사용자에게 "codex 가 무내용 응답 반복 중. 강제 종료할까요?" 확인
- **연속 3회 timeout** → 자동 중단 + 사용자에게 "codex 응답 지연. 호출 스킵하고 게이트로 진행할까요?" 확인

### 7-8. 컨텍스트 주입 원칙 (모든 codex 호출 공통)
- 한국어로 답변 강제
- 추측 금지, 파일 경로/라인 명시
- ADR 우선 (Why 는 ADR 에 있음)
- "괜찮아 보입니다" 같은 무내용 응답 금지

---

## 8. 사용자 게이트 UX

### 8-1. 리뷰 결과 제시 형식 (예시)
```
=== Codex 리뷰 결과 — 계획서 (3건) ===

요약: ADR-0007 위배 1건, 누락 1건, 컨벤션 1건

[P0] 1건 — 머지 차단
  1. docs/plans/task-3-4.md:23
     finding:    재고 차감과 결제가 같은 트랜잭션
     suggestion: 결제 호출 분리 + Outbox (ADR-0007)

[P1] 1건 — 강력 권고
  2. docs/plans/task-3-4.md:15
     finding:    k6 도입 시 D-004 영향 누락
     suggestion: loadtest-tool-evaluation.md §3-4 참조

[P2] 1건 — nit
  3. naming: scenarioC → scenario_c

────────────────────────────────────────
어떻게 처리할까요?
  [1] P0/P1만 반영 (1, 2)
  [2] 전체 반영 (1, 2, 3)
  [3] 항목 선택 (예: "1,3")
  [4] 다 무시하고 진행
  [5] 종료 (지금까지 작업만 보존)
>
```

### 8-2. 가독성 원칙
- severity 별 그룹핑, P0 먼저
- file:line 항상 명시
- finding/suggestion 각 1~2줄, 길면 잘라서 "더 보기"
- 항목 번호로만 선택 (자연어 X)

### 8-3. "ㅇㅋ 자동화" 방지
- 기본 선택지는 [1] (P0/P1 만 반영) — 가장 안전한 기본
- "전체 반영" 은 default 가 아님
- P0 가 1건 이상인데 [4] 무시 선택 시:
  > "P0 1건이 있는데 정말 무시하고 진행할까요? 사유를 1줄로 입력해주세요."
- 입력된 사유는 `docs/plans/.audit/<task-id>.md` 에 append (영구 audit, §6-4-3)

---

## 9. 위험 요소 / 트레이드오프

### 9-1. 식별된 위험 (v2 — R10~R12 추가, R5/R9 보강)

| ID | 위험 | 발생 가능성 | 영향 | 대응 |
|----|------|------------|------|------|
| R1 | codex CLI non-interactive 모드가 안정적이지 않음 | 중 | **자동화 자체 불가** | Phase 0 검증 필수, 안 되면 대안 B (플러그인) fallback. §5-2 D 재진입 경로 |
| R2 | codex 출력 형식 불안정 (JSON 안 지킴) | 중~높 | 파싱 실패 빈발 | §7-5 fallback (raw 제시) + 프롬프트 보강 + §7-7 임계치 |
| R3 | codex API 비용 폭증 | 낮~중 | 운영비 부담 | 호출 상한 3회 + 사용자 게이트 + 프록시 지표 (§7-6) + 베이스라인 측정 (Phase 4) |
| R4 | 큰 diff 컨텍스트 초과 | 중 | 리뷰 실패 | §7-4 분할 처리 |
| R5 | 자동화로 사용자 검토 소홀 | 높 | **품질 저하 (가장 큰 비기능적 위험)** | §8-3 ㅇㅋ 방지 장치 + 게이트 default 안전 + G1b 별도 측정으로 가시화 |
| R6 | codex 가 ADR/Layer 1 컨벤션 모름 | 중 | 부적절한 지적 양산 | §7-8 프롬프트 원칙 + §7-1 ADR 인덱스 inline 주입 |
| R7 | Bash 출력 캡처가 길어 Claude 컨텍스트 오염 | 중 | 후속 응답 품질 저하 | JSON 출력은 파일로 받고 필요한 부분만 Read |
| R8 | 슬래시 커맨드 내부 로직이 복잡해져 유지보수 부담 | 중 | 장기적 부채 | 커맨드 1개당 200줄 이내 유지, 공통 로직은 별도 스크립트로 분리 |
| R9 | 중단 후 재개 시 상태 오추정 | 낮~중 | 작업 누락/중복 | §6-4 state 파일 + TASKS `🔄` + plan 파일 3중 교차 검증 |
| **R10** | **다른 세션에서 동시 실행** (예: 사용자가 두 터미널에서 `/work` 호출) | 낮 | 브랜치/state 충돌, 산출물 손상 | §6-4-4 lock **디렉토리** (mkdir 원자성, v3 F5 반영). PID 기반 stale 처리 |
| **R13** | `/ship` 재개 시 중복 커밋/중복 push (v3 F2) | 중 | 브랜치 히스토리 오염, PR 충돌 | §6-3-3 stage 6단 세분화 + `created_commits[]`/`push_status`/`pr_url` 로 재진입 매트릭스 |
| **R14** | base branch 가 `main` 이 아니거나 origin/HEAD 가 stale (v3 F6) | 낮~중 | diff 자체가 잘못됨 → 리뷰 오류 | §7-2 base branch discovery 4단 폴백 |
| **R15** | 슬래시 커맨드 heredoc quoting 오류로 placeholder 미치환 (v3 F4) | 중 | codex 가 존재하지 않는 파일 탐색 → 무내용 응답 | §7-1 `<<EOF` (unquoted) 로 통일, `${TASK_ID}` 주입 |
| **R11** | **codex 가 매 호출마다 ADR 컨벤션 zero 에서 시작** | 높 | 부적절한 지적, 일관성 결여 | §7-1 ADR 인덱스 inline 주입 (R6 와 짝). 부족 시 핵심 ADR 본문도 inline |
| **R12** | **F1 (슬래시 커맨드 실행 모델) 가정 오류** | **중~높** | **본 설계 전면 재검토** | §13 Phase 0 최우선 검증 + §5-2 D 재진입 경로 사전 정의 |

### 9-2. 의도적으로 감수하는 트레이드오프 (v2 — `/tmp` 항목 삭제)
- **모델 다양성을 Codex 1개에 한정** — Gemini 등 추가 안 함. 2축으로 충분한지는 Phase 4 후 평가
- **`.cache/` 자동 정리 없음** — 디스크 압박 시 사용자가 수동 정리 (자동 정리는 감사 흔적 손실 위험)
- **에러 시 자동 복구 없음** — 모든 에러는 사용자에게 던지고 재시도 결정 위임. 자동 재시도 → 비용/혼란 위험
- **lock 이 PID 기반 단순 구현** — 강한 보장은 `flock(1)` 필요하나 macOS 기본 미포함. 단일 사용자 전제에서 충분

---

## 10. 산출물 템플릿 / 컨벤션

### 10-1. 계획서 템플릿 (`docs/plans/<task-id>.md`)
```markdown
# <Task-ID>: <Task 제목>

> 작성: YYYY-MM-DD
> 관련 Phase: Phase N
> 관련 ADR: ADR-NNNN (있으면)

## 1. 목표
> 이 task 가 무엇을 달성하려 하는가 (1~2문단)

## 2. 작업 항목
- [ ] 항목 1
- [ ] 항목 2
...

## 3. 영향 파일
| 파일 | 종류 (신규/수정/삭제) | 변경 요지 |
|------|---------------------|----------|
| ... | ... | ... |

## 4. 검증 방법
- 단위 테스트:
- 통합 테스트:
- 수동 검증:

## 5. 트레이드오프 / 대안
> 검토했지만 선택하지 않은 대안과 사유

## 6. ADR 영향
> Proposed → Accepted 전환, Superseded 발생 등

## 7. 비고
```

### 10-2. PR 본문 템플릿
```markdown
## Why
> 이 변경이 왜 필요한가 (배경, 동기). 관련 Issue/Task 링크.

## What
> 무엇을 바꿨는가 (1줄 요약 + bullet)

## How
> 어떻게 구현했는가. 핵심 결정과 그 근거 (ADR 인용).

## Test plan
- [ ] 단위 테스트
- [ ] 통합 테스트
- [ ] 수동 확인 시나리오

## 관련
- Task: docs/TASKS.md §...
- Plan: docs/plans/<task-id>.md
- ADR: ADR-NNNN
```

### 10-3. 커밋 분할 기준
| 분류 | 패턴 | 예 |
|------|------|------|
| feat | 비즈니스 로직 추가 | `feat(order): 결제 타임아웃 스케줄러 추가` |
| fix | 버그 수정 | `fix(payment): 환불 시 재고 복구 누락` |
| refactor | 동작 변화 없는 구조 변경 | `refactor(common): 응답 포맷 단순화` |
| test | 테스트만 변경 | `test(order): 동시성 시나리오 추가` |
| docs | 문서만 변경 | `docs(adr): ADR-0008 작성` |
| chore | 빌드/설정 | `chore(gradle): 의존성 업데이트` |

분할 원칙:
- 한 커밋은 한 분류 (mixed 금지)
- 한 커밋이 100파일 이상 → 분할 재제안
- ADR/계획서 변경은 별도 커밋

---

## 11. Open Questions / 결정 필요 사항

> 본 문서가 합의되기 전 답해야 하는 질문들. 리뷰 시 이 절을 먼저 채워주세요.
> **v2 변경**: F1 대응으로 §11-0 (슬래시 커맨드 실행 모델) 을 §11-1 (Codex CLI 명세) 보다 앞에 신설. 우선순위 재정렬.
> **v3 변경**: §11-10 신설 (Q26~Q28), §11-7 드리프트 정리 (F12), §11-9 Q25 에 v3 default 명시.

### 11-0. 슬래시 커맨드 실행 모델 (v2 신설 — **최우선, F1 대응**)
본 설계의 핵심 가정은 "슬래시 커맨드가 다단계 게이트 / 루프 / 하위 커맨드 호출을 지원한다" 인데, 이 가정 자체가 검증되지 않음. Codex CLI 명세보다 **이 검증이 먼저** 되어야 §3~6 의 대부분이 의미 있음.

- **Q0-1**. 슬래시 커맨드는 본질적으로 마크다운 → 프롬프트 확장인가, 아니면 다단계 흐름 제어가 가능한가?
- **Q0-2**. 슬래시 커맨드 안에서 사용자 입력을 여러 번 받고 그 사이 상태를 유지할 수 있는가? (대화 컨텍스트로 유지되는 것은 OK)
- **Q0-3**. 슬래시 커맨드 안에서 다른 슬래시 커맨드를 호출할 수 있는가? (`/plan` 안에서 `/sync` 호출 등) 또는 그 로직을 인라인 복제해야 하는가?
- **Q0-4**. 한 슬래시 커맨드 실행 도중 사용자가 자유 메시지를 보내면 어떻게 동작하는가? (인터럽트, 무시, 큐잉?)
- **Q0-5**. Bash 호출의 stdout/stderr 가 길 경우 Claude 컨텍스트에 어떻게 들어오는가? 자동 truncation 정책?

> **결과에 따라**: Q0-1~3 가 모두 "가능" → F 채택 유지. 일부 제약 있으면 §6 우회안 추가. 본질적 불가능이면 §5-2 의 D 재진입 (외부 하네스).

### 11-1. Codex CLI 명세 (필수)
- Q1. `codex exec` 가 실제 서브커맨드인가? 아니면 다른 형태인가? (`codex chat`, `codex` 단독 + stdin, etc.)
- Q2. non-interactive 모드 플래그는 무엇인가?
- Q3. 작업 디렉토리 지정 방법은? (`--cd`, `-C`, env var, etc.)
- Q4. 인증 방식은? (`OPENAI_API_KEY` env / config 파일 / login 세션)
- Q5. JSON 출력 강제가 안정적인가? (5회 호출 시 성공률)
- Q6. 토큰/비용 정보가 stdout/stderr 에 노출되는가?

### 11-2. 계획서 템플릿 (§10-1)
- Q7. 7개 섹션이 충분한가? 빠진 게 있는가?
- Q8. ADR 영향 섹션을 별도로 둘 가치가 있는가, 1번에 포함시킬까?

### 11-3. 브랜치 명 컨벤션
- Q9. PeakCart 의 기존 git log 컨벤션은? (`git log --oneline -20` 결과 필요)
- Q10. `feat/task-N-N-<slug>` 형식으로 통일할까, 자유 형식 유지할까?

### 11-4. PR 본문 톤
- Q11. 기존 PR 1~2개 샘플 — 한국어/영어 비율, 격식 수준
- Q12. 이모지/체크리스트 스타일 선호도
- Q13. "리뷰어 친화적" 의 구체적 정의 (Why 우선? Test plan 필수?)

### 11-5. 비용 / 운영
- Q14. codex API 월 예산 한도가 있는가?
- Q15. 한 사이클 평균 비용이 X 이상이면 자동 차단할까, 사용자 확인할까?

### 11-6. 게이트 UX
- Q16. §8-1 의 5분기 선택지가 적정한가? 더 단순화 (3분기) / 세분화?
- Q17. P0 무시 시 사유 입력을 강제하는 것이 부담인가?

### 11-7. 산출물 영속성
- Q18. `.cache/codex-reviews/*.json` raw dump 를 git 영구 저장할 가치가 있는가? (현 default: gitignore)
- Q19. P0 무시 사유 (audit log `docs/plans/.audit/<task-id>.md` 의 해당 엔트리) 를 PR 본문에 자동 포함할까? (§6-3-3 Step 5 default: 포함)

### 11-8. fallback 시나리오
- Q20. R1 (codex non-interactive 안정성 부족) 발생 시 어디까지 후퇴할까? — 플러그인 모드 / 외부 하네스 / 본 안 폐기

### 11-9. v2 신설 — 추가 의사결정 항목
- **Q21** (A2). codex 호출 시 ADR 인덱스를 inline 주입하는 것 (§7-1) 이 충분한가, 아니면 핵심 ADR 본문 (예: ADR-0007) 도 매번 inline 으로 박아야 하는가? 비용/품질 트레이드오프.
- **Q22** (A4). codex 가 연속 3회 무내용 응답 시 자동 fallback 정책 (§7-7) 이 적정한가? 더 엄격 (1회) / 더 관대 (5회) ?
- **Q23** (A1 / R10). 동시성 lock (§6-4-4) 을 PID 기반 단순 구현으로 충분한가? 단일 사용자 전제가 깨지는 시나리오가 있는가?
- **Q24**. `/ship` 성공 후 state.json 처리 — `docs/plans/.archive/` 로 이동 vs 즉시 삭제? archive 의 장기 가치는?
- **Q25** (F4 보강). `/done` 을 PR 생성 성공 후로 옮긴 결과, push 는 됐지만 PR 생성이 실패한 경우 (예: gh CLI 인증 만료) 의 처리 — 자동 재시도 vs 사용자에게 수동 처리 위임? (v3 §7-5-D 에서 "수동 재시도 + 본문 재사용" default)

### 11-10. v3 신설 — 리뷰 2차 반영 후 추가 항목
- **Q26** (F7 / 게이트 피로). 게이트를 "항상 필요한 승인" (GW-1 브랜치명, GS-3 PR 본문 등 되돌릴 수 없는 행동 직전) 과 "이상 시에만 개입" (GS-1 consistency hints — 문제 없으면 자동 통과) 으로 분리할까? 분리 시 평상시 decision prompt 수가 절반 수준으로 줄어들지만, "자동 통과" 가 R5 (ㅇㅋ 자동화) 와 충돌할 수 있음.
- **Q27** (F2 보강). `/ship` 재진입 시 `created_commits[]` 와 `git log` 비교로 중복 커밋을 방지하는데, 사용자가 중간에 수동으로 amend/rebase 한 경우 sha 불일치 감지 후 어떻게 처리할까? — 자동 재계산 vs 사용자 확인.
- **Q28** (F9~F11 / 범용화 보류). 본 안은 PeakCart 전용 reference design. Phase 4 end-to-end 검증 후 다음 프로젝트 적용 시점이 오면 (a) 현 문서를 복제해 fork / (b) Core + Adapter + Profile 로 재구조화 중 어느 쪽이 합리적인가? — 지금 결정하지 않고 **DEFERRED** (§3-3 에 추가).

---

## 12. 검증 계획

### 12-1. 단계별 검증 (v2 — Phase 0 에 슬래시 커맨드 실행 모델 검증 추가)
| Phase | 내용 | 성공 기준 |
|-------|------|----------|
| **0a** (신설) | **슬래시 커맨드 실행 모델 검증** | §11-0 의 Q0-1~Q0-5 답변 확보. 다단계 게이트 가능 여부 명확화 |
| 0b | codex CLI 명세 확정 | §11-1 의 Q1~Q6 답변 확보 + JSON 강제 5회 호출 성공률 측정 |
| 0c | macOS 도구 portability 확인 | `timeout`/`gtimeout` 존재 여부, fallback 패턴 검증 |
| 1 | `/plan` 단독 검증 | 가짜 task 1개로 한 사이클, 산출물 존재/형식 확인, state.json 정합 |
| 2 | `/work` 단독 검증 | 작은 실제 task 로 branch + diff (`git diff $BASE`) + 리뷰 + 재개 시뮬레이션 |
| 3 | `/ship` 단독 검증 | 위 결과를 커밋/PR 까지, PR URL 반환, /done 이 PR 성공 후에만 동작하는지 확인 |
| 4 | end-to-end | 실제 다음 Phase 3 task 1개로 전체 사이클 |
| 5 (선택) | 안정화 | 1주일 사용 후 회고, 프롬프트/게이트 조정 |

> **Phase 0a 가 결과 C (실행 모델 본질적 불가능)** 이면 §13 의 Phase 1 이후 모두 무효. v3 로 전면 재설계 (§5-2 D 재진입).

### 12-2. 회귀 검증
기존 `/sync`, `/next`, `/done` 단독 호출 각 1회 정상 동작 확인.

### 12-3. 정량 측정 항목 (v2 — F5 KPI 분리 + F6 프록시 지표)

**사용자 부담 지표** (G1 분할 측정):
| 지표 | 측정 방법 | 목표 |
|------|----------|------|
| **invocation 수** (G1a) | `/plan`, `/work`, `/ship` 호출 카운트 | **8 → 3** |
| **decision prompt 수** (G1b) | 게이트 응답 카운트 (audit log 줄 수) | 베이스라인 측정 후 결정 (현 추정 5~7) |
| **context switch 수** (G1c) | 사용자가 Claude ↔ Codex 도구 사이 전환 (사용자 직접 카운트) | **0** |
| **복붙 수** (G2) | 사용자 직접 카운트 | **0** |

**시스템 품질 지표**:
| 지표 | 측정 방법 | 목표 |
|------|----------|------|
| JSON 파싱 실패율 | 호출 10회당 실패 수 | < 10% |
| 사이클당 codex 호출 수 | `.cache/codex-reviews/` 파일 수 | ≤ 3 (게이트 무시 시 fallback 호출 제외) |
| 사이클 총 소요 시간 | 시작~PR URL 시각차 | 베이스라인 측정 |
| 무내용 응답률 | items 가 0건이면서 실제 P0 후보가 있던 경우 | < 10% |

**비용 지표** (1순위 → fallback):
| 지표 | 측정 방법 | 비고 |
|------|----------|------|
| 토큰 수 | codex CLI metadata (있을 시) | 1순위 |
| API 비용 | codex CLI metadata (있을 시) | 1순위 |
| 입력 byte | heredoc + 참조 파일 크기 합 | fallback 프록시 |
| 입력 lines | diff 줄 수 | fallback 프록시 |
| 출력 byte | 응답 JSON 파일 크기 | fallback 프록시 |
| 응답 시간 | wall clock | 항상 측정 |

모든 측정값은 호출별 1줄로 `.cache/codex-reviews/_metrics.tsv` 에 append.

### 12-4. 정성 평가 항목
- 사용자가 매 게이트마다 의식적으로 결정했는가 ("ㅇㅋ" 함정 회피 정도)
- 리뷰 품질 — codex 가 무내용 응답을 얼마나 자주 했는가
- 산출물 (계획서, PR 본문) 의 일관성 — 사이클별 편차
- audit log (`docs/plans/.audit/<task-id>.md`) 가 회고 시 실제로 유용한가

---

## 13. 실행 순서 (구현 단계 — **합의 후**)

> 본 §13 은 §11 의 Open Questions 가 답변된 후에야 의미 있음. 지금은 참고용.

### Phase 0: 사전 확인 (~1시간 — v2 에서 확장)
- [ ] **0a. 슬래시 커맨드 실행 모델 검증** (최우선)
  - [ ] §11-0 Q0-1~Q0-5 답변 확보
  - [ ] 다단계 게이트 동작 가능성 확인
  - [ ] 결과가 C (불가능) 면 v3 재설계로 전환 — 이하 단계 무효
- [ ] **0b. codex CLI 명세 확정**
  - [ ] §11-1 Q1~Q6 답변 확보
  - [ ] codex CLI 단독 테스트
  - [ ] JSON 출력 강제 5회 호출 검증 (성공률 기록)
- [ ] **0c. macOS 환경 확인**
  - [ ] `timeout`/`gtimeout` 존재 여부
  - [ ] §2-2 fallback 패턴 검증
- [ ] `.gitignore` 에 `docs/plans/*.state.json`, `docs/plans/*.lock`, `.cache/` 추가

### Phase 1: `/plan` 구현 (~1.5시간)
- [ ] `docs/plans/.gitkeep` 추가
- [ ] `.claude/commands/plan.md` 작성
- [ ] §10-1 계획서 템플릿 확정 후 적용
- [ ] §6-4 state.json + review.md + lock 통합
- [ ] dry-run

### Phase 2: `/work` 구현 (~1.5시간)
- [ ] `.claude/commands/work.md` 작성
- [ ] **§7-2 의 `git diff $BASE` 명령 검증** (F2 — 첫 구현 직후 빈 결과 안 나오는지)
- [ ] §7-4 diff 분기 임계값 검증
- [ ] 중단 후 재개 시뮬레이션 (state 기반 이어받기)
- [ ] 작은 task 로 검증

### Phase 3: `/ship` 구현 (~1시간)
- [ ] `.claude/commands/ship.md` 작성
- [ ] §10-2 PR 템플릿 확정 후 적용
- [ ] §10-3 커밋 분할 로직 검증
- [ ] **`/done` 호출 위치가 PR 생성 성공 후인지 검증** (F4)
- [ ] PR 생성 실패 시 TASKS.md 가 미갱신 상태로 유지되는지 검증

### Phase 4: end-to-end (~1시간)
- [ ] 실제 task 1개로 전체 사이클
- [ ] §12-3 정량 지표 측정 (G1a/b/c 모두)
- [ ] audit log (`docs/plans/.audit/<task-id>.md`) 의 가독성 평가
- [ ] 회고 → §14 작성

### Phase 5: 안정화 (1주일 사용 후, 선택)
- [ ] 프롬프트 보강
- [ ] 게이트 default 조정
- [ ] 비용 상한 재조정

**총 예상 소요**: 5~6시간 (Phase 5 제외, v2 에서 Phase 0 확장으로 +1시간)

---

## 14. Lessons Learned
> Phase 4 완료 후 작성.

---

## 15. 변경 이력
| 버전 | 날짜 | 변경 | 작성자 |
|------|------|------|--------|
| Draft v1 | 2026-04-18 | 최초 작성 | Claude |
| Draft v2 | 2026-04-18 | Codex 1차 리뷰 반영 — F1~F8 + A1, A2, A4 수용. 주요 변경: §3-1 G1 분할 (invocation/decision/context-switch), §5-2 D 재진입 경로 신설, §6-3-3 `/done` 시점을 PR 성공 후로 이동, 신규 §6-4 (state/lock/audit log 영속화), §7-1/7-2 macOS timeout portability + ADR 인덱스 inline 주입 + git diff $BASE 명령 수정, §7-6 비용 프록시 지표, §7-7 실패 임계치, §9-1 R10~R12 추가, §11-0 슬래시 커맨드 실행 모델 검증 (최우선), §11-9 Q21~Q25 추가, §12-1 Phase 0 분할 (0a/0b/0c), §12-3 KPI 분리, §13 Phase 0 확장. typo: brunch→branch | Claude |
| Draft v3 | 2026-04-19 | 2차 리뷰 반영 — F2~F6, F8, F12 수용 + F1/F7 부분 보강 + F9~F11 기각 근거 명시. 주요 변경: 상단에 F1 Blocker 경고 및 PeakCart scope 명시, §3-3 Deferred 에 범용화 보류 추가, §6-3-2 `applied_items` → `completed_plan_items[]`/`accepted_review_items[]`/`rejected_review_items[]`/`deferred_review_items[]` 로 분리 (F3), §6-3-2/7-2 base branch discovery 4단 폴백 (F6), §6-3-3 `/ship` stage 6단 세분화 + 재진입 매트릭스 + `created_commits[]`/`push_status`/`remote_branch`/`pr_url`/`done_applied` 추가 (F2), §6-4-2 state.json 스키마 갱신, §6-4-4 lock 을 파일→디렉토리 (mkdir 원자성, F5), §7-1 heredoc `<<'EOF'` → `<<EOF` 로 변경해 `${TASK_ID}` 주입 가능 (F4), §7-5 fallback ladder 를 JSON/timeout/push/PR/consistency 5개 ladder 로 확장 (F8), §9-1 R13~R15 추가, §11-7 `/tmp`/`decision-<ts>.md` → `.cache/`/audit log 드리프트 정리 (F12), §11-10 Q26~Q28 추가, audit log 파일명 canonicalize (F12). **기각**: F9/F10/F11 범용화 — §2-1 사용자 제약 (PeakCart 전용) 및 §3-2 비목표로 명시된 영역. §3-3/Q28 에서 "Phase 4 후 재평가" 로 DEFERRED 처리 | Claude |
| | | (다음 리뷰 후 추가) | |

---

## 부록 A. 글로서리

| 약어 | 의미 |
|------|------|
| ADR | Architecture Decision Record (`docs/adr/`) |
| SSOT | Single Source of Truth |
| GP-N | `/plan` 의 N번째 게이트 |
| GW-N | `/work` 의 N번째 게이트 |
| GS-N | `/ship` 의 N번째 게이트 |
| Rn | §9-1 위험 요소 ID |

## 부록 B. 참고 — 기존 자산 위치
- `.claude/commands/sync.md`, `next.md`, `done.md`
- `.claude/settings.json` (codex 플러그인 활성화 — 본 안에서 미사용, R1 fallback 카드)
- `docs/TASKS.md`, `docs/adr/README.md`
- `docs/01~07-*.md` (Layer 1 설계 문서)
- `docs/progress/PHASE{1,2,3}.md`
- `docs/consistency-hints.sh`

## 부록 C. v2 신규 자산 (구현 시)
- `docs/plans/<task-id>.md` (계획서, git 추적)
- `docs/plans/.audit/<task-id>.md` (audit log, git 추적)
- `docs/plans/<task-id>.state.json` (재개 상태, gitignore)
- `docs/plans/<task-id>.lock` (동시성 lock, gitignore)
- `docs/plans/.archive/` (`/ship` 후 state archive)
- `.cache/codex-reviews/` (raw JSON dump, gitignore)
- `.cache/codex-reviews/_metrics.tsv` (호출별 비용/프록시 지표)
- `.cache/diffs/` (diff 백업, gitignore)
- `.gitignore` 항목 추가: `docs/plans/*.state.json`, `docs/plans/*.lock`, `.cache/`
