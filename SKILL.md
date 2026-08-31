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
- Db2/Oracle 캐시에서 `?` 는 **「카탈로그가 알려주지 않았다」**이지 「없다」가 아닙니다.
  권한이 좁은 계정이면 인덱스·코멘트가 `?` 로 나옵니다.
  카탈로그를 아예 못 읽은 경우 파일 머리에 `-- INCOMPLETE:` 줄이 붙습니다 — 그 줄이 있으면
  **그 캐시에서 「없음」을 결론으로 삼지 마십시오.**
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

지원 DB_TYPE: `mariadb`, `mysql`, `postgres`, `sqlite`, `mssql`, `oracle` (usql 경유)
             `db2` (`db_schema.py` 경유 — `pip install ibm_db` 필요)

**Db2 는 usql 을 쓰지 않습니다.** usql 에서 Db2 는 ODBC 경유만 가능한데 그 경로가
스키마 카탈로그 조회에서 깨집니다(NULL 컬럼에서 결과 절단 또는 panic — README 참조).
`db.sh` 가 `DB_TYPE=db2` 를 보고 자동으로 `db_schema.py` 로 보내므로 명령은 동일합니다.
Db2 프로파일의 `DB_NAME` 은 데이터베이스 이름, Oracle 은 서비스 이름입니다.

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
