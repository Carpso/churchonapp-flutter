#!/usr/bin/env python3
"""
Media Audit & R2 Migration Tool
================================
Scans all Supabase Storage buckets, computes sizes, and optionally
migrates files to Cloudflare R2 via the migrate-to-r2 edge function.

Usage:
    # Audit only (list all files and sizes)
    python tools/audit_media_r2.py audit

    # Dry-run migration (show what would be moved)
    python tools/audit_media_r2.py migrate --dry-run

    # Actually migrate a specific bucket
    python tools/audit_media_r2.py migrate --bucket sermons-vault

    # Migrate and update DB records
    python tools/audit_media_r2.py migrate --bucket bible-audio --update-urls

Requirements:
    pip install supabase python-dotenv
    Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env
"""

import argparse
import json
import os
import sys
from pathlib import Path
from datetime import datetime

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

try:
    from supabase import create_client, Client
except ImportError:
    print("Error: supabase package not installed. Run: pip install supabase")
    sys.exit(1)


def get_supabase_client() -> Client:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("Error: Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env")
        sys.exit(1)
    return create_client(url, key)


def format_size(size_bytes: int) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} PB"


def audit_bucket(client: Client, bucket_name: str, prefix: str = "") -> dict:
    """List all files in a bucket and compute statistics."""
    try:
        files = client.storage.from_(bucket_name).list(
            path=prefix,
            options={"limit": 1000, "sortBy": {"column": "name", "order": "asc"}}
        )
    except Exception as e:
        print(f"  Error listing bucket '{bucket_name}': {e}")
        return {"bucket": bucket_name, "files": [], "total_size": 0, "error": str(e)}

    total_size = 0
    file_list = []
    for f in files:
        size = f.get("metadata", {}).get("size", 0) if f.get("metadata") else 0
        total_size += size
        file_list.append({
            "name": f["name"],
            "path": f"{prefix}/{f['name']}" if prefix else f["name"],
            "size": size,
            "size_human": format_size(size),
            "content_type": f.get("metadata", {}).get("mimetype", "unknown"),
            "last_updated": f.get("updated_at", ""),
        })

    return {
        "bucket": bucket_name,
        "prefix": prefix or "(root)",
        "file_count": len(file_list),
        "total_size": total_size,
        "total_size_human": format_size(total_size),
        "files": file_list,
    }


def audit_all_buckets(client: Client) -> list:
    """Audit all storage buckets."""
    try:
        buckets_result = client.storage.list_buckets()
        buckets = buckets_result if isinstance(buckets_result, list) else []
    except Exception as e:
        print(f"Error listing buckets: {e}")
        return []

    results = []
    for bucket in buckets:
        bucket_name = bucket.get("name", "")
        print(f"  Scanning bucket: {bucket_name}...")
        result = audit_bucket(client, bucket_name)
        results.append(result)
        print(f"    {result['file_count']} files, {result['total_size_human']}")

    return results


def migrate_bucket(client: Client, bucket_name: str, dry_run: bool = True, prefix: str = "") -> dict:
    """Migrate files from Supabase Storage to R2 via edge function."""
    mode_text = "DRY RUN" if dry_run else "MIGRATING"
    print(f"\n  [{mode_text}] Bucket: {bucket_name}")

    try:
        response = client.functions.invoke("migrate-to-r2", body={
            "mode": "list" if dry_run else "migrate",
            "bucket": bucket_name,
            "prefix": prefix,
            "limit": 500,
        })

        result = response.get("data", response) if isinstance(response, dict) else response
        return result
    except Exception as e:
        print(f"    Error: {e}")
        return {"error": str(e)}


def update_db_urls(client: Client) -> dict:
    """Update bible_audio_files records to point to R2 URLs."""
    print("\n  Updating bible_audio_files records to use R2...")
    try:
        response = client.functions.invoke("migrate-to-r2", body={
            "mode": "update-urls",
        })
        result = response.get("data", response) if isinstance(response, dict) else response
        return result
    except Exception as e:
        print(f"    Error: {e}")
        return {"error": str(e)}


def generate_report(results: list, output_path: str = "media_audit_report.json"):
    """Save audit report to JSON."""
    report = {
        "generated_at": datetime.now().isoformat(),
        "total_buckets": len(results),
        "total_files": sum(r.get("file_count", 0) for r in results),
        "total_size": sum(r.get("total_size", 0) for r in results),
        "total_size_human": format_size(sum(r.get("total_size", 0) for r in results)),
        "buckets": results,
    }

    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)

    print(f"\nReport saved to {output_path}")
    return report


def main():
    parser = argparse.ArgumentParser(description="Media Audit & R2 Migration Tool")
    parser.add_argument("action", choices=["audit", "migrate", "update-urls"],
                        help="Action to perform")
    parser.add_argument("--bucket", help="Specific bucket to audit/migrate")
    parser.add_argument("--prefix", default="", help="Path prefix filter")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be migrated without actually migrating")
    parser.add_argument("--update-urls", action="store_true",
                        help="Also update DB records to point to R2")
    parser.add_argument("--output", default="media_audit_report.json",
                        help="Output file for audit report")

    args = parser.parse_args()
    client = get_supabase_client()

    if args.action == "audit":
        print("=== Media Audit ===\n")
        if args.bucket:
            result = audit_bucket(client, args.bucket, args.prefix)
            results = [result]
            print(f"\n  {result['file_count']} files, {result['total_size_human']}")
        else:
            results = audit_all_buckets(client)

        report = generate_report(results, args.output)
        print(f"\n  Total: {report['total_files']} files, {report['total_size_human']}")

    elif args.action == "migrate":
        print("=== R2 Migration ===\n")
        if args.bucket:
            buckets = [args.bucket]
        else:
            try:
                buckets_result = client.storage.list_buckets()
                buckets = [b.get("name", "") for b in (buckets_result if isinstance(buckets_result, list) else [])]
            except Exception as e:
                print(f"Error listing buckets: {e}")
                return

        for bucket_name in buckets:
            result = migrate_bucket(client, bucket_name, args.dry_run, args.prefix)
            if "error" in result:
                print(f"    Error migrating {bucket_name}: {result['error']}")
            elif "summary" in result:
                s = result["summary"]
                print(f"    Result: {s.get('migrated', 0)} migrated, "
                      f"{s.get('skipped', 0)} skipped, "
                      f"{s.get('failed', 0)} failed")

        if args.update_urls and not args.dry_run:
            url_result = update_db_urls(client)
            if "summary" in url_result:
                s = url_result["summary"]
                print(f"    URL updates: {s.get('updated', 0)} of {s.get('total', 0)}")

    elif args.action == "update-urls":
        print("=== Update DB URLs to R2 ===\n")
        result = update_db_urls(client)
        if "summary" in result:
            s = result["summary"]
            print(f"  Updated: {s.get('updated', 0)} of {s.get('total', 0)} records")
        elif "error" in result:
            print(f"  Error: {result['error']}")


if __name__ == "__main__":
    main()
