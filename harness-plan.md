# Claude × Codex 하이브리드 워크플로우 하네스 — 설계 문서

> **상태**: Draft v10 — Phase 0 (0a/0b/0c) 통과 후 구현 반영. Phase 1 착수 가능.
> **작성**: 2026-04-18 (최신 갱신: 2026-04-19)
> **대상 프로젝트**: PeakCart (`/Users/kimgyuill/dev/projects/PeakCart`) — **본 문서는 PeakCart 전용 reference design**. 범용 하네스로의 추상화는 §3-2 의 비목표로 명시됨. 다른 프로젝트 재사용은 본 안 검증 후 별도 문서에서 다룸.
> **이 문서의 용도**: 여러 차례 리뷰/개선을 거친 후 구현. 지금은 **구현 참조 설계 문서**이며, §6~§7 의 계약은 Phase 0 검증을 통과했음.
> **Phase 0 검증 결과** (v10): 0a 판정 B (일부 제약 있지만 우회 가능 — nested slash 불가 → shared script 패턴), 0b 5/5 JSON 파싱 성공 (`--output-schema` 네이티브 지원), 0c hard timeout provider 확보 (Python wrapper). 본 문서는 더 이상 **조건부** 설계안이 아님.

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
- GitHub CLI (`gh`): `/ship` 의 PR 조회/생성에 필요. 설치/인증/버전/권한은 Phase 0 에서 선확인 필요

**macOS 도구 portability 주의** (v9 정정 — timeout provider 는 선택이 아니라 필수 계약):
- `timeout` 은 macOS 기본 PATH 에 없음 (GNU coreutils 의존). 그러나 본 설계는 §7-5-B timeout ladder 에 의존하므로, **`timeout` / `gtimeout` / Python wrapper 중 하나는 반드시 확보돼야 함**
- 허용 provider 는 다음 3개뿐:
  ```bash
  if command -v timeout >/dev/null; then TIMEOUT="timeout 60"
  elif command -v gtimeout >/dev/null; then TIMEOUT="gtimeout 60"
  else TIMEOUT="python3 scripts/timeout_wrapper.py 60"
  fi
  ```
- **`TIMEOUT=""` (무한 대기 fallback) 은 금지**. provider 가 없으면 Phase 0c 실패로 판정하고 구현 착수 금지

### 2-3. 자산
| 자산 | 위치 | 활용 |
|------|------|------|
| `.claude/commands/sync.md` | PeakCart | 그대로 유지. nested slash 불가 확정 (Phase 0a) → `/plan` 은 `.claude/scripts/shared-logic.sh` 로 로직 재사용 |
| `.claude/commands/next.md` | PeakCart | 그대로 유지, `/plan` 인자 없을 때 **선정 로직 참조** |
| `.claude/commands/done.md` | PeakCart | 그대로 유지, `/ship` 에서 **완료 반영 로직 참조** |
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
- **G1b. decision prompt 횟수**: 사용자 게이트 응답 횟수 = **베이스라인 측정 + 의식적 통제**
  - 하위 지표: `gate_shown_count`, `gate_auto_pass_count`, `gate_user_response_count`, `degraded_gate_count`, `always_gate_count`, `conditional_gate_count`
  - **판정선**: 정상 경로 평균 `gate_user_response_count ≤ 4`, p95 `≤ 6`. high-risk degraded 경로는 평균 `≤ 6`, p95 `≤ 8`
- **G1c. 수동 fallback/외부 전환 횟수**: 사용자가 하네스를 벗어나 외부 터미널/수동 절차로 전환한 횟수 = **주요 운영 지표**
  - 측정: `manual_fallback_declared_count`, `external_terminal_handoff_count`
  - 목표: 정상 경로 `0`, 주간 샘플 회고 기준 5건 중 1건 이하
- **G2. 수동 복붙 발생 횟수**: 설계상 0 이 아니라 **신고 기반 compliance metric** 으로 추적
  - 측정: `manual_copy_paste_declared_count` + 주간 샘플 회고
  - 목표: 정상 경로 `0`, 예외 발생 시 audit log 에 원인 기록
- **G3. 감사 흔적 보존**: 리뷰 요약 + 사용자 결정 + P0 무시 사유는 **재부팅/정리에 영향받지 않는 위치** (§6-4 참조)
- **G4. 사용자 결정 흐름 유지**: 자동 무시 X, 매 게이트 default 가 안전 옵션

> G1a 만 보면 자동화 효과가 과대평가될 수 있음. **G1a + G1b 를 함께 보고**, G1b 가 평균 4 이하로 떨어지지 않으면 사용자 피로 절감 효과 미미로 판정. G1c/G2 는 outcome KPI 라기보다 **운영 준수(compliance) 지표**로 해석한다.

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

> **v10 업데이트**: 본 절과 §6~§7 의 흐름/명령은 Phase 0 (0a/0b/0c) 검증을 통과한 **확정 구현 명세**이다. 0a 결과 B (nested slash 불가 → shared script 패턴 채택) 와 0b 결과 A (`--output-schema` 5/5 성공) 를 §7 에 반영.

### 4-1. 한 줄 요약
**Claude Code 의 슬래시 커맨드 안에서 Codex CLI 를 Bash subprocess 로 호출**하되, `/sync`/`/next`/`/done` 로직은 `.claude/scripts/shared-logic.sh` 로 추출해 재사용. 결정 게이트만 사용자에게 남긴다.

### 4-2. 신규 슬래시 커맨드 3종

| 커맨드 | 흡수하는 기존 단계 | 책임 |
|--------|-------------------|------|
| `/plan [<task-id>]` | 1, 2, 3, 3.1 | 계획 수립 + Codex 리뷰 루프 |
| `/work` | 4, 5 | 구현 + diff Codex 리뷰 루프 |
| `/ship` | 6, 7, 8 | 진행 반영 + 작업별 커밋 + PR 생성 |

### 4-3. 핵심 메커니즘
- **Codex 호출**: `codex exec --cd "$(pwd)" --output-schema <FILE>` 확정 (Phase 0b). 인증은 ChatGPT 로그인 (`~/.codex/auth.json`)
- **컨텍스트 주입**: 코덱스에게 "프로젝트 루트에서 ADR/계획서를 직접 읽으라" 고 경로만 전달 (복붙 X)
- **출력 강제 형식**: JSON 스키마 강제 → Claude 가 파싱해 사용자에게 정형 표로 제시
- **사용자 게이트**: 리뷰가 정상 파싱된 경우와 degraded review (§6-2, §7-5) 를 구분해 표시
- **루프 상한**: 한 슬래시 커맨드 내 codex **기본 시도 예산** 최대 3회. 분할/복구는 잔여 예산 내에서만 허용하며, 초과 시 자동 중단 + 사용자 명시 확인

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
| F | **Claude Code 슬래시 커맨드 + Bash 로 codex CLI 호출** | 신규 인프라 0, 양 도구 모두 로컬 파일 직접 접근, 출력 캡처 자유, IDE UX 보존 | 슬래시 실행 모델·Codex 프로세스 계약이 미확정이면 설계 전체가 무효화될 수 있음. 출력 파싱/루프 관리/재개 모델 복잡도 큼 | **조건부 채택** |

### 5-1. 후속 진화 경로 (참고)
F → D 진화는 가능. 하네스가 복잡해지거나 멀티 모델로 확장 시 Python/Node 하네스로 이전. 본 안은 **그 시점이 오기 전까지의 최소 충분 해**.

### 5-2. 조건부 D 재진입 경로 (v2 추가 — F1 / A3 대응)
대안 D 의 기각 사유는 "현 단계 과잉" 인데, 이는 **F (슬래시 커맨드) 가 작동한다는 가정** 위에 성립. Phase 0 의 슬래시 커맨드 실행 모델 검증 (§13 Phase 0) 이 다음 결과를 내면 D 를 다시 검토:
- **검증 결과 A — 슬래시 커맨드가 다단계 게이트/루프/하위 호출을 안정적으로 지원** → F 채택 유지
- **검증 결과 B — 일부 제약 있지만 우회 가능** → F 채택, 우회 방법을 §6 에 명시
- **검증 결과 C — 슬래시 커맨드가 본질적으로 한 번의 프롬프트 확장이라 본 설계 불가능** → **D 재검토 필수**. 현재 문서를 차기 버전으로 전면 개정.

이 분기는 §13 Phase 0 의 산출물에 따라 결정.

### 5-3. 장애 유형별 fallback 기준 (v8 신설)

| 장애 유형 | 우선 fallback | 비고 |
|-----------|---------------|------|
| 슬래시 커맨드 실행 모델 자체가 다단계 상태머신을 지탱하지 못함 | D (외부 하네스) | 문서 전체 실행 모델 재설계 대상 |
| Codex CLI non-interactive 만 불안정 | B (플러그인) 또는 수동 모드 | 슬래시 상태머신은 유지 가능하나 Codex 호출면만 교체 |
| `gh` 문제로 `/ship` 자동화 불가 | `/ship` 만 수동 fallback | `/plan`, `/work` 는 유지 가능. D 재검토는 별도 설계 변경 논의가 있을 때만 |
| Codex JSON 불안정/timeout 반복 | 현 설계 유지 + degraded / split / stop ladder | 구조 전환 전 운영 fallback |

---

## 6. 상세 설계

> **v10 업데이트**: 본 §6 상태머신은 Phase 0a 결과 B (slash + shared-script 패턴) 위에서 유효한 **in-command 확정 명세**이다. 0a 가 결과 C 였다면 out-of-command (외부 하네스) 로 재기술이 필요했으나 그 시나리오는 realized 되지 않음.

### 6-1. 컴포넌트 흐름

```
[사용자] ─ /plan <task-id> ─▶ [Claude Code: 오케스트레이터]
                                   │
                                   ├─ Step 1: /sync 로직 → 다음 task 파악
                                   ├─ Step 2: 계획서 작성 → docs/plans/<task>.md
                                   ├─ Step 3: Bash 호출
                                   │           codex exec --cd $(pwd) <<EOF
                                   │             [프롬프트 + 경로 명시]
                                   │           EOF > .cache/codex-reviews/plan-<task-id>-<ts>.json
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
                                   │       ┌──────── .cache/codex-reviews/plan-<task-id>-<ts>.json
                                   │       ▼
                                   ├─ Step 4: JSON 파싱 + 사용자 화면 정형 표
                                   ├─ Step 5: 사용자 게이트 (5분기)
                                   └─ Step 6: 보완 적용 → Step 3 재호출 (최대 3회)
```

### 6-2. 사용자 게이트의 위치 (전체 사이클) — v4: 기본/조건부 분리 (F4 반영)

게이트를 "항상 물음" (`always`) 와 "이상 시에만 물음" (`conditional`) 로 명시적으로 분리. **정상 경로에서 조건부 게이트는 자동 통과** — G1b 피로 축소의 핵심.

| 게이트 | 유형 | 트리거 | 정상 경로 동작 | 묻는 내용 |
|--------|------|--------|---------------|----------|
| GP-1 | conditional | ADR 선행이 필요한 변경 감지 시 (새 환경/외부 의존성/경계 변경) | 해당 신호 없으면 **자동 통과** | "ADR 먼저 작성할까요?" |
| GP-2 | conditional | `/plan` codex 리뷰가 `result=ok` 이고 P0/P1 ≥ 1건 | **`result=ok` + P0/P1 없음 → 자동 통과** (P2 는 audit log 에만 기록, 계획서 자동 수정 X) | 리뷰 항목 반영 선택 |
| GP-2b | conditional | `/plan` codex 리뷰가 `timeout` / `json_parse_failed` / `empty` / `error` | 정상 리뷰가 아니면 **자동 통과 금지** | "degraded review 로 진행할지" 확인 |
| GW-1 | always | `/work` 시작 시점 | — | "브랜치 명 확정?" |
| GW-2 | conditional | `/work` diff 리뷰가 `result=ok` 이고 P0/P1 ≥ 1건 | `result=ok` + P0/P1 없음 → 자동 통과 (P2 는 audit log 에만 기록) | 리뷰 항목 반영 선택 |
| GW-2b | conditional | `/work` diff 리뷰가 `timeout` / `json_parse_failed` / `empty` / `error` | 정상 리뷰가 아니면 **자동 통과 금지** | "degraded review 로 진행할지" 확인 |
| GS-1 | conditional | `consistency-hints.sh` 가 깨진 참조 보고 | **경고 0건 → 자동 통과** (현 v3 는 항상 물음 → v4 자동화) | 깨진 참조에도 진행 여부 |
| GS-2 | always | `/ship` 커밋 분할 직전 | — | "이 분할로 커밋?" (되돌릴 수 없는 행동 직전) |
| GS-3 | always | `/ship` push + PR 직전 | — | "이 본문으로 push + PR?" (외부 공개 직전) |

