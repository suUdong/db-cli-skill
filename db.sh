#!/bin/bash
# db.sh — Database CLI wrapper for Claude Code skill
# Usage: db.sh <command> [args]

set -e

DB_DIR="${HOME}/.claude/db"
SCHEMA_DIR="${DB_DIR}/schema"
SCHEMA_MAX_AGE="${DB_SCHEMA_MAX_AGE:-7d}"

# --- helpers ---

_load_profile() {
  local alias="$1"
  local file
  file=$(grep -rl "^DB_ALIAS=${alias}$" "${DB_DIR}"/*.env 2>/dev/null | head -1)
  if [ -z "$file" ]; then
    echo "ERROR: alias '${alias}' not found" >&2
    exit 1
  fi
  source "$file"
  # DSN with password (usql requires it in DSN)
  CONN_STR="${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  # safe version for display — never expose password in output
  CONN_STR_SAFE="${DB_TYPE}://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
}

_check_usql() {
  if ! command -v usql &>/dev/null; then
    echo "ERROR: usql not installed. Run: db.sh setup" >&2
    exit 1
  fi
}

_open_editor() {
  local file="$1"
  case "$(uname -s)" in
    MINGW*|MSYS*) notepad "$file" ;;
    Darwin*)      open -e "$file" ;;
    Linux*)       ${EDITOR:-vi} "$file" ;;
  esac
}

_default_port() {
  case "$1" in
    mariadb|mysql) echo 3306 ;;
    postgres)      echo 5432 ;;
    mssql)         echo 1433 ;;
    oracle)        echo 1521 ;;
    sqlite)        echo "" ;;
    *)             echo 3306 ;;
  esac
}

_parse_duration_to_seconds() {
  local val="$1"
  local num unit
  num=$(echo "$val" | sed 's/[^0-9]//g')
  unit=$(echo "$val" | sed 's/[0-9]//g')
  if [ -z "$num" ]; then num=7; fi
  case "$unit" in
    m|min)  echo $(( num * 60 )) ;;
    h|hr)   echo $(( num * 3600 )) ;;
    d|day)  echo $(( num * 86400 )) ;;
    w|week) echo $(( num * 604800 )) ;;
    *)      echo $(( num * 86400 )) ;;  # default: days
  esac
}

_format_duration() {
  local sec="$1"
  if [ "$sec" -lt 3600 ]; then
    echo "$(( sec / 60 ))m"
  elif [ "$sec" -lt 86400 ]; then
    echo "$(( sec / 3600 ))h"
  else
    echo "$(( sec / 86400 ))d"
  fi
}

_schema_age_seconds() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo 9999999
    return
  fi
  local file_mtime now_epoch
  now_epoch=$(date +%s)
  # use file modification time (more reliable than parsing header)
  file_mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)
  if [ "$file_mtime" -eq 0 ]; then
    echo 9999999
    return
  fi
  echo $(( now_epoch - file_mtime ))
}

_auto_refresh_if_stale() {
  local alias="$1"
  local file="${SCHEMA_DIR}/${alias}.schema.sql"
  local age_sec max_sec
  age_sec=$(_schema_age_seconds "$file")
  max_sec=$(_parse_duration_to_seconds "$SCHEMA_MAX_AGE")
  if [ "$age_sec" -ge "$max_sec" ]; then
    if [ "$age_sec" -ge 9999999 ]; then
      echo "INFO: No schema cache for '${alias}'. Auto-dumping..." >&2
    else
      echo "INFO: Schema cache is $(_format_duration $age_sec) old (max: ${SCHEMA_MAX_AGE}). Auto-refreshing..." >&2
    fi
    cmd_dump "$alias" >&2
  fi
}

# --- commands ---

cmd_setup() {
  echo "=== db-skill setup ==="
  mkdir -p "${DB_DIR}" "${SCHEMA_DIR}"

  if command -v usql &>/dev/null; then
    echo "usql installed: $(usql --version 2>&1 | head -1)"
  else
    echo "usql not found."
    case "$(uname -s)" in
      MINGW*|MSYS*) echo "Install: scoop install usql" ;;
      Darwin*)      echo "Install: brew install xo/xo/usql" ;;
      Linux*)       echo "Install: go install github.com/xo/usql@latest" ;;
    esac
    exit 1
  fi

  # check profiles
  local count
  count=$(ls "${DB_DIR}"/*.env 2>/dev/null | wc -l | tr -d ' ')
  echo "Profiles: ${count}"
  echo "DB dir: ${DB_DIR}"
  echo "Schema dir: ${SCHEMA_DIR}"
  echo "Schema max age: ${SCHEMA_MAX_AGE_DAYS} days"
  echo ""
  echo "Setup complete."
  echo ""
  echo "Next: db.sh add <project> <db_type> <env>"
}

cmd_list() {
  if [ ! -d "${DB_DIR}" ] || [ -z "$(ls "${DB_DIR}"/*.env 2>/dev/null)" ]; then
    echo "No profiles found in ${DB_DIR}"
    exit 0
  fi
  printf "%-20s %-10s %-30s %s\n" "ALIAS" "TYPE" "HOST" "FILE"
  printf "%-20s %-10s %-30s %s\n" "-----" "----" "----" "----"
  for f in "${DB_DIR}"/*.env; do
    source "$f"
    local schema_status=""
    local schema_file="${SCHEMA_DIR}/${DB_ALIAS}.schema.sql"
    if [ -f "$schema_file" ]; then
      local age_sec max_sec
      age_sec=$(_schema_age_seconds "$schema_file")
      max_sec=$(_parse_duration_to_seconds "$SCHEMA_MAX_AGE")
      local age_fmt
      age_fmt=$(_format_duration $age_sec)
      if [ "$age_sec" -ge "$max_sec" ]; then
        schema_status=" [schema: ${age_fmt}, stale]"
      else
        schema_status=" [schema: ${age_fmt}]"
      fi
    else
      schema_status=" [no schema]"
    fi
    printf "%-20s %-10s %-30s %s%s\n" "$DB_ALIAS" "$DB_TYPE" "${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}" "$(basename "$f")" "$schema_status"
  done
}

cmd_add() {
  local project="$1" dbtype="$2" env="$3" host="$4" port="$5" user="$6" dbname="$7" alias="$8"

  if [ -z "$project" ] || [ -z "$dbtype" ] || [ -z "$env" ]; then
    echo "Usage: db.sh add <project> <db_type> <env> [host] [port] [user] [dbname] [alias]"
    echo "  db_type: mariadb|mysql|postgres|sqlite|mssql|oracle"
    echo "  env: dev|staging|prod"
    echo "Example: db.sh add kdi-partner mariadb dev localhost 3306 kdi kdi kdi_dev"
    exit 1
  fi

  host="${host:-localhost}"
  port="${port:-$(_default_port "$dbtype")}"
  user="${user:-root}"
  dbname="${dbname:-$project}"
  alias="${alias:-${project//-/_}_${env}}"

  local file="${DB_DIR}/${project}.${dbtype}.${env}.env"

  mkdir -p "${DB_DIR}" "${SCHEMA_DIR}"

  # duplicate check: file
  if [ -f "$file" ]; then
    echo "ERROR: Profile already exists: $(basename "$file")"
    echo "Use: db.sh edit ${alias}"
    exit 1
  fi
  # duplicate check: alias
  if grep -rl "^DB_ALIAS=${alias}$" "${DB_DIR}"/*.env 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: Alias '${alias}' already exists in another profile"
    exit 1
  fi

  cat > "$file" <<EOF
DB_ALIAS=${alias}
DB_TYPE=${dbtype}
DB_HOST=${host}
DB_PORT=${port}
DB_USER=${user}
DB_PASS=changeme
DB_NAME=${dbname}
EOF

  echo "Profile created: ${file}"
  echo "Opening editor — set password and save..."
  _open_editor "$file"
}

cmd_edit() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh edit <alias>"
    exit 1
  fi
  local file
  file=$(grep -rl "^DB_ALIAS=${alias}$" "${DB_DIR}"/*.env 2>/dev/null | head -1)
  if [ -z "$file" ]; then
    echo "ERROR: alias '${alias}' not found" >&2
    exit 1
  fi
  echo "Opening: ${file}"
  _open_editor "$file"
}

cmd_remove() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh remove <alias>"
    exit 1
  fi
  local file
  file=$(grep -rl "^DB_ALIAS=${alias}$" "${DB_DIR}"/*.env 2>/dev/null | head -1)
  if [ -z "$file" ]; then
    echo "ERROR: alias '${alias}' not found" >&2
    exit 1
  fi
  rm "$file"
  echo "Removed: ${file}"
  if [ -f "${SCHEMA_DIR}/${alias}.schema.sql" ]; then
    rm "${SCHEMA_DIR}/${alias}.schema.sql"
    echo "Removed schema cache: ${alias}.schema.sql"
  fi
}

cmd_test() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh test <alias>"
    exit 1
  fi
  _check_usql
  _load_profile "$alias"
  echo "Testing ${alias} → ${CONN_STR_SAFE}..."
  local start_time end_time
  start_time=$(date +%s)
  if usql "${CONN_STR}" -c "SELECT 1" &>/dev/null; then
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    if [ "$elapsed" -eq 0 ]; then
      echo "OK (<1s)"
    else
      echo "OK (${elapsed}s)"
    fi
  else
    echo "FAIL — check host/port/credentials"
    exit 1
  fi
}

cmd_query() {
  local aliases="$1" sql="$2" format="${3:-table}"
  if [ -z "$aliases" ] || [ -z "$sql" ]; then
    echo "Usage: db.sh query <alias[,alias2]> \"<sql>\" [format]"
    echo "  format: table (default), csv, json"
    exit 1
  fi
  _check_usql

  IFS=',' read -ra ALIAS_LIST <<< "$aliases"
  for alias in "${ALIAS_LIST[@]}"; do
    _load_profile "$alias"
    if [ ${#ALIAS_LIST[@]} -gt 1 ]; then
      echo "=== ${alias} ==="
    fi
    case "$format" in
      csv)
        usql "${CONN_STR}" -c "${sql}" --csv 2>&1
        ;;
      json)
        usql "${CONN_STR}" -c "${sql}" --json 2>&1
        ;;
      *)
        usql "${CONN_STR}" -c "${sql}" 2>&1
        ;;
    esac
    if [ ${#ALIAS_LIST[@]} -gt 1 ]; then
      echo ""
    fi
  done
}

cmd_dump() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh dump <alias>"
    exit 1
  fi
  _check_usql
  _load_profile "$alias"
  mkdir -p "${SCHEMA_DIR}"

  local outfile="${SCHEMA_DIR}/${alias}.schema.sql"
  echo "-- ${alias} (${DB_TYPE}://${DB_HOST}:${DB_PORT}/${DB_NAME}) @$(date +%Y-%m-%d)" > "$outfile"

  local tables
  case $DB_TYPE in
    mariadb|mysql)
      tables=$(usql "${CONN_STR}" -c "SHOW TABLES" 2>&1 \
        | grep -v "Tables_in_\|---\|(.*rows)" \
        | sed 's/^ *//;s/ *$//' \
        | grep -v '^$')
      for t in $tables; do
        usql "${CONN_STR}" -c "SHOW CREATE TABLE \`${t}\`" 2>&1 \
          | awk -F'|' 'NR>2 && !/rows\)/{gsub(/^ +| +$/,"",$2); if($2!="") printf "%s",$2}' \
          | tr -d '+' \
          | tr -s ' ' \
          | sed 's/^ //;s/ $//' >> "$outfile"
        echo "" >> "$outfile"
      done
      ;;
    postgres)
      tables=$(usql "${CONN_STR}" -c "SELECT tablename FROM pg_tables WHERE schemaname='public'" 2>&1 \
        | grep -v "tablename\|---\|(.*rows)" \
        | sed 's/^ *//;s/ *$//' \
        | grep -v '^$')
      for t in $tables; do
        usql "${CONN_STR}" -c "SELECT 'CREATE TABLE \"${t}\" (' || string_agg(column_name || ' ' || data_type || CASE WHEN is_nullable='NO' THEN ' NOT NULL' ELSE '' END, ', ') || ');' FROM information_schema.columns WHERE table_name='${t}' AND table_schema='public'" 2>&1 \
          | grep -v "---\|(.*rows)\|?column?" \
          | sed 's/^ *//;s/ *$//' \
          | grep -v '^$' >> "$outfile"
        echo "" >> "$outfile"
      done
      ;;
    *)
      echo "WARN: dump not fully implemented for ${DB_TYPE}, using information_schema"
      usql "${CONN_STR}" -c "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='${DB_NAME}' ORDER BY TABLE_NAME, ORDINAL_POSITION" 2>&1 >> "$outfile"
      ;;
  esac

  local count
  count=$(grep -c "^CREATE TABLE" "$outfile" 2>/dev/null || echo 0)
  local size
  size=$(wc -c < "$outfile" | tr -d ' ')
  echo "Dumped ${count} tables → ${outfile} (${size} bytes)"
}

