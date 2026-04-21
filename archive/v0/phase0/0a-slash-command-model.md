# Phase 0a: 슬래시 커맨드 실행 모델 검증 결과

> **실행일**: 2026-04-19
> **담당**: Claude (claude-code-guide 서브에이전트 조사)
> **참조**: `harness-plan.md` §11-0, §13 Phase 0a

## 최종 판정: **B** — 일부 제약 있지만 우회 가능

설계안 **F (슬래시 + codex subprocess)** 유지. nested slash 만 shell script 로 대체.
§5-2 분기 중 "결과 B → F 채택, 우회 방법 §6 에 명시" 경로 확정.

---

## Q0-1. 마크다운 확장 vs 다단계 흐름 제어

**답**: 하이브리드. 커맨드 본질은 "마크다운 → 프롬프트 변환" 이지만, Claude 가 그 안에서 Bash/Read/Edit 도구를 반복 호출하며 같은 턴 내에서 결과를 처리 → 사실상 상태 머신 구현 가능.

**근거**: Skills 문서 "skill 내용이 한 번의 메시지로 Claude 에 입력되고, 세션 내내 유지됨" + Interactive Mode Bash 모드(`!`).

**frontmatter 지원**: `allowed-tools`, `model`, `effort`, `context`, `hooks` + `$ARGUMENTS` 치환.

**하네스 영향**: §6-3 다단계 절차 (예: `/plan` 계획 → Codex 리뷰 → 루프) 구현 가능.

## Q0-2. 다회 사용자 입력 + 상태 유지

**답**: ✅ 가능. 한 커맨드 실행 중 Claude 가 사용자에게 질문 → 응답 기다림 → 다음 단계 패턴 완전 지원. 상태는 (a) Claude 대화 메모리 + (b) 외부 파일 (state.json) 이원화.

**하네스 영향**: §6-4 state.json + lock + audit log 설계 그대로 유효. 자동 갱신 필요 시 매 단계 후 파일 쓰기 강제.

## Q0-3. nested slash 호출

**답**: ❌ **직접 불가**. Skills/Custom Commands 는 다른 커맨드를 spawn 할 수 없음.

**우회**: `.claude/scripts/shared-logic.sh` 에 `/sync`, `/next`, `/done` 의 공통 로직을 추출 → 각 커맨드 마크다운에서 `bash .claude/scripts/shared-logic.sh sync` 형태로 호출.

**하네스 영향**: **중요 설계 변경 불필요** — harness-plan.md 는 이미 v7 에서 "nested slash 가정 금지, 인라인 or 공통 스크립트" 로 설계됨 (§2-3, §6-3-1 Step 2, §6-3-3 Step 9).

**Action Item**: Phase 1 착수 시 `.claude/scripts/` 디렉토리 생성 + `/sync`, `/next`, `/done` 공통 로직 추출이 선행 작업이 됨.

## Q0-4. 자유 메시지 인터럽트

**답**: 인터럽트되지 않음. 사용자 자유 메시지는 대화의 다음 턴으로 queued, 커맨드 실행 중단 X. ESC + ESC 는 "Rewind or summarize" (checkpoint 복구 or 요약).

**하네스 영향**: 사용자가 커맨드 진행 중 "잠깐 ADR 보기" 같은 개입 자유롭게 가능. 오히려 긍정적.

## Q0-5. stdout/stderr truncation

**답**: 자동 truncation 정책 존재 (정확한 threshold 미공개). 권장 패턴: **파일 리다이렉트 후 Read 도구로 필요 부분만 로드**.

**근거**: Background bash 문서 "Output is written to a file and Claude can retrieve it using the Read tool".

**하네스 영향**: 이미 §7-1/§7-2 에서 `> .cache/codex-reviews/*.json 2> *.stderr` 패턴 채택. 설계 변경 불필요.

---

## 각 Q 요약표

| Q | 답 | 우회 필요 | 하네스 설계 변경 |
|---|-----|----------|------------------|
| Q0-1 다단계 흐름 | ✅ 가능 | — | 없음 |
| Q0-2 다회 입력 | ✅ 가능 | — | 없음 |
| Q0-3 nested slash | ❌ 불가 | shared-logic.sh 추출 | 이미 v7 에서 반영됨 |
| Q0-4 자유 메시지 | 비인터럽트 | — | 없음 (긍정적 기능) |
| Q0-5 truncation | 자동 관리 | 파일 리다이렉트 패턴 | 이미 §7 에 반영됨 |

## Phase 1 선행 작업 추가

- [ ] `.claude/scripts/` 디렉토리 생성
- [ ] `/sync`, `/next`, `/done` 로직을 shell script 로 추출 (또는 각 슬래시 커맨드에서 인라인 복제)
- [ ] TASKS.md P1-* 에 반영

## 결론

- **Phase 0a 통과** — 설계안 F 유지
- Phase 0b (Codex CLI 명세) 로 진행 가능
- R12 (F1 가정 오류) 위험 **해소**
