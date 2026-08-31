# db-cli-skill

MCP 없이 Claude Code에서 데이터베이스를 다루는 CLI 기반 스킬.

`usql` + `db.sh` 래퍼로 연결 관리, 쿼리 실행, 스키마 캐시를 제공합니다.
MCP 서버 대비 **idle 토큰 소모 0**, 필요할 때만 CLI 호출로 토큰을 절약합니다.

## 왜 MCP 대신 CLI인가?

| 항목 | MCP DB 서버 | db-cli-skill |
|------|-----------|--------------|
| idle 토큰 (도구 정의 상주) | 3,000~5,000/턴 | **0** |
| 스키마 조회 | JSON ~2,000 토큰 | DDL Grep, 해당 줄만 ~200 |
| 쿼리 결과 | JSON wrapping 1.5x | 테이블 출력 1x |
| 100턴 세션 idle 비용 | **30만~50만 토큰** | **0** |
| 설치 복잡도 | MCP 서버 설정 | `bash setup.sh` |

## 지원 DB

| DB | 경로 | 필요한 것 |
|----|------|-----------|
| MariaDB, MySQL, PostgreSQL, SQLite, MSSQL, Oracle | `usql` | `usql` |
| **IBM Db2** | `db_schema.py` (네이티브 드라이버) | `pip install ibm_db` |