**always 게이트 (3개)**: GW-1, GS-2, GS-3 — 되돌리기 어려운 행동(branch 생성, 커밋 확정, 외부 publish) 직전에만 배치. 여기는 자동화하지 않음.

**conditional 게이트 (6개)**: GP-1, GP-2, GP-2b, GW-2, GW-2b, GS-1 — 이상 신호가 있을 때만 개입. 단, **degraded review 는 자동 통과하지 않음**.

**기대 효과**: 정상 경로 평균 3~4회 개입 (always 3 + conditional 중 P0/P1 발생 시 평균 ~1회). 이상 경로일수록 더 자주 멈춤 — 사용자는 "평상시 조용, 이상 시 집중" 경험.

> **R5 (ㅇㅋ 자동화) 와의 충돌 해소**: conditional 자동 통과는 (a) `result=ok` 이고 P0/P1 이 0건일 때만, (b) timeout/JSON 실패/empty 는 GP-2b/GW-2b 로 분리해 자동 통과 금지, (c) P2 는 audit log 에 자동 기록되어 회고 시 재확인 가능. "일 없을 때 조용히 넘기는 것" 과 "리뷰가 실패했는데 조용히 넘기는 것" 은 구분한다.
>
> **자동 통과 가시화 규칙 (v9)**: GP-2/GW-2 자동 통과 시에도 완전 은닉하지 않고 `요약 1줄 + run_id + "세부 보기" + "강제 검토"` 를 표시한다. 게이트는 열지 않되, 사용자가 필요하면 즉시 override 가능해야 한다.
>
> **degraded review 의 위험도 차등 원칙 (v9 default)**:
> - `risk_level=high` if `diff_lines >= 800` or `split_review=true` or touched path matches `auth|security|payment|config|infra`
> - `risk_level=low` otherwise
> - `/plan` 은 `adr_boundary_change=true` 면 `high`
> - high-risk degraded 의 기본 선택지는 `중단/재시도`, low-risk degraded 만 `진행` 기본값 허용

### 6-3. 슬래시 커맨드별 상세 명세

#### 6-3-1. `/plan [<task-id>]`

**전제**: 없음 (사이클 시작점)
**산출물** (v2 — F3 대응으로 영속화 위치 변경):
- `docs/plans/<task-id>.md` (영구, git 추적)
- `docs/plans/.audit/<task-id>.md` (영구, git 추적, 사용자 결정 audit log — §6-4)
- `docs/plans/<task-id>.state.json` (영구, gitignore — 재개용 상태 — §6-4)
- `.cache/codex-reviews/plan-<task-id>-<ts>.json` (영구, gitignore — raw JSON dump)
- `.cache/codex-reviews/plan-<task-id>-<ts>.stderr` (영구, gitignore — 프로세스 stderr)

**처리 단계** (v5 — §6-2 conditional 게이트 반영 + v4 review_runs 구조로 `/work` 와 대칭화):
1. 인자 파싱: 있으면 그 task, 없으면 `next` 상당 로직으로 자동 선택
2. **lock 획득 + `sync` 상당 로직 실행**: nested slash 불가 (Phase 0a 확정) → `.claude/scripts/shared-logic.sh` 의 `lib_sync` / `lib_next` 함수를 호출
3. **state 파일 확인** (`docs/plans/<task-id>.state.json`): 존재 시 `stage` + `loop_count_by_command.plan` 으로 재개 지점 결정, 사용자에게 재개 제안
4. ADR 작성 선행 판단: 새 환경/외부 의존성/아키텍처 경계 변경 여부
   - **조건부 (GP-1)**: 신호 있음 → 게이트 실행 → "예" 시 종료, "아니오" 시 진행. **신호 없음 → 자동 통과** (§6-2)
5. 계획서 초안 작성 (템플릿은 §10-1 참조). 작업 항목은 stable id (`P1.`, `P2.`, ...) 필수. 성공 후 `stage=plan.draft.created`
6. **run 예약 기록**: `run_id="plan:<utc-ts>:<session_id>:<attempt>"` 생성 후 state 에 `pending_run` 으로 **원자 저장**. `loop_count_by_command.plan`, `attempts_by_command.plan`, `codex_attempts_cycle_total` 은 이 시점에 함께 증가시켜 crash 후에도 같은 run_id 재사용 금지
7. `stage` 는 바꾸지 않고 Codex 리뷰 호출 (§7-1 호출 규약 — 프롬프트에 `${RUN_ID}` 주입). raw JSON 은 `.cache/codex-reviews/plan-<task-id>-<ts>.json` 에 저장
8. 결과 파싱 후 §7-3 스키마 검증. `run_id` 응답값이 주입값과 일치하지 않으면 §7-5-A fallback
9. **조건부 (GP-2)**: `result=ok` 이고 응답 items 에 severity ∈ {P0, P1} 이 1건 이상 → 사용자 표 제시 + 게이트 실행. `result=ok` + P0/P1 0건 → 자동 통과 + 요약 1줄 표시. `result!=ok` 이면 **GP-2b** 실행
10. 선택 항목 또는 degraded 승인 결과를 계획서/audit/state 에 반영. state 의 `review_runs[]` 에 `{run_id, command: "plan", loop, ts, raw_path, result, accepted_ids, rejected_ids, deferred_ids, degraded_accepted, degraded_reason, risk_level, risk_signals}` append, `pending_run` 제거 후 `stage=plan.review.completed` 기록
11. 루프 판정: 아래 3조건을 모두 만족할 때만 Step 6 으로 복귀
    - 이번 run 에서 실제 수정이 발생 (`accepted_ids` 1개 이상)
    - 사용자가 "수정 후 재리뷰" 를 명시 선택
    - `attempts_by_command.plan < 3`
12. 종료 시 state 파일에 `stage: "plan.done"` 기록

**중단 후 재개**: `stage`, `loop_count_by_command.plan`, `review_runs[]` (`command=="plan"` 인 run 만), `pending_run` 로 재진입 지점 결정. `pending_run != null` 이면 §6-4-6 규약대로 먼저 finalize 하고 새 run 예약 여부를 판단

> **v4→v5 보강**: v4 state 스키마는 `review_runs[]` + `loop_count_by_command` 였지만 `/plan` 절차는 v3 의 `loop_count` 에 머물러 있었음. v5 에서 `/work` 와 대칭으로 맞춰 plan 리뷰도 run 단위로 감사 추적 가능.

---

#### 6-3-2. `/work`

**전제**: `docs/plans/<task-id>.md` 가 존재, state.json 의 `stage` 가 `plan.done` 이상
**산출물** (v2 변경):
- 새 브랜치 + working tree 변경
- `docs/plans/.audit/<task-id>.md` 에 diff 리뷰 결정 append
- `<task-id>.state.json` 갱신 (stage: `work.impl.completed` / `work.review.completed` → `work.done`)
- `.cache/codex-reviews/diff-<task-id>-<ts>.json` (raw JSON)
- `.cache/codex-reviews/diff-<task-id>-<ts>.stderr` (프로세스 stderr)
- `.cache/diffs/diff-<task-id>-<ts>.patch` (diff 백업)

**처리 단계** (v3 — F3/F6 대응):
1. **lock 획득 + state 파일 확인**: 진행 중이면 어느 단계에서 멈췄는지 확인. TASKS.md `🔄` 와 교차 검증
2. 브랜치 결정:
   - state 에 branch 정보 있으면 `git branch --show-current` 와 교차 검증 후 그대로 사용
   - 없으면 브랜치 명 제안 (예: `feat/task-3-4-loadtest`) → **GW-1 게이트** → state 에 기록
   - branch 확정 후 `git switch <branch>` 또는 `git switch -c <branch>` 수행. `HEAD != state.branch` 이면 자동 진행 금지
3. 계획서 항목 순회하며 구현. 항목 완료 시 state 의 `completed_plan_items[]` 에 해당 **stable id** (예: `"P1"`, `"P2"` — §10-1 규약) 를 append 하고, 구현 완료 후 `stage=work.impl.completed` 기록
4. **diff 캡처** (v3 — F6 대응으로 base branch discovery 명세화):
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
5. `git diff --stat "$BASE"` 로 변경 규모 보고
6. **review plan 예약 기록**: diff 크기에 따라 `review_plan.mode=single|split` 을 먼저 정한다. `single` 이면 `run_id="work:<utc-ts>:<session_id>:<attempt>"`, `split` 이면 chunk 별 `run_id="work:<utc-ts>:<session_id>:<attempt>:cN"` 을 예약 후 state 에 **원자 저장**. `loop_count_by_command.work` 는 논리 loop 수를 1 증가시키고, `attempts_by_command.work` 와 `codex_attempts_cycle_total` 은 **실제 Codex subprocess 호출 예정 수** 만큼 증가시킨다 (single=1, split=chunk 수)
7. `stage` 는 바꾸지 않고 Codex diff 리뷰 호출 (§7-2 호출 규약, diff 크기 분기는 §7-4 — 프롬프트에 `${RUN_ID}` 주입). split 인 경우 모든 chunk 가 terminal 상태가 된 뒤에만 aggregate gate 를 연다
8. 결과 파싱 후 §7-3 스키마 검증. `run_id` 불일치 시 §7-5-A fallback. 표 제시 — raw JSON 은 `.cache/...` 에 저장
9. **조건부 (GW-2)**: aggregate `result=ok` 이고 응답 items 에 P0/P1 ≥ 1건 → 사용자 표 + 게이트. `result=ok` + P0/P1 0건 → 자동 통과 + 요약 1줄 표시. `result!=ok` 이면 **GW-2b** 실행. P2 는 어느 쪽이든 audit log 에만 기록
10. 선택 항목 또는 degraded 승인 결과 적용. state 의 `review_runs[]` 에 해당 run 또는 chunk 엔트리 (`run_id`, `parent_run_id`, `command: "work"`, `loop`, `ts`, `raw_path`, `result`, `accepted_ids`, `rejected_ids`, `deferred_ids`, `degraded_accepted`, `degraded_reason`, `risk_level`, `risk_signals`, `chunk_index`, `chunk_total`) 를 append, `pending_run` 제거 후 `stage=work.review.completed` 기록
11. 루프 판정: 아래 3조건을 모두 만족할 때만 Step 6 으로 복귀
    - 이번 run 에서 실제 수정이 발생 (`accepted_ids` 1개 이상)
    - 사용자가 "수정 후 재리뷰" 를 명시 선택
    - `attempts_by_command.work < 3`
12. 종료 시 state 파일에 `stage: "work.done"` 기록

**중단 후 재개**: state 의 `stage`, `loop_count_by_command`, `completed_plan_items` (stable id), `review_plan`, `review_runs` (각 run 별 수용/거부), `branch` 로 재진입. split 인 경우 `review_plan.chunks[].status` 를 보고 미완료 chunk 부터 이어간다

> **F3 반영 (v3→v4 보강)**: v3 의 `applied_items` 분리에서 한 발 더 — (a) `completed_plan_items` 는 계획서의 stable id (§10-1) 를 저장해 순서 변경에 무관해짐, (b) 리뷰 수용/거부는 단일 배열이 아니라 `review_runs[]` 의 run 단위로 저장해 호출 간 `items[].id` 충돌 제거.

---

#### 6-3-3. `/ship`

**초기 진입 전제**: active state 가 없을 때는 `/work` 완료, state.json 의 `stage` 가 `work.done`, `state.branch` 가 현재 checkout branch 와 일치, 커밋 대상 변경이 존재해야 함
**재진입 전제**: active state 가 `ship.*` 이면 `/ship` 은 재개 모드로 동작하며 working tree 변경 존재를 요구하지 않음
**산출물**:
- 작업별 git 커밋 (여러 개)
- 원격 push (사용자 명시 동의 후)
- GitHub PR
- TASKS/progress/ADR 갱신 (PR 생성 성공 후)

**처리 단계** (v5 — F1 conditional GS-1 + F4 stage 표기를 "완료 후 → ..." 로 통일):

> **표기 규약**: stage 는 "**해당 단계 완료 후**" 상태를 의미 (§6-4-2 매트릭스 참조). 아래 절차는 "이 단계를 수행 → 성공 시 stage=X 로 기록" 순서로 읽는다.

1. **state 파일 확인 + lock**: 다른 세션이 같은 task 진행 중인지 확인 (§6-4 참조). state 의 `stage` 를 읽어 이어받을 지점 결정 (아래 재진입 표 참조)
2. **Consistency precheck 수행**: `bash docs/consistency-hints.sh` 실행
   - **조건부 (GS-1)**: warnings ≥ 1건 → 게이트 실행, 사용자가 (a) 수정 / (b) 무시 + 사유 / (c) 종료 선택. **warnings 0건 → 자동 통과** (§6-2)
   - **실행 실패** (script 없음 / permission / nonzero exit with no parseable warnings) → §7-5-E 의 실행 실패 분기로 이동. 자동 통과 금지
   - 통과 후 → `stage=ship.precheck` 기록
