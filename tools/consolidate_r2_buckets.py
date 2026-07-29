#!/usr/bin/env python3
"""
Consolidate R2 buckets: copy all objects from church-on-app-maps into choa-sermons-vault/maps/.

Usage:
    python tools/consolidate_r2_buckets.py --r2-endpoint <endpoint> --r2-access-key <key> --r2-secret-key <secret>

Or set env vars: R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
"""
import argparse
import os
import sys

try:
    import boto3
    from botocore.config import Config
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)


SOURCE_BUCKET = "church-on-app-maps"
DEST_BUCKET = "choa-sermons-vault"
DEST_PREFIX = "maps"


def main():
    parser = argparse.ArgumentParser(description="Consolidate R2 buckets")
    parser.add_argument("--r2-endpoint", default=os.getenv("R2_ENDPOINT"))
    parser.add_argument("--r2-access-key", default=os.getenv("R2_ACCESS_KEY_ID"))
    parser.add_argument("--r2-secret-key", default=os.getenv("R2_SECRET_ACCESS_KEY"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not all([args.r2_endpoint, args.r2_access_key, args.r2_secret_key]):
        print("ERROR: Missing R2 credentials. Provide via --flags or env vars.")
        sys.exit(1)

    s3 = boto3.client(
        "s3",
        endpoint_url=args.r2_endpoint,
        aws_access_key_id=args.r2_access_key,
        aws_secret_access_key=args.r2_secret_key,
        config=Config(signature_version="s3v4"),
        region_name="auto",
    )

    # List all objects in source bucket
    print(f"Listing objects in {SOURCE_BUCKET}...")
    paginator = s3.get_paginator("list_objects_v2")
    source_keys = []
    for page in paginator.paginate(Bucket=SOURCE_BUCKET):
        for obj in page.get("Contents", []):
            source_keys.append(obj["Key"])

    print(f"Found {len(source_keys)} objects in {SOURCE_BUCKET}")

    if not source_keys:
        print("Nothing to copy.")
        return

    copied = 0
    skipped = 0
    failed = 0

    for key in source_keys:
        dest_key = f"{DEST_PREFIX}/{key}"
        
        if args.dry_run:
            print(f"  [DRY RUN] {key} -> {DEST_BUCKET}/{dest_key}")
            copied += 1
            continue

        try:
            # Check if already exists
            try:
                s3.head_object(Bucket=DEST_BUCKET, Key=dest_key)
                print(f"  [SKIP] {key} (already exists)")
                skipped += 1
                continue
            except s3.exceptions.ClientError:
                pass

            # Copy
            s3.copy_object(
                Bucket=DEST_BUCKET,
                Key=dest_key,
                CopySource={"Bucket": SOURCE_BUCKET, "Key": key},
            )
            print(f"  [OK] {key} -> {dest_key}")
            copied += 1
        except Exception as e:
            print(f"  [FAIL] {key}: {e}")
            failed += 1

    print(f"\nDone: {copied} copied, {skipped} skipped, {failed} failed")
    print(f"Files are now at: https://media.churchonapp.com/{DEST_PREFIX}/<filename>")
    print(f"\nNext steps:")
    print(f"  1. Update MAPS_ZAMBIA_URL in .env to: https://media.churchonapp.com/maps/zambia.pmtiles")
    print(f"  2. Update MAPS_ZIMBABWE_URL in .env to: https://media.churchonapp.com/maps/zimbabwe.pmtiles")
    print(f"  3. Delete old bucket {SOURCE_BUCKET} via Cloudflare dashboard")


if __name__ == "__main__":
    main()