cmd_search() {
  local alias="$1" keyword="$2"
  if [ -z "$alias" ] || [ -z "$keyword" ]; then
    echo "Usage: db.sh search <alias> <keyword>"
    exit 1
  fi
  _auto_refresh_if_stale "$alias"
  local file="${SCHEMA_DIR}/${alias}.schema.sql"
  grep -i "${keyword}" "$file" || echo "No match for '${keyword}'"
}

cmd_refresh() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh refresh <alias>"
    exit 1
  fi
  echo "Refreshing schema for ${alias}..."
  cmd_dump "$alias"
}

cmd_tables() {
  local alias="$1"
  if [ -z "$alias" ]; then
    echo "Usage: db.sh tables <alias>"
    exit 1
  fi
  _auto_refresh_if_stale "$alias"
  local file="${SCHEMA_DIR}/${alias}.schema.sql"
  grep -o 'CREATE TABLE "[^"]*"' "$file" 2>/dev/null | sed 's/CREATE TABLE "//;s/"//' \
    || grep -o 'CREATE TABLE [^ (]*' "$file" 2>/dev/null | sed 's/CREATE TABLE //' \
    || echo "No tables found"
}

cmd_desc() {
  local alias="$1" table="$2"
  if [ -z "$alias" ] || [ -z "$table" ]; then
    echo "Usage: db.sh desc <alias> <table>"
    exit 1
  fi
  _auto_refresh_if_stale "$alias"
  local file="${SCHEMA_DIR}/${alias}.schema.sql"
  grep -i "CREATE TABLE.*${table}" "$file" || echo "Table '${table}' not found in cache"
}