3. **커밋 분할 제안 수행** (분할 기준은 §10-3) → 분할 결과를 state 의 `commit_plan[]` 에 **먼저 원자 저장** → **GS-2 게이트** (always) 분할 미리보기 확인 → 승인 후 → `stage=ship.partition.previewed` 기록
4. **커밋 생성 수행**: `commit_plan[]` 의 각 그룹별 `partition_id` / 예상 커밋 메시지를 기준으로 `git add <files>` + `git commit` 순차 실행 (`-A` 금지, 파일 명시). 각 커밋 직후 sha 를 state 의 해당 partition 에 append. 재진입 시 `created_commits[]` 뿐 아니라 `commit_plan[]` 의 partition_id + commit subject 를 `git log` 와 교차 확인해 **재커밋 방지**. 모든 커밋 완료 후 → `stage=ship.commits.created` 기록
5. **PR 본문 생성 수행** (템플릿은 §10-2). `docs/plans/.audit/<task-id>.md` 의 P0 무시 사유가 있으면 본문에 포함 (Q19 default). 본문을 `.cache/pr-body-${TASK_ID}.md` 에 저장 (PR 생성 실패 시 재사용)
6. **GS-3 게이트** (always): 본문 미리보기 확인
7. **Push 수행**: `git push -u origin <branch>`
   - 성공 후 → state 의 `ship_resume_cursor: "pr.pending"`, `push_status: "pushed"`, `remote_branch: "<branch>"`, `stage=ship.pushed` 기록
   - `git push` 가 이미 up-to-date 이면 멱등적으로 다음 단계
   - 실패 시 `ship_resume_cursor: "push.failed"` 와 `push_status: "failed"` 기록 후 §7-5-C ladder
8. **PR 생성 수행**: 먼저 `gh pr list --head <branch> --state open --json url` 또는 동등 조회로 기존 PR 존재 여부 확인. 있으면 `pr_url` 재사용, 없으면 `gh pr create --body-file .cache/pr-body-${TASK_ID}.md ...`
   - 성공 후 → state 의 `ship_resume_cursor: "done.pending"`, `pr_url`, `stage=ship.pr.created` 기록
   - 실패 시 `ship_resume_cursor: "pr.failed"` 기록 후 §7-5-D ladder (본문 `.cache/pr-body-*.md` 재사용)
9. **`done` 상당 로직 수행** (TASKS `🔄`→`✅`, progress, ADR 갱신) — Phase 0a 결과 B 로 nested slash 불가 확정 → 기존 `/done` 의 파일 갱신 로직을 `.claude/scripts/shared-logic.sh` 에 추출해 재사용
   - 성공 후 → state 의 `done_applied: true`, `stage=ship.done` 기록
   - 실패 시 사용자에게 보고하고 종료 (TASKS 는 미갱신, PR 은 이미 생성됨 → 다음 호출 시 Step 9 만 재시도 — 재진입 매트릭스의 `ship.pr.created` 행 참조)
10. state.json archive (또는 삭제 — Q24)
11. PR URL 반환

**중단 후 재진입 매트릭스**:

> **stage 의미 재정의 (v4 — 리뷰 F1 반영)**: stage 값은 "해당 단계 **완료 후**" 의 상태를 가리킴. 예: `stage=ship.pr.created` 는 "PR 생성이 완료된" 상태 → 다음 할 일은 `/done` 재시도. 이전 버전은 "해당 단계에 진입" 의미로도 읽힐 여지가 있어 매트릭스가 PR 재생성을 유도했음.

| 현재 stage / cursor | 확인할 것 | 다음 재진입 지점 |
|-----------|----------|------------|
| 없음 / `work.done` | — | Step 1 부터 (precheck 부터 시작) |
| `ship.precheck` | — | Step 3 (분할 제안 + GS-2) |
| `ship.partition.previewed` | — | Step 4 (커밋 생성) |
| `ship.commits.created` + cursor 없음 | `commit_plan[]` + `created_commits[]` vs `git log` 교차 확인 | Step 5 (PR 본문 생성) |
| `ship.commits.created` + `ship_resume_cursor=push.failed` | `push_status=="failed"` + 원격 반영 여부 재확인 | **Step 7 (push 재시도)** |
| `ship.pushed` | `git ls-remote origin <branch>` 로 원격 반영 확인 + `gh pr list --head <branch>` 조회 | Step 8 (PR 조회 후 없을 때만 생성) |
| `ship.pushed` + `ship_resume_cursor=pr.failed` | `pr_url` 부재 + 기존 PR 선조회 | **Step 8 (PR 생성 재시도)** |
| `ship.pr.created` | `pr_url` 존재 (필수) + `done_applied==false` | **Step 9 (`/done` 재시도)** — PR 은 이미 생성됨, 중복 생성 금지 |
| `ship.done` | `done_applied==true` | archive 만 수행, 작업 완료 |

> **순서의 의미**: `/done` 이 PR 생성 성공 후로 옮겨져 TASKS.md SSOT 는 깨지지 않음. v3 에서 stage 를 6단계로 세분화했고, v4 에서 매트릭스의 `ship.pr.created` 행을 `/done` 재시도로 정정. 파일 시스템 상태(커밋/remote/PR)와 **교차 검증 가능**하며 중복 PR 생성 위험 제거.

---

### 6-4. 상태 영속화 / 재개 / 동시성 (v2 신설 — F3, F8, A1 대응)

**문제**: G3 (감사 흔적 보존) 와 중단 후 재개 모두 영속화된 위치가 필요. 또한 동시 호출 (다른 세션) 방지.

#### 6-4-1. 파일 위치 표

| 파일 | 위치 | git | 수명 | 용도 |
|------|------|-----|------|------|
| 계획서 | `docs/plans/<task-id>.md` | 추적 | 영구 | 계획 본문 |
| 결정 audit log | `docs/plans/.audit/<task-id>.md` | 추적 | 영구 | 매 게이트 사용자 결정 + P0 무시 사유 (G3) |
| gate 이벤트 로그 | `.cache/codex-reviews/gate-events.tsv` | gitignore | 영구 | 게이트 노출/자동통과/응답 지표 |
| state | `docs/plans/<task-id>.state.json` | gitignore | task 완료까지 | 재개용 상태 머신 |
| lock **디렉토리** | `docs/plans/<task-id>.lock/` (디렉토리) + 내부 `pid` 파일 | gitignore | 슬래시 커맨드 실행 중만 | 동시 호출 방지 (mkdir 원자성, §6-4-4) |
| raw 리뷰 JSON | `.cache/codex-reviews/{plan,diff}-<task-id>-<ts>.json` | gitignore | 영구 (수동 정리 전까지) | 감사 / 디버깅 |
| diff 백업 | `.cache/diffs/diff-<task-id>-<ts>.patch` | gitignore | 영구 | 디버깅 |

`.gitignore` 에 다음 추가 필요 (v4: lock 은 디렉토리):
```
docs/plans/*.state.json
docs/plans/*.lock/
.cache/
```

> `.lock/` 끝 슬래시는 디렉토리 ignore 명시 (§6-4-4 mkdir 원자성 lock). 부록 C 와 동일.

#### 6-4-2. state.json 스키마

```json
{
  "task_id": "task-3-4",
  "stage": "work.impl.completed",
  "session_id": "01HF...ABC",
  "branch": "feat/task-3-4-loadtest",
  "completed_plan_items": ["P1", "P2"],
  "pending_run": null,
  "review_plan": {
    "command": "work",
    "mode": "single",
    "aggregate_result": "ok",
    "budget_remaining": 2,
    "unreviewed_scope": [],
    "chunks": []
  },
  "review_runs": [
    {
      "run_id": "plan:20260418T142300Z:01HFABC:1",
      "command": "plan",
      "loop": 1,
      "ts": "2026-04-18T14:23:00Z",
      "raw_path": ".cache/codex-reviews/plan-task-3-4-1745000000.json",
      "result": "ok",
      "accepted_ids": [1, 2],
      "rejected_ids": [],
      "deferred_ids": [3],
      "degraded_accepted": false,
      "degraded_reason": null,
      "risk_level": "low",
      "risk_signals": []
    },
    {
      "run_id": "work:20260418T161000Z:01HFABC:1",
      "parent_run_id": null,
      "command": "work",
      "loop": 1,
      "ts": "2026-04-18T16:10:00Z",
      "raw_path": ".cache/codex-reviews/diff-task-3-4-1745005000.json",
      "result": "ok",
      "accepted_ids": [1, 2, 4],
      "rejected_ids": [3],
      "deferred_ids": [5],
      "degraded_accepted": false,
      "degraded_reason": null,
      "risk_level": "high",
      "risk_signals": ["diff_large"],
      "chunk_index": 1,
      "chunk_total": 1
    }
  ],
  "loop_count_by_command": { "plan": 1, "work": 1 },
  "attempts_by_command": { "plan": 1, "work": 1 },
  "codex_attempts_cycle_total": 2,
  "commit_plan": [],
  "created_commits": [],
  "ship_resume_cursor": null,
  "push_status": null,
  "remote_branch": null,
  "pr_url": null,
  "done_applied": false,
  "last_diff_path": ".cache/diffs/diff-task-3-4-1745000000.patch",
  "started_at": "2026-04-18T10:00:00Z",
  "updated_at": "2026-04-18T10:30:00Z"
}
```

`stage` 가능 값 (v9 — 규약 통일):
- `stage` 는 항상 "**마지막으로 성공 완료된 내부 단계**" 를 의미한다
- 외부 호출 진행 중 상태는 `stage` 가 아니라 `pending_run` / `review_plan` 으로 표현한다
- `plan.draft.created` → `plan.review.completed` → `plan.done`
- `work.impl.completed` → `work.review.completed` → `work.done`
- `ship.precheck` → `ship.partition.previewed` → `ship.commits.created` → `ship.pushed` → `ship.pr.created` → `ship.done` (이후 archive)

필드 의미 (v4 — 리뷰 F2/F3 반영으로 식별자 안정화):
- `completed_plan_items[]`: 계획서 §2 체크리스트 중 구현 완료 항목의 **stable id** (예: `"P1"`, `"P2"`). 계획서 순서 변경/삽입에 영향받지 않음. id 규약은 §10-1 참조
- `session_id`: lock 소유자와 state writer 를 식별하는 UUID/ULID. PID 외에 세션 정체성을 남겨 stale 판정의 근거로 사용
- `pending_run`: 외부 Codex 호출 전에 예약해 둔 run 메타데이터. crash 후 raw 파일만 남은 경우에도 어떤 run 이 진행 중이었는지 복구 가능
  - 구조: `{ run_id, command, loop, ts, raw_path, status }`. 최소 `run_id`, `command`, `ts`, `raw_path` 는 필수
  - split 인 경우 `pending_run` 은 **현재 실행 중인 chunk 1개만** 가리킨다
- `review_plan`: split review 를 포함한 현재 review 실행 계획
  - 구조: `{ command, mode, aggregate_result, budget_remaining, unreviewed_scope[], chunks[] }`
  - `chunks[]`: `{ chunk_id, scope, run_id, status, raw_path, chunk_index, chunk_total }`
- `review_runs[]`: **각 Codex 호출을 1개 run 으로 기록**. Codex 출력의 `items[].id` 가 호출마다 1,2,3... 으로 reset 되므로 단일 배열로 합치면 loop 간 충돌 발생. run 별로 분리 저장해 감사/회고 시 "어느 호출의 몇 번 항목을 수용/거부했는지" 를 추적
  - `run_id`: 기본 형식은 `"{command}:{utc-ts}:{session_id}:{attempt}"`, split chunk 는 `"{command}:{utc-ts}:{session_id}:{attempt}:cN"` 형식. 둘 다 예약 시점에 유일해야 함
  - `parent_run_id`: split review 의 chunk 인 경우 상위 run 식별자
  - `accepted_ids` / `rejected_ids` / `deferred_ids`: 해당 run 내 items[].id
  - `result`: `ok` | `timeout` | `json_parse_failed` | `empty` | `error`
  - `error_reason`: `result="error"` 일 때의 하위 원인. 예: `interrupted_before_output`
  - `degraded_accepted` / `degraded_reason`: clean review 가 아니었지만 진행을 허용했는지와 사유
  - `risk_level` / `risk_signals[]`: gate 와 metrics 계산에 사용한 위험 판정 근거
  - `chunk_index` / `chunk_total`: split review 복구용
  - `raw_path`: 원본 Codex JSON 위치 (audit 감사 흔적)
