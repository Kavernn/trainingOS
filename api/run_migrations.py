#!/usr/bin/env python3
"""
run_migrations.py — Apply pending SQL migrations to Supabase.

Usage:
    python run_migrations.py [--dry-run] [--force VERSION]

Reads all *.sql files from docs/migrations/, checks schema_migrations table
for already-applied versions, and runs only the pending ones in alphabetical order.

Options:
    --dry-run         List pending migrations without running them.
    --force VERSION   Re-run a specific migration version (e.g. 024_exercise_logs_rpe_pain_zone).
"""

import os
import sys
import argparse
import logging
from pathlib import Path
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
logger = logging.getLogger("migrations")

MIGRATIONS_DIR = Path(__file__).parent.parent / "docs" / "migrations"


def _get_client():
    from supabase import create_client
    url = os.environ.get("SUPABASE_URL", "")
    key = (os.environ.get("SUPABASE_SERVICE_KEY")
           or os.environ.get("SUPABASE_KEY")
           or os.environ.get("SUPABASE_ANON_KEY", ""))
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
    return create_client(url, key)


def _applied_versions(client) -> set[str]:
    try:
        resp = client.table("schema_migrations").select("version").execute()
        return {row["version"] for row in (resp.data or [])}
    except Exception:
        # Table doesn't exist yet — migration 026 must be run first manually
        return set()


def _record_version(client, version: str):
    client.table("schema_migrations").upsert(
        {"version": version, "applied_at": datetime.now(timezone.utc).isoformat()},
        on_conflict="version",
    ).execute()


def sync_applied(client):
    """Mark all .sql files as applied in schema_migrations (bootstrap after manual apply)."""
    sql_files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    applied = _applied_versions(client)
    count = 0
    for path in sql_files:
        version = path.stem
        if version not in applied:
            _record_version(client, version)
            logger.info("  marked %s as applied", version)
            count += 1
    logger.info("Sync done — %d version(s) recorded.", count)


def run(dry_run: bool = False, force_version: str | None = None):
    sql_files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not sql_files:
        logger.error("No migration files found in %s", MIGRATIONS_DIR)
        sys.exit(1)

    client = _get_client()
    applied = _applied_versions(client)

    pending = []
    for path in sql_files:
        version = path.stem
        if force_version and version != force_version:
            continue
        if version not in applied:
            pending.append(path)

    if not pending:
        logger.info("All migrations up to date (%d applied).", len(applied))
        return

    logger.info("Pending migrations: %d", len(pending))
    for path in pending:
        logger.info("  → %s", path.stem)

    if dry_run:
        logger.info("[dry-run] No changes made.")
        return

    for path in pending:
        version = path.stem
        sql = path.read_text(encoding="utf-8")
        logger.info("Applying %s …", version)
        try:
            # Supabase Python client doesn't expose raw SQL directly —
            # use the PostgREST rpc endpoint or the postgres connection.
            # For direct SQL, use the postgres connection via psycopg2.
            import psycopg2
            db_url = os.environ.get("DATABASE_URL", "")
            if not db_url:
                raise RuntimeError(
                    "DATABASE_URL required for raw SQL migrations. "
                    "Set it to your Supabase postgres connection string."
                )
            conn = psycopg2.connect(db_url)
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(sql)
            conn.close()
            _record_version(client, version)
            logger.info("  ✓ %s applied", version)
        except Exception as e:
            logger.error("  ✗ %s FAILED: %s", version, e)
            logger.error("Stopping — fix the error and re-run.")
            sys.exit(1)

    logger.info("Done. %d migration(s) applied.", len(pending))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run pending Supabase migrations")
    parser.add_argument("--dry-run", action="store_true", help="List pending without running")
    parser.add_argument("--force", metavar="VERSION", help="Re-run a specific version")
    parser.add_argument("--sync", action="store_true", help="Mark all existing files as applied (bootstrap after manual apply)")
    args = parser.parse_args()
    client = _get_client()
    if args.sync:
        sync_applied(client)
    else:
        run(dry_run=args.dry_run, force_version=args.force)
