# v0 Phase 0 Archive

이 디렉터리는 `v0 Phase 0` 사전 검증 결과를 보관한다.

## 파일

- `0a-slash-command-model.md`
  - 슬래시 커맨드 실행 모델 검증
  - nested slash 불가, shared script 우회 근거
- `0b-codex-cli-spec.md`
  - Codex CLI 명세 검증
  - `--output-schema` 기반 JSON 강제 근거
- `0c-environment.md`
  - macOS / `gh` / git / timeout provider 환경 검증

## 언제 참조하는가

- 왜 `/sync`, `/next`, `/done`이 독립 명령이 아니라 로직으로 흡수됐는지 확인할 때
- 왜 `codex exec --output-schema`를 표준 호출로 채택했는지 확인할 때
- timeout provider, gh 인증, git 환경 같은 초기 운영 제약을 다시 볼 때