- `loop_count_by_command`: 커맨드별 **논리 review loop 수** (표시/감사용)
- `attempts_by_command`: 커맨드별 **실제 Codex subprocess 호출 수**. split review 는 chunk 수만큼 증가
- `codex_attempts_cycle_total`: 재시도/분할 호출 포함 사이클 전체 누적 시도 수. 메트릭/회고용이며 루프 제어에는 사용하지 않음
- `commit_plan[]`: `/ship` 커밋 분할을 먼저 고정한 계획. 각 partition 의 `partition_id`, 파일 목록, 예상 메시지를 담아 재개 시 중복 커밋 방지
- `created_commits[]`: `/ship` 에서 생성한 커밋 sha 배열 (중복 커밋 방지)
- `ship_resume_cursor`: `/ship` 실패 후 재진입 위치를 보조하는 커서. 예: `push.failed`, `pr.failed`, `done.pending`
- `push_status`: `null` | `"pushed"` | `"failed"` (원격 반영 여부)
- `remote_branch`: push 성공 시 원격 브랜치 명 (ls-remote 로 검증 가능)
- `pr_url`: PR 생성 성공 시 URL. 미생성이면 `null`
- `done_applied`: `/done` 로직 (TASKS/progress/ADR 갱신) 실행 완료 여부

> **F2 수정 핵심**: v3 의 `accepted_review_items: [1,3]` 같은 단일 배열은 "어느 호출의 1번/3번인지" 를 잃음. loop 1 의 `id=1` 과 loop 2 의 `id=1` 이 구분 불가능해 재개 시 잘못된 항목을 "이미 수용" 처리할 위험. v4 는 run 단위로 분리 저장.
>
> **v7 보강 핵심**: run_id 는 loop 기반 suffix 가 아니라 **예약 후 즉시 state 에 영속화되는 유일 키**여야 한다. 그래야 Codex 응답 저장 후 state 기록 전에 죽어도 동일 run 으로 잘못 합쳐지지 않는다.
>
> **F3 수정 핵심**: v3 의 `completed_plan_items: [1, 2]` 는 계획서 체크리스트 **순번** 을 의미했으나, 순서가 바뀌거나 중간에 항목을 삽입하면 의미가 달라짐. v4 는 `P1`, `P2` 같은 stable id (한번 부여하면 재사용/재배치 금지) 로 변경.

#### 6-4-3. review.md 형식 (audit log)

매 게이트 결정마다 append. 사람 읽기용 Markdown 과 별도로 `gate-events.tsv` 에 정형 이벤트를 1줄씩 append:
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

`gate-events.tsv` 최소 컬럼:
```
ts	task_id	gate_id	gate_type	command	run_id	shown	auto_passed	result	user_choice	response_ms	default_selected	ignored_p0_count	degraded_accepted	risk_level	risk_signals	reason
```

- `shown`: 실제 사용자에게 게이트를 노출했는지
- `auto_passed`: conditional gate 가 조용히 통과됐는지
- `degraded_accepted`: degraded review 를 사용자가 승인했는지
- `reason`: P0 무시 / consistency 무시 / 강제 진행 사유
- auto-pass 후 사용자가 `[강제 검토]` 를 누르면 **새 행을 추가**한다: `shown=true`, `auto_passed=false`, `user_choice="force_review"`, `reason="auto_pass_override"`

#### 6-4-4. 동시성 제어 (lock) — v3 원자성 보강 (F5 대응)

**문제**: `[ -f $LOCK ] + echo $$ > $LOCK` 은 두 단계 사이 race — 두 세션이 동시에 확인 단계를 통과하면 둘 다 lock 획득. 이를 `mkdir` 의 원자성으로 해결.

```bash
LOCK_DIR="docs/plans/<task-id>.lock"   # 디렉토리 기반 lock (파일 아님)
PID_FILE="$LOCK_DIR/pid"
META_FILE="$LOCK_DIR/meta.json"
SESSION_ID="$(uuidgen 2>/dev/null || date +%s)"

# mkdir 은 원자적: 디렉토리가 이미 있으면 실패
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # stale 검사: 내부 pid 가 살아있는지 확인
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "다른 세션이 진행 중 (pid=$PID). meta 확인 후 중단/재시도하세요."
      exit 1
    fi
  fi
  echo "stale 가능성이 있는 lock 발견 (pid=${PID:-unknown}). 자동 삭제하지 않고 meta 확인 후 사용자 승인으로만 해제합니다."
  exit 1
fi
echo $$ > "$PID_FILE"
printf '{"session_id":"%s","pid":%s,"started_at":"%s","command":"%s"}\n' "$SESSION_ID" "$$" "$(date -u +%FT%TZ)" "<command>" > "$META_FILE"
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
```

> v2 의 `[ -f ] + echo >` 는 **TOCTOU (time-of-check to time-of-use)** race 가 있음. `mkdir` 은 커널이 원자성 보장. stale 처리는 `pid` 단독이 아니라 `session_id`/시작 시각/명령명을 함께 남겨 사람이 판별 가능하게 한다. `/plan`/`/work`/`/ship` 모두 lock 을 획득해야 동일 state/audit 파일 동시 갱신을 막을 수 있다. **자동 stale lock 삭제는 금지**하고, `meta.json` / `state.updated_at` / 경과 시간 확인 후 사용자 승인으로만 강제 해제한다.
>
> 단일 사용자 전제에서는 race 가 드물지만, 터미널 두 개에서 실수로 동시 호출하는 흔한 경우를 막기 위해 필요. 더 강한 보장 (NFS 등) 이 필요하면 `flock(1)` 검토 (macOS 기본 미포함).

강제 해제 절차:
1. `meta.json.session_id`, `pid`, `started_at`, state `updated_at` 를 사용자에게 제시
2. 사용자가 `force unlock` 을 승인한 경우에만 audit log 에 `stale_lock_override` 이벤트 append
3. 기존 lock 디렉토리 삭제 후 새 세션이 즉시 lock 재획득
4. 새 state write 에 `recovered_from_stale_lock=true`, `previous_session_id=<old>` 기록

#### 6-4-5. state 쓰기 규약 (v7 신설)

state 갱신은 **항상 원자적 치환**으로 수행:

```bash
STATE="docs/plans/${TASK_ID}.state.json"
TMP="${STATE}.tmp.$$"

render_state_json > "$TMP" &&
mv "$TMP" "$STATE"
```

- in-place overwrite 금지 (`>` 직접 덮어쓰기 금지)
- 외부 부작용 직전에는 먼저 state 를 기록하고, 외부 부작용 직후에는 결과를 다시 기록
- state parse 실패 시 자동 진행 금지. `.corrupt-<ts>.json` 으로 격리 후 사용자에게 복구/종료 선택 제공

#### 6-4-6. pending_run 종료 규약 (v8 신설)

- 외부 Codex 호출이 시작된 후에는 해당 run 을 반드시 **terminal 상태** (`ok` | `timeout` | `json_parse_failed` | `empty` | `error`) 로 `review_runs[]` 에 **1회만** 승격 기록하고, 직후 `pending_run=null` 로 정리
- 재개 시 `pending_run != null` 이면 순서대로:
  1. `raw_path` 존재 + parse 가능 → 기존 run finalize
  2. raw 없음 → 해당 run 을 `result="error"` 로 finalize 하고 `error_reason="interrupted_before_output"` 를 함께 기록
  3. finalize 후에만 새 `run_id` 예약
- 동일 `run_id` 로 재호출 금지

#### 6-4-7. archive 정책

`/ship` 성공 후:
- `ship.done` 과 `terminalized_at` 기록이 먼저 성공해야 archive 가능
- state.json → `docs/plans/.archive/<task-id>.state.json` 으로 이동 (또는 삭제 — Q24 에서 결정)
- `docs/plans/.audit/<task-id>.md` 는 그대로 유지 (영구 audit)
- `.cache/` 는 자동 정리 X (사용자가 디스크 압박 시 수동 정리)
- `/ship` 호출 시 active state 가 없고 archive 에 동일 task 의 `ship.done` state 가 있으면 "이미 완료된 task" 로 즉시 종료

---

## 7. Codex 호출 규약 (계약)

### 7-1. 입력 프로토콜 (계획 리뷰)

(v10 — Phase 0b 검증 결과 반영: `--output-schema` 로 JSON 강제 이전, 프롬프트의 스키마 inline 제거)

```bash
TS=$(date +%s)
TASK_ID="<task-id>"   # 실제 호출부에서 주입
RUN_ID="plan:20260418T142300Z:01HFABC:1"   # 예약 후 state 에 먼저 기록된 유일 id
mkdir -p .cache/codex-reviews

# hard timeout provider 필수 (§2-2, §13)
if command -v timeout >/dev/null; then T="timeout 60"
elif command -v gtimeout >/dev/null; then T="gtimeout 60"
else T="python3 scripts/timeout_wrapper.py 60"
fi

# --output-schema 로 JSON 강제 (§7-3-2). heredoc 은 unquoted EOF 로 ${VAR} 치환 허용.
$T codex exec \
   --cd "$(pwd)" \
   --output-schema .claude/schemas/plan-review.json \
   > ".cache/codex-reviews/plan-${TASK_ID}-${TS}.json" \
   2> ".cache/codex-reviews/plan-${TASK_ID}-${TS}.stderr" <<EOF
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
[출력] CLI 의 --output-schema 가 JSON 포맷을 강제한다. 프롬프트에서는 형식을 다시 기술하지 않는다.
[필수 필드] 응답 최상위 "run_id" 는 반드시 "${RUN_ID}" 와 문자 그대로 일치. items[].id 는 1부터 시작해 본 응답 내에서만 유일.
EOF
```

> **v10 수정 핵심**: Phase 0b 에서 `codex exec --output-schema <FILE>` 가 5회 호출 5/5 JSON 파싱 성공 (100%) 으로 검증됨. 네이티브 스키마 강제를 1순위로 쓰고, 프롬프트의 `[스키마]` inline 과 `[출력 형식] JSON 강제` 지시는 제거 — 중복 지시가 오히려 모델을 혼란시킬 수 있음. 프롬프트에는 도메인 컨텍스트 (역할/원칙/체크 항목/run_id 일치) 만 남긴다.
>
> **v3 이후 유지**: heredoc 은 `<<EOF` (unquoted) — `${TASK_ID}`/`${RUN_ID}` 치환을 위해 필수. quoted `<<'EOF'` 는 placeholder 미치환 버그 원인 (F4).

### 7-2. 입력 프로토콜 (diff 리뷰)

(v10 — `--output-schema` 로 JSON 강제 이전 + §7-1 과 일관)

```bash
TS=$(date +%s)
TASK_ID="<task-id>"
RUN_ID="work:20260418T161000Z:01HFABC:1"   # 예약 후 state 에 먼저 기록된 유일 id
mkdir -p .cache/codex-reviews .cache/diffs

# hard timeout provider 필수 (§2-2, §13)
if command -v timeout >/dev/null; then T="timeout 60"
elif command -v gtimeout >/dev/null; then T="gtimeout 60"
else T="python3 scripts/timeout_wrapper.py 60"
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

# --output-schema 로 JSON 강제 (§7-3-2)
$T codex exec \
   --cd "$(pwd)" \
   --output-schema .claude/schemas/diff-review.json \
   > ".cache/codex-reviews/diff-${TASK_ID}-${TS}.json" \
   2> ".cache/codex-reviews/diff-${TASK_ID}-${TS}.stderr" <<EOF
[역할] PeakCart 프로젝트의 시니어 코드 리뷰어
[참조 가능 파일] ${DIFF_PATH}, docs/plans/${TASK_ID}.md, docs/adr/
[체크 항목]
  - 계획서 의도와의 일치
  - 버그, race condition, null/empty 처리
  - 시큐리티 (입력 검증, 권한, 시크릿 노출)
  - 테스트 커버리지
  - 컨벤션 (네이밍, 패키지 위치)
[ADR 인덱스 핵심] (§7-1 동일 inline 주입)
[출력] CLI 의 --output-schema 가 JSON 포맷을 강제한다. 프롬프트에서는 형식을 다시 기술하지 않는다.
[필수 필드] 응답 최상위 "run_id" 는 반드시 "${RUN_ID}" 와 문자 그대로 일치. items[].id 는 1부터 시작해 본 응답 내에서만 유일.
EOF
```

> **F2 수정 핵심** (v2 에서 유지): 기존 `git diff main...HEAD` 는 "main 과 HEAD 의 공통 조상부터 HEAD 까지 커밋된 변경" 만 잡음. 첫 구현 직후 working tree 만 수정된 상태에선 빈 결과. 변경된 `git diff "$BASE"` 는 working tree 변경 + 미커밋 + 미스테이징 모두 포함.
>
> **F6 수정 핵심** (v3 신규): v2 는 `origin/main` 하드코딩. main 이 아니거나 (master, develop 등) origin/HEAD 가 stale 하면 diff 자체가 잘못됨. v3 는 origin/HEAD → git config (`peakcart.baseBranch`) → 환경변수 (`PEAKCART_BASE_BRANCH`) → 폴백 'main' 순서로 발견.

