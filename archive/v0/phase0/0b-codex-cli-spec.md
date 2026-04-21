# Phase 0b: Codex CLI 명세 검증 결과

> **실행일**: 2026-04-19
> **참조**: `harness-plan.md` §11-1, §13 Phase 0b
> **codex-cli 버전**: 0.121.0

## 통과 판정 ✅

JSON 강제 5/5 = **100% 성공률** (§12-3 목표 > 90%). Phase 0c 진행 가능.

---

## Q1~Q6 답변

### Q1. `codex exec` 가 실제 서브커맨드인가?
**YES**. `codex --help` 출력:
```
Commands:
  exec         Run Codex non-interactively [aliases: e]
  review       Run a code review non-interactively
```
→ `exec` 뿐 아니라 `review` 도 별도 존재 (필요시 특화 사용 가능, 현재 설계에서는 `exec` 로 통일).

### Q2. non-interactive 모드 플래그
`codex exec` 자체가 "Run non-interactively". 별도 플래그 불필요.

### Q3. 작업 디렉토리 지정
**`-C, --cd <DIR>`** — harness-plan.md §7-1/§7-2 가정과 일치. 추가로:
- `--skip-git-repo-check` — non-git 디렉토리 허용 (PeakCart 는 git repo 라 불필요)
- `--add-dir <DIR>` — 추가 writable 디렉토리

### Q4. 인증 방식
- 명령: `codex login` / `codex logout` / `codex login status`
- 저장 위치: `~/.codex/auth.json`
- 현재 사용자는 **ChatGPT 로그인 사용 중** (API key env 아님)
- `~/.codex/config.toml` 로 기본값 설정

### Q5. JSON 출력 강제 안정성
**핵심 발견**: `--output-schema <FILE>` 플래그로 **네이티브 JSON Schema 강제** 지원.

5회 호출 결과:
| 호출 | exit | duration | items | JSON valid |
|------|------|----------|-------|------------|
| 1 | 0 | 7.3s | 3 | ✅ |
| 2 | 0 | 12s | 3 | ✅ |
| 3 | 0 | 9s | 3 | ✅ |
| 4 | 0 | 8s | 3 | ✅ |
| 5 | 0 | 8s | 3 | ✅ |

**성공률 5/5 = 100%**, 평균 wall clock ~9초 (설계 60초 timeout 여유).

**주의사항** (중요):
- `--output-schema` 는 OpenAI Structured Outputs 스펙을 **엄격히** 따라야 함
- 모든 `object` 에 `additionalProperties: false` 필수
- 위반 시 exit 1 + `invalid_json_schema` 에러
- harness-plan.md §7-3 스키마 작성 시 이 제약 반영 필요

### Q6. 토큰/비용 metadata 노출
**YES — stderr 에 노출**. 형식:
```
tokens used
9,797
```
- 줄바꿈으로 분리됨 (한 줄 아님), 파싱 시 `grep -A1 "tokens used"`
- 비용 (USD) 은 노출 안 됨 → tokens → 비용 환산 로직 필요 (모델별 pricing table)
- harness-plan.md §7-6 "1순위: tokens metadata 파싱" 경로 유효

### Q6-1. `$CODEX_CMD` 추상명 확정
```bash
CODEX_CMD="codex exec --cd $(pwd) --output-schema <SCHEMA_FILE> --sandbox read-only"
```
- PeakCart 는 git repo 라 `--skip-git-repo-check` 불필요
- `--sandbox read-only` = 리뷰 목적 (파일 수정 금지, 읽기만)

---

## 설계 영향 (harness-plan.md 수정 제안)

### §7-1 / §7-2 Codex 호출 규약 단순화 가능
현재 문서는 프롬프트에 "JSON 스키마 강제" 지시문을 넣는 방식. 실제로는:
- ✅ **`--output-schema` 로 네이티브 강제** — 프롬프트 지시문은 보조로만
- 스키마 파일은 `.claude/schemas/plan-review.json`, `diff-review.json` 로 분리 저장 권장

### §7-3 출력 프로토콜 — 스키마 엄격화 필수
- 모든 `object` 에 `additionalProperties: false` 추가
- `items[].id`, `severity`, `finding`, `suggestion` 등 구체 필드 스키마 재검토
- `run_id` 도 top-level required 에 포함 (기존 v4 반영됨)

### §7-5-A JSON 파싱 실패 ladder
현재 설계는 "코드블록 감쌈" 가정 포함. `--output-schema` 사용 시:
- 100% JSON 강제되므로 파싱 실패는 exit != 0 케이스 위주
- 코드블록 감쌈은 거의 발생하지 않을 것 (fallback 유지하되 우선순위 낮춤)

### §7-6 토큰 파싱
```bash
# stderr 에서 tokens 추출
TOKENS=$(grep -A1 "tokens used" .cache/codex-reviews/*.stderr | tail -1)
```

### 미해결
- **비용 (USD) 는 CLI 가 직접 제공 X** → 모델별 pricing 환산 로직 필요 (fallback 프록시 지표 보강 필요)
- `codex exec --json` (JSONL 이벤트 스트림) 은 비용 metadata 를 더 풍부하게 노출할 가능성 — 후속 검증 대상

---

## Phase 0b 완료 확인

- [x] Q1 — `codex exec` 서브커맨드 존재
- [x] Q2 — non-interactive = `codex exec` 자체
- [x] Q3 — `-C, --cd <DIR>` 사용
- [x] Q4 — ChatGPT 로그인 완료, `~/.codex/auth.json`
- [x] Q5 — JSON 강제 5/5 = 100% (목표 > 90%)
- [x] Q6 — stderr 에 `tokens used\n<숫자>` 노출
- [x] Q6-1 — `$CODEX_CMD` 형태 확정
- [x] 추가 발견: `--output-schema`, `--sandbox read-only`, `--output-last-message`

## 다음 단계

Phase 0c (macOS/gh/git 환경) 로 진행.