cmd_help() {
  cat <<'HELP'
db.sh — Database CLI wrapper

Profile Management:
  setup                          Install usql & init directories
  list                           List profiles with schema status
  add <project> <type> <env> ... Create profile (opens editor for password)
  edit <alias>                   Edit profile in editor
  remove <alias>                 Delete profile + schema cache
  test <alias>                   Test connection (with latency)

Query:
  query <alias[,a2]> "<sql>" [fmt]  Run query (fmt: table|csv|json)

Schema:
  dump <alias>                   Dump schema as DDL cache
  search <alias> <keyword>       Search cached schema (auto-refresh if stale)
  tables <alias>                 List all table names from cache
  desc <alias> <table>           Show DDL for specific table
  refresh <alias>                Force rebuild schema cache

Config:
  DB_SCHEMA_MAX_AGE=7            Days before auto-refresh (env var, default: 7)

DB types: mariadb, mysql, postgres, sqlite, mssql, oracle
Profiles: ~/.claude/db/*.env
Schema:   ~/.claude/db/schema/*.schema.sql
HELP
}

# --- main ---

case "${1:-help}" in
  setup)   cmd_setup ;;
  list)    cmd_list ;;
  add)     shift; cmd_add "$@" ;;
  edit)    shift; cmd_edit "$@" ;;
  remove)  shift; cmd_remove "$@" ;;
  test)    shift; cmd_test "$@" ;;
  query)   shift; cmd_query "$@" ;;
  dump)    shift; cmd_dump "$@" ;;
  search)  shift; cmd_search "$@" ;;
  tables)  shift; cmd_tables "$@" ;;
  desc)    shift; cmd_desc "$@" ;;
  refresh) shift; cmd_refresh "$@" ;;
  help|-h|--help) cmd_help ;;
  *)       echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