### 7-3. 출력 프로토콜 (강제 JSON 스키마) — v10: 네이티브 스키마 강제 이전

**강제 수단**: `codex exec --output-schema <FILE>` (Phase 0b 검증, 5/5 성공). 파일 위치는 `.claude/schemas/plan-review.json`, `.claude/schemas/diff-review.json` (§7-3-2 참조).

**샘플 출력**:
```json
{
  "run_id": "work:20260418T161000Z:01HFABC:1",
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
| `run_id` | ✓ (v4) | 기본 형식은 `"{command}:{utc-ts}:{session_id}:{attempt}"`, split chunk 는 `...:cN`. 호출 전 state 에 예약된 값과 동일해야 함 |
| `summary` | ✓ | 1줄 |
| `items[].id` | ✓ | 정수 (해당 run 내에서만 유효, 1부터 시작 — run_id 와 함께 써야 전역 유일) |
| `items[].severity` | ✓ | `P0` (머지 차단) / `P1` (강력 권고) / `P2` (nit) |
| `items[].category` | ✓ | `architecture` / `bug` / `security` / `test` / `doc` / `style` / `convention` |
| `items[].file` | diff 리뷰만 | 경로 |
| `items[].line` | diff 리뷰만 | 정수 |
| `items[].finding` | ✓ | 1~2줄 |
| `items[].suggestion` | ✓ | 1~2줄, ADR/문서 인용 권장 |

> **F2 수정 핵심**: `items[].id` 만으로는 호출 간 유일성이 없음. 오케스트레이터는 호출 전 유일한 `run_id` 를 예약하고, 프롬프트에 "응답 JSON 최상위에 `run_id: \"<값>\"` 를 그대로 포함" 명령을 추가한다. 복합 키 `{run_id}:{id}` 가 audit 및 state 저장용 정체성.

### 7-3-2. JSON Schema 파일 (v10 신설)

**핵심 제약**: **모든 `object` 에 `"additionalProperties": false` 필수**. OpenAI Structured Outputs 스펙 준수 요건이며 빠뜨리면 `codex exec --output-schema` 가 `invalid_json_schema` 로 **exit 1**. Phase 0b 에서 검증됨.

**`.claude/schemas/plan-review.json`** (계획 리뷰 — `file`/`line` 없음):
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["run_id", "summary", "items"],
  "properties": {
    "run_id": { "type": "string" },
    "summary": { "type": "string" },
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "severity", "category", "finding", "suggestion"],
        "properties": {
          "id": { "type": "integer", "minimum": 1 },
          "severity": { "type": "string", "enum": ["P0", "P1", "P2"] },
          "category": {
            "type": "string",
            "enum": ["architecture", "bug", "security", "test", "doc", "style", "convention"]
          },
          "finding": { "type": "string" },
          "suggestion": { "type": "string" }
        }
      }
    }
  }
}
```

**`.claude/schemas/diff-review.json`** (diff 리뷰 — `file`/`line` 필수):
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["run_id", "summary", "items"],
  "properties": {
    "run_id": { "type": "string" },
    "summary": { "type": "string" },
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "severity", "category", "file", "line", "finding", "suggestion"],
        "properties": {
          "id": { "type": "integer", "minimum": 1 },
          "severity": { "type": "string", "enum": ["P0", "P1", "P2"] },
          "category": {
            "type": "string",
            "enum": ["architecture", "bug", "security", "test", "doc", "style", "convention"]
          },
          "file": { "type": "string" },
          "line": { "type": "integer", "minimum": 0 },
          "finding": { "type": "string" },
          "suggestion": { "type": "string" }
        }
      }
    }
  }
}
```

**유지보수 규칙**:
- 두 스키마는 **git 추적** (`.claude/schemas/` 전체)
- `category` enum 확장 시 두 파일 동시 갱신
- `additionalProperties: false` 는 모든 object level 에 명시 (top-level + items[])
- 스키마 변경은 별도 PR 로 격리 — 기존 audit log 의 raw JSON 이 old schema 기준이므로 migration 정책이 필요할 수 있음

### 7-3-1. 프로세스 레벨 계약 (v9 신설)
- 성공 계약: `stdout` 는 JSON only 여야 하며, `stderr` 는 별도 파일로 저장
- 저장 경로: `.cache/codex-reviews/*.json`, `.cache/codex-reviews/*.stderr`
- `exit_code=0` + parseable JSON → `result=ok`
- `exit_code!=0` 이지만 parseable JSON 이 있으면 `result=error`, `error_reason=nonzero_exit_with_json` 로 기록 후 사용자에게 degraded 여부 확인
- `exit_code!=0` + empty/non-parseable stdout → `result=error`, `error_reason` 은 `usage_error` | `auth_error` | `provider_failure` | `timeout_provider_failure` | `unknown_process_failure` 중 하나로 분류 시도
- `exit_code=0` 이지만 stdout empty 면 `result=empty`
- stdout partial/truncated suspicion 이 있으면 `result=json_parse_failed`, stderr 와 함께 보존
- Phase 0b 에서 반드시 확인할 것: progress/log 가 stdout 에 섞이지 않는지, non-interactive 모드에서 exit code 의미가 안정적인지

### 7-4. diff 크기 분기 (`/work` 의 codex 호출)
| diff 크기 | 처리 |
|-----------|------|
| ~500줄 | 단일 호출, 전체 리뷰 |
| 500~2000줄 | 사용자에게 "분할 리뷰?" 확인 후 **최대 3개 chunk** 로 분할. 우선순위는 (1) 실행 코드 (2) 테스트 누락 후보 (3) 설정/문서. 나머지는 `review_plan.unreviewed_scope[]` 와 audit log 에 남김 |
| 2000줄+ | "task 가 너무 큽니다. 분할 검토 권장" 안내. 기본은 **중단 후 task 분할**. 사용자가 강행하면 상위 3 chunk 만 리뷰 + 나머지 미리뷰 범위 명시 |

- split review 는 **1개의 loop 안에서 수행되는 하위 실행**이다
- chunk 별 결과는 개별 `run_id` 로 저장하되, 상위 loop gate 는 모든 chunk 가 terminal 상태가 된 뒤에만 연다
- 일부 chunk 실패 시 `review_plan.aggregate_result` 는 `ok` 가 아닌 가장 심각한 terminal 값으로 승격한다 (`timeout` > `json_parse_failed` > `empty` > `error`)
- aggregate gate 표시는 chunk 결과를 severity 우선으로 병합해 보여주며, 사용자에게는 `cN:id` 복합 번호로 제시한다. state 저장은 chunk-local `id` + `run_id` 조합을 유지한다
- 중단 후 재개 시 `review_plan.chunks[].status` 를 보고 미완료 chunk 부터 이어간다

### 7-5. Fallback Ladder (v3 — F8 대응으로 운영 가능 수준으로 확장)

"운영 가능" 이란 실패 시 사용자에게 "어떻게 할까요?" 만 던지는 게 아니라 **표준 복구 경로**가 있는 것. 모든 ladder 는 (a) 실패 감지 → (b) 자동 복구 시도 → (c) 여전히 실패 시 사용자 개입의 3단.

#### 7-5-A. JSON 파싱 실패 ladder
1. **재파싱**: 출력이 ```json ... ``` 블록으로 감싸졌을 가능성 → 코드블록만 추출해 재파싱 1회
2. **raw 요약**: 그래도 실패 시 raw 출력 앞 3KB 만 사용자에게 제시, 전체는 `.cache/codex-reviews/*.raw.txt` 에 저장
3. **자연어 게이트**: 사용자가 "1, 3번만 반영" 같이 지시 → Claude 가 해석
4. **다음 호출 강화**: 다음 프롬프트 맨 앞에 `[이전 출력이 JSON 이 아니었음. JSON 스키마 외 텍스트 금지]` 삽입
5. 현재 run 의 `result=json_parse_failed` 를 state/audit 에 기록하고 `review_runs[]` 로 finalize 한 뒤 `pending_run` 제거
6. **연속 2회 실패** → §7-7 임계치 발동
7. 사용자가 degraded 진행을 승인하면 `degraded_accepted=true`, `degraded_reason`, `risk_level`, `risk_signals` 를 같은 run 엔트리에 기록

#### 7-5-B. Codex timeout ladder
1. **1회 timeout**: 경고만 표시, 현재 run 을 `timeout` 으로 finalize 한 뒤 잔여 예산이 있으면 재호출
2. **2회 timeout**: diff 가 큰지 확인 (`wc -l`). 500줄 초과면 §7-4 분할 제안. **분할 진입 시 timeout 재시도는 중단**하고 남은 예산을 chunk 에 배분
3. **3회 timeout** 또는 **잔여 예산 소진** → `review skip mode`: GP-2b/GW-2b 로 직행, 사용자에게 "codex 응답 없음. degraded review 로 진행?" 확인. audit log 에 `review_skipped: timeout` 기록
4. **high-risk degraded 규칙**: `risk_level=high` 이면 기본 선택지는 `중단/재시도` 이고, `계속 진행` 은 사유 입력 시에만 허용
5. degraded 승인 시 동일 run 을 `result=timeout`, `degraded_accepted=true` 로 finalize 하며 clean review 와 구분해 저장

#### 7-5-C. Push 실패 ladder (`/ship` Step 7)
1. **감지**: `git push` exit code ≠ 0
2. **분류**:
   - `fetch first` / non-fast-forward → `git fetch origin` 후 사용자에게 rebase 여부 확인 (자동 rebase X)
   - auth failure → 사용자에게 인증 갱신 요청, 자동 재시도 X
   - network → 30초 후 1회 재시도
3. 실패 상태 state 에 `push_status: "failed"`, `ship_resume_cursor: "push.failed"` 기록 → 다음 호출 시 Step 7 부터 재진입
4. 네트워크 자동 재시도 성공 시 즉시 state 재기록: `push_status="pushed"`, `ship_resume_cursor="pr.pending"`, `stage=ship.pushed`

#### 7-5-D. PR 생성 실패 ladder (`/ship` Step 8)
1. **본문 보존**: PR 본문은 이미 Step 5 에서 `.cache/pr-body-${TASK_ID}.md` 에 저장됨 → 재시도 시 재사용 (재생성 금지)
2. **선조회**: 재시도 전 항상 `gh pr list --head <branch>` 로 기존 PR 존재 여부 확인. 있으면 create 대신 URL 채택
3. **분류**:
   - `gh: command not found` / 미설치 → **수동 PR 생성 안내로 전환 (기본)**. D 경로 재검토는 별도 설계 변경 논의가 있을 때만
   - `gh auth` 만료 → 사용자에게 `gh auth login` 안내 + 재시도 선택
   - API rate limit → `Retry-After` 헤더 확인 후 대기 시간 고지, 수동 재시도
   - 네트워크/5xx → 60초 후 1회 재시도
4. 재시도 시 `gh pr create --body-file .cache/pr-body-${TASK_ID}.md` 로 동일 본문 유지. 실패 run 은 `ship_resume_cursor: "pr.failed"` 로 유지
5. 3회 실패 시 사용자에게 "수동 PR 생성 안내 (본문 파일 경로 제시) / 종료" 선택. TASKS 는 미갱신
6. 자동/수동 재시도 성공 시 즉시 state 재기록: `pr_url` 저장, `ship_resume_cursor="done.pending"`, `stage=ship.pr.created`

#### 7-5-E. Consistency-hints 실패 ladder (`/ship` Step 2 / GS-1)
1. 스크립트가 정상 실행되어 warnings 를 반환했으면 깨진 참조 목록 제시
2. 스크립트 실행 자체가 실패했으면 실패 원인(stderr 요약, exit code) 제시 후 사용자 선택: (a) 환경 수정 후 재실행 / (b) 무시하고 진행 (사유 필수) / (c) 종료
3. warnings 기반 실패면 사용자 선택: (a) 지금 수정 (편집 후 재실행) / (b) 무시하고 진행 (사유 필수 입력) / (c) 종료
4. (b) 선택 시 사유는 audit log 에 append, PR 본문에 "Skipped consistency checks" 섹션 자동 추가