Db2 는 usql 을 거치지 않습니다. usql 에서 Db2 는 ODBC 경유만 가능한데,
**그 경로가 스키마 카탈로그 조회에서 깨집니다.** 근거는 아래
[usql + ODBC 의 한계](#usql--odbc-의-한계--db2-를-usql-로-읽지-않는-이유)에 있습니다.

명령은 동일합니다. `db.sh` 가 프로파일의 `DB_TYPE` 을 보고 알아서 갈라 보냅니다:

```bash
db.sh add myapp db2 dev localhost 50000 db2inst1 MYDB
db.sh test   mydb2_alias        # → db_schema.py
db.sh query  mydb2_alias "SELECT 1 FROM SYSIBM.SYSDUMMY1"
db.sh dump   mydb2_alias        # → 같은 캐시 파일에 씁니다
db.sh tables mydb2_alias        # 그래서 이 명령들은 그대로 동작합니다
db.sh desc   mydb2_alias SALES
db.sh search mydb2_alias "amt"
```

`db_schema.py` 는 Oracle 도 처리합니다. Oracle 은 usql 로도 붙지만,
PK·인덱스 컬럼 순서·코멘트까지 받고 싶으면 직접 호출할 수 있습니다:

```bash
python3 db_schema.py dump my_oracle_alias
```

## 설치

### 0. Db2 를 쓴다면

```bash
pip install ibm_db      # IBM CLI 드라이버가 휠에 포함되어 있습니다 (별도 설치 불필요)
pip install oracledb    # (선택) Oracle 을 db_schema.py 로 읽을 때
```

### 1. usql 설치

```bash
# Windows (scoop)
scoop install usql

# macOS (brew)
brew install xo/xo/usql

# Linux (go)
go install github.com/xo/usql@latest
```

### 2. 초기 설정

```bash
bash setup.sh
```

### 3. Claude Code 스킬 등록

`SKILL.md`를 Claude Code 스킬 디렉토리에 복사:

```bash
# 글로벌 스킬
mkdir -p ~/.claude/skills/db
cp SKILL.md ~/.claude/skills/db/SKILL.md
```

### 4. db.sh를 PATH에 등록

```bash
# 예: ~/bin 에 심볼릭 링크
ln -s /path/to/db-cli-skill/db.sh ~/bin/db.sh

# 또는 직접 복사
cp db.sh ~/bin/db.sh
```

## 사용법

### 연결 프로파일 관리

```bash
# 프로파일 생성 (비밀번호는 편집기에서 직접 입력)
db.sh add my-project mariadb dev localhost 3306 myuser mydb

# 프로파일 목록
db.sh list

# 프로파일 수정
db.sh edit my_project_dev

# 프로파일 삭제
db.sh remove my_project_dev

# 연결 테스트
db.sh test my_project_dev
```

### 쿼리 실행

```bash
# 기본 쿼리
db.sh query my_project_dev "SELECT * FROM users LIMIT 5"

# CSV 출력
db.sh query my_project_dev "SELECT * FROM users" csv

# JSON 출력
db.sh query my_project_dev "SELECT * FROM users" json

# 멀티 DB 동시 쿼리
db.sh query dev_db,staging_db "SELECT COUNT(*) FROM users"
```

### 스키마 관리

```bash
# 스키마 DDL 캐시 생성
db.sh dump my_project_dev

# 테이블 목록
db.sh tables my_project_dev

# 특정 테이블 DDL 보기
db.sh desc my_project_dev users

# 스키마 검색 (키워드)
db.sh search my_project_dev "order"

# 스키마 캐시 강제 갱신
db.sh refresh my_project_dev
```

## usql + ODBC 의 한계 — Db2 를 usql 로 읽지 않는 이유

**usql 로 Db2 에 붙는 것 자체는 됩니다.** 그런데 스키마를 읽을 수 없습니다.
아래는 추측이 아니라 Db2 Community Edition 컨테이너에 실제로 붙여서 확인한 것입니다.

### 측정 환경

| 항목 | 값 |
|------|-----|
| usql | v0.21.4, `-tags odbc` 로 빌드 (go 1.26, Linux x86_64) |
| ODBC 드라이버 | `github.com/alexbrainman/odbc` (2025-06-01) |
| Db2 CLI 드라이버 | `ibm_db` 3.3.0 휠에 포함된 clidriver |
| 서버 | Db2 Community Edition 컨테이너 |

### 되는 것

- 연결 — `SELECT 1 FROM SYSIBM.SYSDUMMY1` 통과
- 일반 `SELECT` — 정상

### 안 되는 것 ①  `\d` 계열이 없습니다

```
$ usql "odbc+DB2://..." -c '\dt'
error: describe commands not supported by odbc driver
```

즉 ODBC 경유로는 usql 의 스키마 조회 기능을 쓸 수 없고,
카탈로그(`SYSCAT.*`)를 직접 질의해야 합니다. 그런데 그게 ②에서 깨집니다.

### 안 되는 것 ②  ★NULL 이 든 카탈로그 컬럼에서 깨집니다

| 컬럼 | 타입 | 증상 |
|------|------|------|
| `SYSCAT.COLUMNS.KEYSEQ` | nullable SMALLINT | `error: odbc: wrong column #0 length 4294967295 returned, 4 expected` — **결과가 중간에서 끊깁니다** |
| `SYSCAT.TABLES.REMARKS` | nullable VARCHAR | `panic: runtime error: slice bounds out of range [:4294967295] with capacity 255` — **프로세스가 죽습니다** |

`4294967295` = `0xFFFFFFFF` = **`SQL_NULL_DATA`(-1)를 부호 없는 값으로 읽은 것**입니다.

**하필 스키마 캐시에 꼭 필요한 두 컬럼입니다** — `KEYSEQ` 는 기본키, `REMARKS` 는 코멘트이고,
둘 다 대부분의 행에서 NULL 입니다.

`COALESCE(...)` 로 감싸면 통과하는 것까지 확인했습니다. 하지만 그건
"모든 nullable 컬럼을 손으로 막는다"는 뜻이고, **한 군데만 빠뜨려도
조용한 절단이거나 panic** 입니다. 스키마 캐시는 만들어 두고 나중에 grep 하는 것이라
잘린 캐시는 눈에 띄지 않습니다 — 그래서 이 경로를 "지원"으로 넣지 않았습니다.

### 안 되는 것 ③  `odbc.ini` 만으로는 안 붙습니다

```
SQL1531N  The connection failed because the name specified with the DSN connection
string keyword could not be found in either the db2dsdriver.cfg configuration file
or the db2cli.ini configuration file.
```

IBM CLI 드라이버는 unixODBC 의 `odbc.ini` 가 아니라 **자기 `db2cli.ini`** 를 따로 봅니다
(`DB2CLIINIPATH`). 설정 파일이 **두 개** 필요합니다.

### 설치 비용 비교 (같은 머신에서 실측)

| | usql + ODBC | `pip install ibm_db` |
|---|---|---|
| 설치 절차 | apt(golang, unixodbc, unixodbc-dev) → `go install -tags odbc` → CLI 드라이버 → `odbcinst.ini` → `db2cli.ini` | `pip install ibm_db` |
| 소요 시간 | cgo 콜드 빌드 **56초** (+ apt) | **7초** |
| 디스크 | apt 239MB + 바이너리 62.6MB + go 캐시 349MB + GOPATH 854MB + 드라이버 122MB | **175MB** |
| sudo | **필요** (apt) | 불필요 |
| C 컴파일러 | **필요** (cgo) | 불필요 (휠) |
| 설정 파일 | **2개** | 0개 |
| 카탈로그 읽기 | ★**깨짐** | 정상 |

### ★그리고 둘은 «택일»이 아닙니다

usql+ODBC 경로가 요구하는 IBM CLI 드라이버는 **`pip install ibm_db` 가 이미 가져옵니다**
(`site-packages/clidriver/lib/libdb2.so`). 위 실측에서도 `odbcinst.ini` 의 `Driver=` 를
그 경로로 잡았습니다.

즉 **ODBC 경로는 네이티브 드라이버 «위에» 얹히는 구조**입니다.
"A 냐 B 냐"가 아니라 **"B 냐, B 에 A 를 더하냐"**이고,
A 를 더해서 얻는 것은 대화형 셸뿐이며 스키마 조회는 얻지 못합니다.

usql 로 Db2 를 탐색용으로 쓰는 것 자체는 말리지 않습니다.
다만 **자동화·덤프 경로에는 넣지 마십시오.**

---

## 스키마 캐시

스키마는 `CREATE TABLE` DDL 원본으로 캐시합니다.

**DDL을 선택한 이유:**
- LLM 사전학습 데이터에 가장 많이 등장하는 포맷 → 파싱 비용 0
- text-to-SQL 정확도가 JSON, YAML, 마크다운 테이블 대비 최고
- 토큰 효율적 (테이블당 1줄)
- Grep 검색 호환
- `SHOW CREATE TABLE` 결과 그대로 → 변환 로직 불필요

### Db2 / Oracle 캐시의 표기

`db_schema.py` 가 만든 캐시는 같은 파일·같은 한 줄 DDL 형식이라
`tables` / `desc` / `search` 가 그대로 동작합니다. 다만 두 가지를 구분해서 읽으십시오.

- **`?`** — 「카탈로그가 알려주지 않았다」이지 **「없다」가 아닙니다.**
  권한이 좁은 계정은 테이블·컬럼은 정상으로 읽으면서 인덱스·코멘트만 `?` 가 됩니다.
- **`-- INCOMPLETE:`** — 파일 머리에 이 줄이 있으면 일부 카탈로그를 아예 못 읽은 것입니다.
  못 읽은 항목은 아래에서 **줄 자체가 없습니다.** 그 캐시에서 「없음」을 결론으로 삼지 마십시오.
  (인덱스를 못 읽은 경우 테이블마다 `-- INDEXES:?` 줄이 대신 붙습니다.)

`CREATE VIEW` 는 **컬럼 signature 와 의존 대상만** 담습니다 — `SELECT` 본문은 캐시하지 않으므로
실행 가능한 DDL 로 읽으면 안 됩니다.

### 자동 갱신

스키마 캐시가 설정 기간을 초과하면 `search`, `tables`, `desc` 실행 시 자동 refresh:

```bash
# 환경변수로 설정 (기본: 7d)
export DB_SCHEMA_MAX_AGE=60m   # 60분
export DB_SCHEMA_MAX_AGE=1d    # 1일
export DB_SCHEMA_MAX_AGE=2w    # 2주
```

## 보안

- **비밀번호는 절대 채팅창에 입력하지 않습니다.** Claude Code의 모든 대화는 서버로 전송됩니다.
- 프로파일 생성/수정 시 OS 편집기(notepad/vi)가 열려 비밀번호를 직접 입력합니다.
- 출력에 비밀번호가 노출되지 않습니다 (CONN_STR_SAFE 사용).
- `.env` 파일은 `~/.claude/db/`에 저장되며, git 커밋 대상이 아닙니다.

## 연결 프로파일 형식

`~/.claude/db/{project}.{db_type}.{env}.env`:

```bash
DB_ALIAS=my_project_dev
DB_TYPE=mariadb
DB_HOST=localhost
DB_PORT=3306
DB_USER=myuser
DB_PASS=changeme
DB_NAME=mydb
```

## 파일 구조

```
db-cli-skill/
├── README.md          # 이 파일
├── LICENSE            # MIT
├── db.sh              # 핵심 CLI 래퍼 (usql 경유)
├── db_schema.py       # Db2/Oracle 네이티브 드라이버 스키마 덤프
├── setup.sh           # 초기 설치 스크립트
├── SKILL.md           # Claude Code 스킬 정의
└── example/
    └── example.mariadb.dev.env  # 예제 프로파일
```

## 경쟁 도구 비교

| 기능 | db-cli-skill | DBHub (MCP) | claude-database-tools | dblab |
|------|-------------|-------------|----------------------|-------|
| MCP 불필요 | O | X | O | - |
| 멀티 DB 지원 | O | O | X (MSSQL only) | O |
| 스키마 DDL 캐시 | O | X | X | X |
| 자동 refresh | O | X | X | X |
| idle 토큰 비용 | 0 | 높음 | 0 | - |
| 멀티 연결 동시 쿼리 | O | O | X | X |
| 보안 (편집기 분리) | O | X | X | X |
| 출력 포맷 선택 | O (table/csv/json) | X | X | X |

## 라이선스

MIT License
