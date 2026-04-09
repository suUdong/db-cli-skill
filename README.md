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

MariaDB, MySQL, PostgreSQL, SQLite, MSSQL, Oracle

## 설치

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

## 스키마 캐시

스키마는 `CREATE TABLE` DDL 원본으로 캐시합니다.

**DDL을 선택한 이유:**
- LLM 사전학습 데이터에 가장 많이 등장하는 포맷 → 파싱 비용 0
- text-to-SQL 정확도가 JSON, YAML, 마크다운 테이블 대비 최고
- 토큰 효율적 (테이블당 1줄)
- Grep 검색 호환
- `SHOW CREATE TABLE` 결과 그대로 → 변환 로직 불필요

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
├── db.sh              # 핵심 CLI 래퍼
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