### 7-6. 비용/빈도 제어 (v10 — Phase 0b 검증 결과로 tokens 파싱 형식 확정)
- 한 슬래시 커맨드 내 codex **기본 시도 수** 상한: **3회**
- 상한 도달 시 사용자에게 "더 호출할까요?" 명시 확인
- 분할 리뷰는 **잔여 예산 내에서만** 허용. 예: 2회 timeout 후 남은 예산이 1회면 chunk 1개만 리뷰하거나 task 분할로 중단
- **비용 측정**:
  - **1순위**: `codex exec` stderr 에 `tokens used\n<숫자>` **두 줄** 형식으로 토큰 수가 노출됨 (Phase 0b 검증). 파싱 예:
    ```bash
    TOKENS=$(grep -A1 "tokens used" "${STDERR_PATH}" | tail -1 | tr -d ' ')
    ```
  - `codex exec --json` (JSONL 이벤트 스트림) 은 더 풍부한 metadata 를 줄 가능성 — 후속 검증 대상으로 보류
  - **USD 비용**: CLI 가 직접 제공하지 않음. 모델별 pricing table 로 환산 (프록시 지표)
  - **fallback** (metadata 미노출 시) — 프록시 지표 (input_bytes/output_bytes/duration_ms) 자동 기록
- 큰 diff 분할로 호출 횟수 부풀리는 것 회피 — 상한을 넘기면 기본은 중단 후 task 분할 신호로 해석

#### 7-6-1. `_metrics.tsv` 스키마 (v4 — F5 반영으로 명시화)

회고·비용분석·timeout 원인분석을 할 수 있도록 차원을 늘린 TSV. 호출마다 1줄 append. 헤더는 최초 1회만.

**컬럼 (순서 고정, tab 구분)**:

| # | 컬럼 | 타입 | 값/예시 | 용도 |
|---|------|------|---------|------|
| 1 | `ts` | ISO8601 | `2026-04-19T14:23:00Z` | 시간 축 정렬 |
| 2 | `task_id` | string | `task-3-4` | 과제 단위 집계 |
| 3 | `command` | enum | `plan` \| `work` | codex 호출이 발생하는 커맨드만. `/ship` 은 codex 를 호출하지 않으므로 제외 (shell precheck/commit/push/PR 은 본 메트릭 대상 아님) |
| 4 | `run_id` | string | `plan:2026...:sess:1` \| `work:2026...:sess:2` | state `review_runs[].run_id` 와 조인 키 |
| 5 | `loop` | int | `1`~`3` | command 내 몇 번째 루프인지 |
| 6 | `input_type` | enum | `plan` \| `diff` \| `diff-split` | `/work` 의 분할 호출(§7-4) 은 `diff-split` |
| 7 | `diff_lines` | int | `1234` \| `-1` | diff 리뷰일 때 대상 줄 수. plan 이면 -1 |
| 8 | `input_bytes` | int | heredoc 본문 + 참조 파일 크기 합 | 프록시 비용 |
| 9 | `output_bytes` | int | 응답 JSON 파일 크기 | 프록시 비용 |
| 10 | `duration_ms` | int | wall clock | 성능/timeout 원인 분석 |
| 11 | `result` | enum | `ok` \| `json_parse_failed` \| `timeout` \| `empty` \| `error` | 호출 결과 분류 |
| 12 | `fallback_mode` | enum | `none` \| `retry_strict` \| `review_skip` \| `split` \| `raw_gate` | §7-5 ladder 중 어떤 분기로 복구됐는지 |
| 13 | `tokens_in` | int \| `` | codex metadata 있을 때만 | 1순위 비용 |
| 14 | `tokens_out` | int \| `` | 동상 | 1순위 비용 |
| 15 | `cost_usd` | decimal \| `` | 동상 | 1순위 비용 |

**예시 행** (헤더 + 2줄):
```
ts	task_id	command	run_id	loop	input_type	diff_lines	input_bytes	output_bytes	duration_ms	result	fallback_mode	tokens_in	tokens_out	cost_usd
2026-04-19T14:23:00Z	task-3-4	plan	plan:20260419T142300Z:01HFABC:1	1	plan	-1	4821	1207	8234	ok	none			
2026-04-19T16:10:07Z	task-3-4	work	work:20260419T161007Z:01HFABC:1	1	diff	1234	52018	3402	21033	timeout	review_skip			
```

**집계 쿼리 예시** (회고용):
- task 별 총 호출/비용: `awk -F'\t' '$2=="task-3-4"{c++;b+=$9} END{print c,b}'`
- fallback 발동률: `awk -F'\t' 'NR>1 && $12!="none"' _metrics.tsv | wc -l`
- timeout 원인 diff 크기 분포: `awk -F'\t' '$11=="timeout"{print $7}' _metrics.tsv | sort -n`

> **F5 수정 핵심**: v3 는 "프록시 지표를 기록한다" 수준이었고 스키마 미정. 실제 운영 시 비용 폭증/timeout 반복의 원인 분석 불가. v4 는 컬럼 고정 + 분석 쿼리 예시까지 제공.

#### 7-6-2. `gate-events.tsv` 스키마 (v8 신설)

게이트 피로와 품질 저하의 균형을 직접 측정하기 위한 별도 이벤트 로그. 게이트 평가마다 1줄 append.

| 컬럼 | 의미 |
|------|------|
| `ts` | ISO8601 시각 |
| `task_id` | 과제 id |
| `gate_id` | `GP-2`, `GW-2b` 등 |
| `gate_type` | `always` \| `conditional` |
| `command` | `plan` \| `work` \| `ship` |
| `run_id` | Codex 관련 게이트면 해당 run, 아니면 빈값 |
| `shown` | 실제 사용자에게 노출됐는지 |
| `auto_passed` | 자동 통과됐는지 |
| `result` | `ok` \| `degraded` \| `warning` \| `blocked` |
| `user_choice` | `[1]`, `continue`, `stop` 등 |
| `response_ms` | 사용자 응답 시간 |
| `default_selected` | 기본 옵션 선택 여부 |
| `ignored_p0_count` | 무시된 P0 수 |
| `degraded_accepted` | degraded review 승인 여부 |
| `risk_level` | `low` \| `high` |
| `risk_signals` | 고정 집합에서 선택한 comma-separated 값 |
| `reason` | 사유 텍스트 또는 enum |

기록 규약:
- 게이트 평가 1회당 정확히 1행
- `shown=false` 이면 `user_choice=""`, `response_ms=0`, `default_selected=false`
- `auto_passed=true` 는 `shown=false` 와 함께만 허용
- 같은 gate 가 다시 노출되면 별도 행으로 기록
- `risk_signals` 허용 값은 `diff_large`, `security_touched`, `auth_touched`, `payment_touched`, `config_touched`, `split_review`, `adr_boundary_change` 로 고정
- 복수 값일 때는 comma-separated, 사전순 정렬 고정

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
- GP-2/GW-2 자동 통과 시에도 다음 1줄은 항상 노출:
  > "Codex review auto-passed (`<run_id>`): P0/P1 없음, P2 N건. [세부 보기] [강제 검토]"
- P2 만 반복되는 경우에도 완전 은닉하지 않음:
  - 동일 task 내 P2 가 3건 이상 누적되거나 동일 file/category 반복 시 요약 노출 1회
  - `/ship` 직전 "이번 사이클 P2 요약" 을 선택적으로 보여 backlog 분리 여부 판단

---

## 9. 위험 요소 / 트레이드오프

### 9-1. 식별된 위험 (v2 — R10~R12 추가, R5/R9 보강)

| ID | 위험 | 발생 가능성 | 영향 | 대응 |
|----|------|------------|------|------|
| R1 | codex CLI non-interactive 모드가 안정적이지 않음 | 중 | **자동화 자체 불가** | Phase 0 검증 필수, 안 되면 대안 B (플러그인) fallback. §5-2 D 재진입 경로 |
| R2 | codex 출력 형식 불안정 (JSON 안 지킴) | 중~높 | 파싱 실패 빈발 | §7-5 fallback (raw 제시) + 프롬프트 보강 + §7-7 임계치 |
| R3 | codex API 비용 폭증 | 낮~중 | 운영비 부담 | 호출 총시도 상한 3회 + 분할 상한 3 chunk + 프록시 지표 (§7-6) + Phase 0 에 per-cycle soft cap 확정 |
| R4 | 큰 diff 컨텍스트 초과 | 중 | 리뷰 실패 | §7-4 분할 처리 |
| R5 | 자동화로 사용자 검토 소홀 | 높 | **품질 저하 (가장 큰 비기능적 위험)** | §8-3 ㅇㅋ 방지 장치 + 게이트 default 안전 + G1b 별도 측정으로 가시화 |
| R6 | codex 가 ADR/Layer 1 컨벤션 모름 | 중 | 부적절한 지적 양산 | §7-8 프롬프트 원칙 + §7-1 ADR 인덱스 inline 주입 |
| R7 | Bash 출력 캡처가 길어 Claude 컨텍스트 오염 | 중 | 후속 응답 품질 저하 | JSON 출력은 파일로 받고 필요한 부분만 Read |
| R8 | 슬래시 커맨드 내부 로직이 복잡해져 유지보수 부담 | 중 | 장기적 부채 | 커맨드 1개당 200줄 이내 유지, 공통 로직은 별도 스크립트로 분리 |
| R9 | 중단 후 재개 시 상태 오추정 | 낮~중 | 작업 누락/중복 | §6-4 state 파일 + TASKS `🔄` + plan 파일 3중 교차 검증 + 원자 저장 |
| **R10** | **다른 세션에서 동시 실행** (예: 사용자가 두 터미널에서 `/work` 호출) | 낮 | 브랜치/state 충돌, 산출물 손상 | §6-4-4 lock **디렉토리** (mkdir 원자성, v3 F5 반영). PID 기반 stale 처리 |
| **R13** | `/ship` 재개 시 중복 커밋/중복 push (v3 F2) | 중 | 브랜치 히스토리 오염, PR 충돌 | §6-3-3 stage 6단 세분화 + `created_commits[]`/`push_status`/`pr_url` 로 재진입 매트릭스 |
| **R14** | base branch 가 `main` 이 아니거나 origin/HEAD 가 stale (v3 F6) | 낮~중 | diff 자체가 잘못됨 → 리뷰 오류 | §7-2 base branch discovery 4단 폴백 |
| **R15** | 슬래시 커맨드 heredoc quoting 오류로 placeholder 미치환 (v3 F4) | 중 | codex 가 존재하지 않는 파일 탐색 → 무내용 응답 | §7-1 `<<EOF` (unquoted) 로 통일, `${TASK_ID}` 주입 |
| **R16** | degraded review 를 clean review 로 오인 | 중 | false negative 로 품질 저하 | GP-2b/GW-2b 신설, timeout/empty/JSON 실패 자동 통과 금지 |
| **R17** | 원격 부작용 후 로컬 state 미기록 | 중 | 중복 PR/커밋 | PR 선조회 + commit_plan + 원자 저장 |
| **R18** | `gh` CLI 미설치/인증 만료/권한 부족 | 중 | `/ship` 자동화 불가 | §2-2 / §7-5-D / §13 에 선행 검증 및 수동 PR fallback 명시 |
| **R19** | P2 자동 통과가 장기 품질 저하를 숨김 | 중 | 누적된 경미 결함 방치 | §8-3 P2 누적 요약 노출 + gate-events 측정 |
| **R20** | hard timeout provider 부재로 Codex 호출이 hang | 중 | timeout ladder 무력화, 세션 정지 | §2-2, §7-1/§7-2, §13 Phase 0c 에서 필수 provider 확보 |
| **R21** | split review 상태가 복구되지 않아 중복/누락 리뷰 발생 | 중 | `/work` 재개 불안정 | `review_plan` + chunk status + aggregate_result 도입 |
| **R22** | stdout/stderr 혼합 또는 nonzero exit + JSON 출력 | 중 | raw JSON 신뢰성 붕괴 | §7-3-1 프로세스 계약 + stderr 별도 보존 |
| **R11** | **codex 가 매 호출마다 ADR 컨벤션 zero 에서 시작** | 높 | 부적절한 지적, 일관성 결여 | §7-1 ADR 인덱스 inline 주입 (R6 와 짝). 부족 시 핵심 ADR 본문도 inline |
| **R12** | **F1 (슬래시 커맨드 실행 모델) 가정 오류** | **중~높** | **본 설계 전면 재검토** | §13 Phase 0 최우선 검증 + §5-2 D 재진입 경로 사전 정의 |

