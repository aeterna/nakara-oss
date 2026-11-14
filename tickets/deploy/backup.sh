#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
KEEP="${KEEP_BACKUPS:-7}"
PGHOST="${POSTGRES_HOST:-postgres}"
PGPORT="${POSTGRES_PORT:-5432}"
PGUSER="${POSTGRES_USER:-postgres}"
PGDATABASE="${POSTGRES_DB:-tickets}"

if [ -n "${POSTGRES_PASSWORD_FILE:-}" ] && [ -f "${POSTGRES_PASSWORD_FILE}" ]; then
  export PGPASSWORD="$(cat "${POSTGRES_PASSWORD_FILE}")"
elif [ -n "${POSTGRES_PASSWORD:-}" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
fi

mkdir -p "${BACKUP_DIR}"

run_backup() {
  TIMESTAMP="$(date -u +%Y%m%d_%H%M%SZ)"
  FILENAME="${BACKUP_DIR}/${PGDATABASE}_${TIMESTAMP}.sql.gz"
  echo "[$(date -u)] Starting database backup to ${FILENAME}..."
  pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" | gzip > "${FILENAME}"
  echo "[$(date -u)] Database backup completed successfully."

  echo "[$(date -u)] Pruning backups (retaining newest ${KEEP})..."
  TOTAL_COUNT=$(ls -1t "${BACKUP_DIR}/${PGDATABASE}_"*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
  if [ "${TOTAL_COUNT}" -gt "${KEEP}" ]; then
    ls -1t "${BACKUP_DIR}/${PGDATABASE}_"*.sql.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old_file; do
      echo "[$(date -u)] Removing old backup: ${old_file}"
      rm -f "${old_file}"
    done
  fi
  echo "[$(date -u)] Backup retention check complete."
}

# When RUN_ONCE=1 is set, run a single backup and exit (e.g. cron or one-off tasks)
if [ "${RUN_ONCE:-0}" = "1" ]; then
  run_backup
  exit 0
fi

# Default daemon mode: run daily (every 86400 seconds)
while true; do
  run_backup
  echo "[$(date -u)] Next scheduled backup in 24 hours..."
  sleep 86400
done
