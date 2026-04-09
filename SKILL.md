# db-cli — Database CLI Skill

Universal database access via `usql` + `db.sh` wrapper.
MCP 없이 CLI 기반으로 DB 쿼리, 스키마 캐시, 멀티 연결 지원.

## Tool

`db.sh` — 모든 DB 작업의 단일 진입점. 위치: `/c/workspace/tool/db-skill/db.sh`

```bash
bash /c/workspace/tool/db-skill/db.sh <command> [args]
```

## Commands

| 명령 | 설명 |
|------|------|
| `setup` | usql 설치 확인 + 디렉토리 초기화 |
| `list` | 연결 프로파일 목록 (스키마 캐시 상태 포함) |
| `add <project> <type> <env> [host] [port] [user] [dbname] [alias]` | 프로파일 생성 → 편집기 열기 |
| `edit <alias>` | 프로파일 편집기로 열기 |
| `remove <alias>` | 프로파일 + 스키마 캐시 삭제 |
| `test <alias>` | 연결 테스트 (응답시간 표시) |
| `query <alias[,a2]> "<sql>" [fmt]` | 쿼리 실행 (fmt: table/csv/json, 멀티 alias 지원) |
| `dump <alias>` | 스키마 DDL 캐시 생성 |
| `search <alias> <keyword>` | 캐시된 DDL 검색 (stale 시 자동 refresh) |
| `tables <alias>` | 테이블 이름 목록 |
| `desc <alias> <table>` | 특정 테이블 DDL |
| `refresh <alias>` | 스키마 캐시 강제 갱신 |

## Security Rules

1. **비밀번호, 공인 IP 등 민감 정보는 절대 채팅으로 주고받지 않는다.**
2. `.env` 파일은 OS 편집기(`notepad`, `vi`)로만 수정.
3. 출력에 비밀번호 노출 금지 (CONN_STR_SAFE 사용).
4. `.env` 파일은 git 커밋 금지.

## Schema Cache

- 포맷: DDL (`CREATE TABLE`) — LLM 토큰 효율 + text-to-SQL 정확도 최고
- 위치: `~/.claude/db/schema/<alias>.schema.sql`
- 자동 refresh: `DB_SCHEMA_MAX_AGE` 설정 (기본 `7d`, 예: `60m`, `1d`, `2w`)
- `search`, `tables`, `desc` 실행 시 stale 캐시 자동 갱신

## Profile Format

`~/.claude/db/{project}.{db_type}.{env}.env`:
```
DB_ALIAS=kdi_dev
DB_TYPE=mariadb
DB_HOST=localhost
DB_PORT=3306
DB_USER=kdi
DB_PASS=changeme
DB_NAME=kdi
```

지원 DB_TYPE: `mariadb`, `mysql`, `postgres`, `sqlite`, `mssql`, `oracle`

## Usage Examples

```bash
# 테이블 목록
db.sh tables kdi

# 특정 테이블 스키마 검색
db.sh search kdi "partner"

# 쿼리 실행
db.sh query kdi "SELECT * FROM partner_user LIMIT 5"

# JSON 포맷 출력
db.sh query kdi "SELECT * FROM partner_user" json

# 멀티 DB 동시 쿼리
db.sh query kdi,other_dev "SELECT COUNT(*) FROM partner_user"
```