### 9-2. 의도적으로 감수하는 트레이드오프 (v4 — F6 대응으로 에러 정책 정밀화)
- **모델 다양성을 Codex 1개에 한정** — Gemini 등 추가 안 함. 2축으로 충분한지는 Phase 4 후 평가
- **`.cache/` 자동 정리 없음** — 디스크 압박 시 사용자가 수동 정리 (자동 정리는 감사 흔적 손실 위험)
- **budget enforcement 는 완전 자동 차단 대신 soft cap + 명시 확인** — Phase 0 에 per-cycle soft cap 을 숫자로 고정하고, 초과 시 자동 진행 금지
- **상태를 바꾸는 자동 복구는 없음. 단, 안전한 재시도는 일부 허용** (v4 명시화)
  - **허용되는 자동 재시도** (멱등 / 상태 무변경): §7-5-C 의 네트워크 push 실패 30초 후 1회 재시도, §7-5-D 의 5xx/네트워크 PR 생성 60초 후 1회 재시도, §7-5-B 의 timeout 1회 재호출, §7-5-A 의 JSON 재파싱 1회
  - **금지되는 자동 행동**: 자동 rebase, 자동 force-push, `/done` 자동 재시도 (TASKS.md SSOT 변경), 인증 실패 시 자동 login 시도, 같은 원인 실패 3회 이상 재시도
  - 판단 기준: **"실패 전 상태로 되돌릴 수 있고, 1회 재시도가 사용자 의사결정을 바꾸지 않으면 자동. 아니면 사용자"**
  - v3 의 "에러 시 자동 복구 없음" 은 §7-5 ladder 와 모순이었음 → v4 에서 정합
- **lock 은 강한 분산 락이 아님** — `flock(1)` 이 더 강하나 macOS 기본 미포함. 본 안은 단일 사용자 전제에서 `mkdir` 원자성 + 수동 stale 해제 절차까지를 현실적 상한으로 둠

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
> **stable id 필수 (v4 — F3 반영)**: 각 항목은 `P1.`, `P2.`, ... 같은 영구 식별자로 시작. 순서가 바뀌거나 중간 항목이 삽입/삭제돼도 id 는 재사용하지 않음. 완료된 id 는 state 의 `completed_plan_items[]` 에 기록되어, 계획서 편집 후 재개해도 "어느 항목을 했는지" 가 유지됨.

- [ ] **P1.** 항목 1
- [ ] **P2.** 항목 2
- [ ] **P3.** ... (신규 추가는 기존 id 다음 번호로)
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

> **결과에 따라**: Q0-1~Q0-5 가 모두 운영 가능 수준으로 답돼야 F 채택 유지. 일부 제약 있으면 §6 우회안 추가. 본질적 불가능이면 §5-2 의 D 재진입 (외부 하네스).

### 11-1. Codex CLI 명세 (Phase 0b 완료 — v10)

**Phase 0b 결과 요약** (2026-04-19, 5회 호출 검증):

- **A1** (= Q1): `codex exec` 가 non-interactive 서브커맨드. stdin 으로 프롬프트 수신
- **A2** (= Q2): `codex exec` 자체가 non-interactive. 별도 플래그 불필요
- **A3** (= Q3): `--cd <path>` 플래그 사용 (`-C` 아님)
- **A4** (= Q4): 사용자는 **ChatGPT 로그인** 사용 중 (`~/.codex/auth.json`). API key env 아님. `codex login status` 로 확인
- **A5** (= Q5): `--output-schema <FILE>` 네이티브 지원 → 5/5 JSON 파싱 성공 (100%), 평균 wall clock 9초. 단, **모든 object 에 `additionalProperties: false` 필수** (§7-3-2)
- **A6** (= Q6): stderr 에 `tokens used\n<숫자>` 2줄 형식. USD 비용은 CLI 미노출 (§7-6)
- **A6-1** (= Q6-1): 추상명 불필요 — 인터페이스 확정됐으므로 `codex exec --cd ... --output-schema ...` 를 직접 사용

모든 Codex 호출 관련 open question 은 resolved. 후속 검증 대상: `--json` (JSONL) 이벤트 스트림이 제공하는 추가 metadata.

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
  - **default 제안**: 자동 차단이 아니라 **soft cap 초과 시 명시 확인**. hard cap 은 월 예산이 생긴 후 도입
- Q15-1. `attempts_by_command.*` 와 `codex_attempts_cycle_total` 의 기본 상한을 각각 몇으로 둘 것인가?
  - **v9 default**: `attempts_by_command.plan=3`, `attempts_by_command.work=3`, `codex_attempts_cycle_total=5`

### 11-6. 게이트 UX
- Q16. §8-1 의 5분기 선택지가 적정한가? 더 단순화 (3분기) / 세분화?
- Q17. P0 무시 시 사유 입력을 강제하는 것이 부담인가?

### 11-7. 산출물 영속성
- Q18. `.cache/codex-reviews/*.json` raw dump 를 git 영구 저장할 가치가 있는가? (현 default: gitignore)
- Q19. P0 무시 사유 (audit log `docs/plans/.audit/<task-id>.md` 의 해당 엔트리) 를 PR 본문에 자동 포함할까? (§6-3-3 Step 5 default: 포함)

### 11-8. fallback 시나리오
- Q20. R1 (codex non-interactive 안정성 부족) 발생 시 어디까지 후퇴할까? — 플러그인 모드 / 외부 하네스 / 본 안 폐기
- Q20-1. fallback 기준을 장애 유형별로 고정할 것인가? (`슬래시 모델 불가 => D`, `Codex CLI만 불안정 => B/수동`, `gh 문제 => /ship 수동`)

### 11-9. v2 신설 — 추가 의사결정 항목
- **Q21** (A2). codex 호출 시 ADR 인덱스를 inline 주입하는 것 (§7-1) 이 충분한가, 아니면 핵심 ADR 본문 (예: ADR-0007) 도 매번 inline 으로 박아야 하는가? 비용/품질 트레이드오프.
- **Q22** (A4). codex 가 연속 3회 무내용 응답 시 자동 fallback 정책 (§7-7) 이 적정한가? 더 엄격 (1회) / 더 관대 (5회) ?
- **Q23** (A1 / R10). 동시성 lock (§6-4-4) 을 PID 기반 단순 구현으로 충분한가? 단일 사용자 전제가 깨지는 시나리오가 있는가?
  - **v7 default**: PID 단독은 불충분. `session_id` + 시작 시각 + command metadata 를 lock 에 함께 기록
- **Q24**. `/ship` 성공 후 state.json 처리 — `docs/plans/.archive/` 로 이동 vs 즉시 삭제? archive 의 장기 가치는?
- **Q25** (F4 보강). `/done` 을 PR 생성 성공 후로 옮긴 결과, push 는 됐지만 PR 생성이 실패한 경우 (예: gh CLI 인증 만료) 의 처리 — 자동 재시도 vs 사용자에게 수동 처리 위임? (v3 §7-5-D 에서 "수동 재시도 + 본문 재사용" default)
  - **v7 default**: PR 재시도 전 항상 `head=<branch>` 선조회. 이미 열려 있으면 create 금지, 기존 URL 채택

### 11-10. v3 신설 — 리뷰 2차 반영 후 추가 항목
- **Q26** (F7 / 게이트 피로). 게이트를 "항상 필요한 승인" (GW-1 브랜치명, GS-3 PR 본문 등 되돌릴 수 없는 행동 직전) 과 "이상 시에만 개입" (GS-1 consistency hints — 문제 없으면 자동 통과) 으로 분리할까? 분리 시 평상시 decision prompt 수가 절반 수준으로 줄어들지만, "자동 통과" 가 R5 (ㅇㅋ 자동화) 와 충돌할 수 있음.
- **Q27** (F2 보강). `/ship` 재진입 시 `created_commits[]` 와 `git log` 비교로 중복 커밋을 방지하는데, 사용자가 중간에 수동으로 amend/rebase 한 경우 sha 불일치 감지 후 어떻게 처리할까? — 자동 재계산 vs 사용자 확인.
  - **v7 default**: `commit_plan[]` 의 partition_id / expected subject 기준으로 검출하고, sha 불일치 시 자동 재계산 금지 + 사용자 확인
- **Q28** (F9~F11 / 범용화 보류). 본 안은 PeakCart 전용 reference design. Phase 4 end-to-end 검증 후 다음 프로젝트 적용 시점이 오면 (a) 현 문서를 복제해 fork / (b) Core + Adapter + Profile 로 재구조화 중 어느 쪽이 합리적인가? — 지금 결정하지 않고 **DEFERRED** (§3-3 에 추가).
- **Q29** (v8). degraded review 를 위험도 기반으로 차등 처리할 것인가? 예: `/work` 에서 `diff_lines > X`, `security/auth/payment/config` touched, split 발생 시 기본값을 `중단/재시도` 로 상향
  - **v9 default**: `diff_lines >= 800` 또는 `split_review=true` 또는 `auth|security|payment|config|infra` touched 면 `high-risk`

---

## 12. 검증 계획

### 12-1. 단계별 검증 (v2 — Phase 0 에 슬래시 커맨드 실행 모델 검증 추가)
| Phase | 내용 | 성공 기준 |
|-------|------|----------|
| **-1** (v9 신설) | **베이스라인 수집** | 기존 수동 방식으로 실제 task 3개 측정: 정상 경로 2개 + high-risk 후보 1개. invocation/decision/time/manual fallback/compliance 로그 확보 |
| **0a** (신설) | **슬래시 커맨드 실행 모델 검증** | §11-0 의 Q0-1~Q0-5 답변 확보. 특히 nested slash, 인터럽트, stdout/stderr truncation 정책 명확화 |
| 0b | codex CLI 명세 확정 | §11-1 의 Q1~Q6, Q6-1 답변 확보 + JSON 강제 5회 호출 성공률 측정 |
| 0c | macOS / `gh` / git 운영 환경 확인 | hard timeout provider(`timeout`/`gtimeout`/python wrapper), `gh --version`, `gh auth status`, origin remote, push 권한 검증 |
| 1 | `/plan` 단독 검증 | 가짜 task 1개로 한 사이클, 산출물 존재/형식 확인, state.json 정합 |
| 2 | `/work` 단독 검증 | 작은 실제 task 로 branch + diff (`git diff $BASE`) + 리뷰 + 재개 시뮬레이션 |
| 3 | `/ship` 단독 검증 | 위 결과를 커밋/PR 까지, PR URL 반환, /done 이 PR 성공 후에만 동작하는지 확인 |
| 4 | end-to-end | 실제 다음 Phase 3 task 1개로 전체 사이클 |
| 5 (선택) | 안정화 | 1주일 사용 후 회고, 프롬프트/게이트 조정 |

> **Phase 0a 가 결과 C (실행 모델 본질적 불가능)** 이면 §13 의 Phase 1 이후 모두 무효. 현재 문서를 차기 버전으로 전면 재설계 (§5-2 D 재진입).

### 12-2. 회귀 검증
기존 `/sync`, `/next`, `/done` 단독 호출 각 1회 정상 동작 확인.

### 12-3. 정량 측정 항목 (v2 — F5 KPI 분리 + F6 프록시 지표)

**사용자 부담 지표** (G1 분할 측정):
| 지표 | 측정 방법 | 목표 |
|------|----------|------|
| **invocation 수** (G1a) | `/plan`, `/work`, `/ship` 호출 카운트 | **8 → 3** |
| **decision prompt 수** (G1b) | `gate-events.tsv` 의 `shown`, `auto_passed`, `user_choice` 집계 | 정상 경로 평균 `≤ 4`, p95 `≤ 6`. degraded 게이트는 별도 집계 |
| **수동 fallback/외부 전환 수** (G1c) | `manual_fallback_declared_count`, `external_terminal_handoff_count`, 주간 5건 샘플 회고 | 정상 경로 `0`, 주간 샘플 기준 5건 중 1건 이하 |
| **수동 복붙 수** (G2) | `manual_copy_paste_declared_count` + 주간 샘플 회고 | 정상 경로 `0` |

**시스템 품질 지표**:
| 지표 | 측정 방법 | 목표 |
|------|----------|------|
| JSON 파싱 실패율 | 호출 10회당 실패 수 | < 10% |
| 사이클당 codex 총 시도 수 | state 의 `codex_attempts_cycle_total` | 베이스라인 측정 후 soft cap 확정 |
| 사이클 총 소요 시간 | 시작~PR URL 시각차 | 베이스라인 대비 20% 이상 악화 금지 |
| degraded review 비율 | `result != ok` 인 run 비율 | 낮을수록 좋음 |
| 무내용 응답률 | `result=empty` 인 run 비율 | < 10% |
| 자동 통과율 | `gate-events.tsv` 의 `auto_passed=true` 비율 | 정상 경로 60~85%, 90% 초과 시 과자동화 경고 |
| degraded 승인율 | `degraded_accepted=true` AND `risk_level="high"` 인 행 비율 | `≤ 20%` |
| P0 무시율 | `ignored_p0_count > 0` 비율 | 낮을수록 좋음 |

**비용 지표** (1순위 → fallback):
| 지표 | 측정 방법 | 비고 |
|------|----------|------|
| 토큰 수 | codex CLI metadata (있을 시) | 1순위 |
| API 비용 | codex CLI metadata (있을 시) | 1순위 |
| 입력 byte | heredoc + 참조 파일 크기 합 | fallback 프록시 |
| 입력 lines | diff 줄 수 | fallback 프록시 |
| 출력 byte | 응답 JSON 파일 크기 | fallback 프록시 |
| 응답 시간 | wall clock | 항상 측정 |

모든 호출 메트릭은 `.cache/codex-reviews/_metrics.tsv`, 게이트 메트릭은 `.cache/codex-reviews/gate-events.tsv` 에 append. G1c/G2 는 완전 자동 수집 지표가 아니라 **compliance/self-report + 주간 샘플 회고** 기반이다.

**go / no-go 기준**:
- JSON 파싱 실패율 `>= 10%` 이면 rollout 중단
- high-risk degraded 승인율 `> 20%` 이면 게이트 정책 재설계 전 rollout 금지
- 정상 경로 decision prompt 평균 `> 4` 면 피로 절감 목표 미달
- 자동 통과율 `> 90%` 이면 통제권 약화 경고
- Phase 0 에 확정한 soft cap 을 초과한 cycle 이 20% 를 넘으면 비용 정책 재설계 전 rollout 금지
- 주간 사용자 통제감 설문(5점 척도) 평균 `< 4.0` 이면 UX 재설계

### 12-4. 정성 평가 항목
- 사용자가 매 게이트마다 의식적으로 결정했는가 ("ㅇㅋ" 함정 회피 정도)
- 리뷰 품질 — codex 가 무내용 응답을 얼마나 자주 했는가
- 산출물 (계획서, PR 본문) 의 일관성 — 사이클별 편차
- audit log (`docs/plans/.audit/<task-id>.md`) 가 회고 시 실제로 유용한가

---

## 13. 실행 순서 (구현 단계 — **합의 후**)

> 본 §13 은 §11 의 Open Questions 가 답변된 후에야 의미 있음. 지금은 참고용.

### Phase -1: 베이스라인 수집 (~30분)
- [ ] 기존 수동 방식으로 실제 task 3개 측정: 정상 경로 2개 + high-risk 후보 1개
- [ ] invocation 수, decision 수, cycle time, 수동 fallback, 수동 복붙 여부를 같은 스키마로 기록
- [ ] 이후 Phase 4 비교 기준선 확정

### Phase 0: 사전 확인 — **완료** (2026-04-19, v10 반영)
- [x] **0a. 슬래시 커맨드 실행 모델 검증** — **판정 B** (nested slash 불가 → shared script 패턴 채택)
- [x] **0b. codex CLI 명세 확정** — `--output-schema <FILE>` 5/5 성공, `--cd`, ChatGPT 로그인 인증 (§11-1 참조)
- [x] **0c. macOS / `gh` / git 환경 확인** — Python timeout wrapper 검증 완료, `gh` 인증 OK
- [ ] `.gitignore` 에 `docs/plans/*.state.json`, `docs/plans/*.lock/`, `.cache/` 추가 (Phase 1 선행 작업으로 이동)
- [ ] state atomic write 규약 (`tmp` + `mv`) 검증 (Phase 1 에서 `.claude/scripts/shared-logic.sh` 구현 시 동시 검증)
- [ ] `attempts_by_command.*` / `codex_attempts_cycle_total` / degraded risk threshold 숫자 확정 (Phase 1 전 결정 필요)

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
| Draft v4 | 2026-04-19 | 3차 리뷰 7건 전부 수용. (F1) §6-3-3 재진입 매트릭스 `ship.pr.created` 행 정정 — pr_url 있고 `done_applied==false` 면 Step 9(`/done` 재시도)로 분기, 중복 PR 생성 제거 + stage 의미 "단계 완료 후" 로 재정의. (F2) §7-3 스키마 최상위 `run_id` 추가 + §6-4-2 state 를 `review_runs[]` 구조로 전환 — loop 간 `items[].id` 충돌 해소. (F3) §10-1 계획서 작업 항목 stable id 규약 (`P1.`, `P2.`, ...) 강제 + `completed_plan_items[]` 값을 숫자에서 string id 로. (F4) §6-2 게이트 표에 `always`/`conditional` 유형 열 추가 — GP-1/GP-2/GW-2/GS-1 은 이상 신호 시에만 개입, 정상 경로에서 자동 통과. (F5) §7-6-1 신설 `_metrics.tsv` 15 컬럼 스키마 고정 + 집계 쿼리 예시. (F6) §9-2 "자동 복구 없음" → "상태 무변경 1회 재시도만 허용, 상태 변경 자동 복구 금지" 로 정밀화해 §7-5 와 정합. (F7) 흐름도 `/tmp/...` → `.cache/codex-reviews/...`, 파일 위치 표/부록 C lock 을 디렉토리 표기로 정정. `.gitignore` 항목도 `*.lock/` 로 정정 | Claude |
| Draft v5 | 2026-04-19 | 4차 리뷰 6건 전부 수용 — v4 에서 도입한 구조를 문서 전체에 전파하는 드리프트 정리가 핵심. (F1) §6-3-1/6-3-2/6-3-3 절차 본문에 §6-2 conditional 게이트 분기를 직접 삽입: GP-1/GP-2/GW-2 는 "P0/P1 ≥ 1건 시에만 게이트", GS-1 은 "warnings ≥ 1건 시에만 게이트" 로 명시. (F2) §7-1/§7-2 프롬프트 본문에 `[출력 필수] run_id: "${RUN_ID}"` 지시문 + 호출 스크립트에 `RUN_ID` 변수 추가 — state `review_runs[]` 와의 조인 키 보장. (F3) §6-3-1 `/plan` 처리 단계 전면 재작성 — `loop_count` 단일 카운터 → `loop_count_by_command.plan`, plan 리뷰 결과도 `review_runs[]` append, `run_id=plan#N` 도입해 `/work` 와 대칭. (F4) §6-3-3 본문의 `stage=X: do Y` 표기 → "do Y → 성공 시 stage=X 기록" 으로 변경 + 상단에 "stage 는 단계 완료 후" 규약 재확인. (F5) §6-4-1 `.gitignore` 블록의 `docs/plans/*.lock` → `*.lock/` 로 통일, 부록 C 와 일치. (F6) §3-1 G1b + §12-3 decision prompt 수 추정을 v4/v5 conditional 정책 기준 "정상 경로 3~4회" 로 갱신. **범용화**: v3 결정 유지 — PeakCart 전용 reference design (§3-3 Q28 DEFERRED) | Claude |
| Draft v6 | 2026-04-19 | 5차 리뷰 4건 전부 수용 — 마감 정리. (F1) §6-2 GP-2 행을 "P0/P1 없음 → 자동 통과, P2 는 audit log 기록만, 계획서 자동 수정 X" 로 통일해 §6-3-1 절차와 일치 (안전한 쪽으로). (F2) §13 Phase 0 체크리스트 `.gitignore` 예시의 `docs/plans/*.lock` → `*.lock/` 로 갱신, §6-4-1/부록 C 와 일치. (F3) §7-6-1 `_metrics.tsv` 의 `command` enum 값에서 `ship-precheck` 제거 → `plan | work` 로 제한 (`/ship` 은 codex 호출이 없으므로 메트릭 대상 아님 — 정의 명시). (F4) 부록 C 제목 "v4 canonical 경로" → "v5 canonical 경로" 라벨 정정 | Claude |
| Draft v7 | 2026-04-19 | 실행 가능성/재개 안전성 보강. 주요 변경: nested slash 가정 제거 및 `/next`/`/sync`/`/done` 를 "로직 재사용"으로 재서술, `/plan`/`/work` 에도 lock 획득 명시, `pending_run` + `session_id` + 원자적 state write 규약 추가, `run_id` 를 예약 기반 유일 키로 변경, degraded review 게이트(GP-2b/GW-2b) 신설, diff 분할을 최대 3 chunk 로 제한, `codex_attempts_total` 기준 호출 예산 정리, `commit_plan[]` 과 PR 선조회(`gh pr list --head`)로 `/ship` 재개 idempotency 보강, consistency precheck 실행 실패 분기 추가, KPI 를 자동/수동 측정으로 분리 | Codex |
| Draft v8 | 2026-04-19 | 서브에이전트 병렬 리뷰 1차 통합 반영. 주요 변경: 상단 상태를 조건부 설계안으로 정정, §4/§6 에 "후보안" / "조건부 실행 명세" 라벨 추가, `gh` 의존성과 Phase 0 환경 검증 추가, `/work` 브랜치 checkout/HEAD 교차 검증 명시, `attempts_by_command` 와 `codex_attempts_cycle_total` 분리, `/ship` 에 `ship_resume_cursor` 도입해 push/PR 실패 재진입 경로 명시, `pending_run` finalize 규약 신설, stale lock 자동 삭제 금지, `gate-events.tsv` 신설로 G1b/G1c/G2/P0 무시/degraded 승인 계측 보강, P2 누적 요약 노출 및 fallback 기준 표 추가 | Codex |
| Draft v9 | 2026-04-19 | 서브에이전트 병렬 리뷰 2차 통합 반영. 주요 변경: §2-2/§7/§13 에 hard timeout provider 필수 계약 추가 (`TIMEOUT=""` 제거), §5 대안 F 를 "조건부 채택" 으로 하향, §6-2 자동 통과 가시화 규칙 및 high-risk default threshold 도입, §6-3-1/§6-3-2 의 `stage` 의미를 "마지막 성공 단계" 로 통일하고 리뷰 루프 종료 조건을 "실제 수정 + 명시적 재리뷰 선택" 으로 정정, `review_plan`/chunk 메타데이터로 split review 상태 모델 추가, degraded 승인 기록(`degraded_accepted`, `degraded_reason`, `risk_*`) 명시, stale lock 강제 해제 절차와 archive terminal 규칙 추가, §7-3-1 프로세스 레벨 계약(stdout/stderr/exit code) 신설, §12 에 베이스라인 Phase 및 go/no-go 수치 기준 추가, G1c/G2 를 compliance metric 으로 재정의 | Codex |
| Draft v10 | 2026-04-19 | Phase 0 (0a/0b/0c) 검증 결과 반영. 주요 변경: 문서 헤더를 "조건부 설계안" → "구현 참조 설계 문서" 로 승격, §7-1/§7-2 의 JSON 강제를 프롬프트 지시 → `codex exec --output-schema <FILE>` 네이티브 강제로 이전 (Phase 0b 5/5 성공), 프롬프트에서 `[출력 형식 JSON]` / `[스키마]` inline 블록 제거 (중복 지시 모델 혼란 회피), §7-3-2 신설 — `.claude/schemas/plan-review.json` 과 `diff-review.json` 의 실제 JSON Schema 본문 + **모든 object 에 `additionalProperties: false` 필수** (OpenAI Structured Outputs 스펙 요건, 빠뜨리면 `invalid_json_schema` + exit 1), §7-6 비용 측정 bullet 을 Phase 0b 검증 결과로 구체화 (stderr `tokens used\n<숫자>` 2줄 형식 + `grep -A1` 파싱 예), §11-1 Codex CLI open question Q1~Q6 을 "Phase 0b 답변" 으로 closure (ChatGPT 로그인 인증, `--cd` 사용, `--output-schema` 5/5 성공 등) | Claude |

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

## 부록 C. 신규 자산 (구현 시) — v5 canonical 경로

| 자산 | 경로 | git | 비고 |
|------|------|-----|------|
| 계획서 | `docs/plans/<task-id>.md` | 추적 | stable id 규약 (§10-1) |
| audit log | `docs/plans/.audit/<task-id>.md` | 추적 | 게이트 결정 + P0 무시 사유 (§6-4-3) |
| state | `docs/plans/<task-id>.state.json` | gitignore | `review_runs[]` 구조 (§6-4-2, v4) |
| **lock 디렉토리** | `docs/plans/<task-id>.lock/` + 내부 `pid` | gitignore | mkdir 원자성 (§6-4-4, v3→v4 유지) |
| archive | `docs/plans/.archive/` | gitignore (정책: Q24) | `/ship` 성공 후 state 이동 |
| raw Codex 응답 | `.cache/codex-reviews/{plan,diff}-<task-id>-<ts>.json` | gitignore | 감사 (§6-4-1) |
| 메트릭 | `.cache/codex-reviews/_metrics.tsv` | gitignore | 15 컬럼 고정 스키마 (§7-6-1, v4) |
| gate 메트릭 | `.cache/codex-reviews/gate-events.tsv` | gitignore | 게이트 노출/자동통과/응답 지표 (§7-6-2, v8) |
| PR 본문 캐시 | `.cache/pr-body-<task-id>.md` | gitignore | PR 생성 실패 시 재사용 (§7-5-D) |
| diff 백업 | `.cache/diffs/diff-<task-id>-<ts>.patch` | gitignore | 디버깅 (§6-3-2) |

**`.gitignore` 항목 추가**:
```
docs/plans/*.state.json
docs/plans/*.lock/
.cache/
```

> `.lock/` 끝 슬래시 주의 — 디렉토리 ignore 임을 명시.
