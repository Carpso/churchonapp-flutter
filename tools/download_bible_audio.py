#!/usr/bin/env python3
"""
Download Bible audio from mp3bible.ca and upload to Cloudflare R2.

Scrapes directory listings for each book, downloads individual chapter MP3s,
and uploads to R2 with path: audio/kjv/{BookName}/{Chapter}.mp3

Usage:
    python tools/download_bible_audio.py

Requires: pip install boto3 requests
"""
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote

try:
    import boto3
    from botocore.config import Config
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")
    sys.exit(1)


def load_env():
    env_path = Path(__file__).parent.parent / ".env"
    env = {}
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


# All 66 Bible books: (book_num, display_name, directory_name, chapters)
BOOKS = [
    ("01", "Genesis", "Genesis", 50),
    ("02", "Exodus", "Exodus", 40),
    ("03", "Leviticus", "Leviticus", 27),
    ("04", "Numbers", "Numbers", 36),
    ("05", "Deuteronomy", "Deuteronomy", 34),
    ("06", "Joshua", "Joshua", 24),
    ("07", "Judges", "Judges", 21),
    ("08", "Ruth", "Ruth", 4),
    ("09", "1 Samuel", "1Samuel", 31),
    ("10", "2 Samuel", "2Samuel", 24),
    ("11", "1 Kings", "1Kings", 22),
    ("12", "2 Kings", "2Kings", 25),
    ("13", "1 Chronicles", "1Chronicles", 29),
    ("14", "2 Chronicles", "2Chronicles", 36),
    ("15", "Ezra", "Ezra", 10),
    ("16", "Nehemiah", "Nehemiah", 13),
    ("17", "Esther", "Esther", 10),
    ("18", "Job", "Job", 42),
    ("19", "Psalms", "Psalms", 150),
    ("20", "Proverbs", "Proverbs", 31),
    ("21", "Ecclesiastes", "Ecclesiastes", 12),
    ("22", "Song of Solomon", "Song_of_Solomon", 8),
    ("23", "Isaiah", "Isaiah", 66),
    ("24", "Jeremiah", "Jeremiah", 52),
    ("25", "Lamentations", "Lamentations", 5),
    ("26", "Ezekiel", "Ezekiel", 48),
    ("27", "Daniel", "Daniel", 12),
    ("28", "Hosea", "Hosea", 14),
    ("29", "Joel", "Joel", 3),
    ("30", "Amos", "Amos", 9),
    ("31", "Obadiah", "Obadiah", 1),
    ("32", "Jonah", "Jonah", 4),
    ("33", "Micah", "Micah", 7),
    ("34", "Nahum", "Nahum", 3),
    ("35", "Habakkuk", "Habakkuk", 3),
    ("36", "Zephaniah", "Zephaniah", 3),
    ("37", "Haggai", "Haggai", 2),
    ("38", "Zechariah", "Zechariah", 14),
    ("39", "Malachi", "Malachi", 4),
    ("40", "Matthew", "Matthew", 28),
    ("41", "Mark", "Mark", 16),
    ("42", "Luke", "Luke", 24),
    ("43", "John", "John", 21),
    ("44", "Acts", "Acts", 28),
    ("45", "Romans", "Romans", 16),
    ("46", "1 Corinthians", "1Corinthians", 16),
    ("47", "2 Corinthians", "2Corinthians", 13),
    ("48", "Galatians", "Galatians", 6),
    ("49", "Ephesians", "Ephesians", 6),
    ("50", "Philippians", "Philippians", 4),
    ("51", "Colossians", "Colossians", 4),
    ("52", "1 Thessalonians", "1Thessalonians", 5),
    ("53", "2 Thessalonians", "2Thessalonians", 3),
    ("54", "1 Timothy", "1Timothy", 6),
    ("55", "2 Timothy", "2Timothy", 4),
    ("56", "Titus", "Titus", 3),
    ("57", "Philemon", "Philemon", 1),
    ("58", "Hebrews", "Hebrews", 13),
    ("59", "James", "James", 5),
    ("60", "1 Peter", "1Peter", 5),
    ("61", "2 Peter", "2Peter", 3),
    ("62", "1 John", "1John", 5),
    ("63", "2 John", "2John", 1),
    ("64", "3 John", "3John", 1),
    ("65", "Jude", "Jude", 1),
    ("66", "Revelation", "Revelation", 22),
]

MP3BIBLE_BASE = "https://www.mp3bible.ca"
TRANSLATION = "kjv"
R2_PREFIX = f"audio/{TRANSLATION}"


def scrape_book_dir(book_num: str, dir_name: str) -> list[tuple[str, int]]:
    """Scrape mp3bible.ca directory listing for a book.
    
    Returns list of (encoded_filename, chapter_number) tuples.
    """
    url = f"{MP3BIBLE_BASE}/{book_num}_{dir_name}/"
    try:
        resp = requests.get(url, timeout=30)
        if resp.status_code != 200:
            return []
        
        filenames = re.findall(r'href="([^"]+\.mp3)"', resp.text)
        
        results = []
        for fn in filenames:
            fn_decoded = unquote(fn)
            # Match 3-digit (Numbers001), 2-digit (Numbers01), or no chapter (Philemon.mp3)
            match3 = re.search(r'(\d{3})\.mp3$', fn_decoded)
            match2 = re.search(r'(\d{2})\.mp3$', fn_decoded)
            match0 = re.search(r'[A-Za-z]\.mp3$', fn_decoded)
            if match3:
                chapter = int(match3.group(1))
            elif match2:
                chapter = int(match2.group(1))
            elif match0:
                chapter = 1
            else:
                continue
            results.append((fn, chapter))
        
        return results
    except Exception as e:
        print(f"  Scrape error: {e}")
        return []


def download_and_upload(args: tuple) -> tuple[str, int, int, int]:
    """Download one MP3 from mp3bible.ca and upload to R2. Returns (book_name, uploaded, skipped, failed)."""
    s3, r2_bucket, book_num, display_name, dir_name, filename, chapter, existing_keys = args
    r2_key = f"{R2_PREFIX}/{display_name}/{chapter:03d}.mp3"
    
    if r2_key in existing_keys:
        return (display_name, 0, 1, 0)
    
    src_url = f"{MP3BIBLE_BASE}/{book_num}_{dir_name}/{filename}"
    
    tmp = None
    try:
        for attempt in range(3):
            try:
                resp = requests.get(src_url, timeout=60, stream=True)
                if resp.status_code != 200:
                    return (display_name, 0, 0, 1)
                
                tmp = Path(tempfile.mktemp(suffix=".mp3"))
                with open(tmp, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=16384):
                        f.write(chunk)
                
                s3.upload_file(str(tmp), r2_bucket, r2_key, ExtraArgs={"ContentType": "audio/mpeg"})
                existing_keys.add(r2_key)
                return (display_name, 1, 0, 0)
            except Exception:
                if attempt < 2:
                    time.sleep(1)
                continue
        return (display_name, 0, 0, 1)
    finally:
        if tmp and tmp.exists():
            tmp.unlink(missing_ok=True)


def main():
    from concurrent.futures import ThreadPoolExecutor, as_completed
    
    env = load_env()
    
    r2_endpoint = env.get("R2_ENDPOINT", "")
    r2_access_key = env.get("R2_ACCESS_KEY_ID", "")
    r2_secret_key = env.get("R2_SECRET_ACCESS_KEY", "")
    r2_bucket = env.get("R2_BUCKET", "choa-sermons-vault")
    
    if not all([r2_endpoint, r2_access_key, r2_secret_key]):
        print("ERROR: Missing R2 credentials in .env")
        print("Need: R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY")
        sys.exit(1)
    
    print(f"R2 Endpoint: {r2_endpoint}")
    print(f"R2 Bucket: {r2_bucket}")
    print(f"Source: mp3bible.ca (Audio Scriptures International)")
    print(f"Translation: {TRANSLATION.upper()}")
    print(f"Total books: {len(BOOKS)}")
    print()
    
    s3 = boto3.client(
        "s3",
        endpoint_url=r2_endpoint,
        aws_access_key_id=r2_access_key,
        aws_secret_access_key=r2_secret_key,
        config=Config(signature_version="s3v4"),
        region_name="auto",
    )
    
    existing_keys = set()
    try:
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=r2_bucket, Prefix=f"{R2_PREFIX}/"):
            for obj in page.get("Contents", []):
                existing_keys.add(obj["Key"])
    except Exception as e:
        print(f"Warning: Could not list R2 bucket: {e}")
    
    print(f"Existing files in R2 under {R2_PREFIX}/: {len(existing_keys)}")
    print()
    
    # Phase 1: Scrape all directory listings
    all_jobs = []
    for book_num, display_name, dir_name, chapters in BOOKS:
        mp3_list = scrape_book_dir(book_num, dir_name)
        if not mp3_list:
            print(f"  WARNING: No files found for {display_name}")
            continue
        for fn, chapter in mp3_list:
            r2_key = f"{R2_PREFIX}/{display_name}/{chapter:03d}.mp3"
            if r2_key not in existing_keys:
                all_jobs.append((s3, r2_bucket, book_num, display_name, dir_name, fn, chapter, existing_keys))
    
    remaining = len(all_jobs)
    print(f"Files to download+upload: {remaining}")
    print(f"Files already in R2: {sum(1 for b in BOOKS for c in range(1, b[3]+1) if f'{R2_PREFIX}/{b[1]}/{c:03d}.mp3' in existing_keys)}")
    print()
    
    if remaining == 0:
        print("Nothing to do — all files already in R2!")
        return
    
    # Phase 2: Parallel download + upload
    total_uploaded = 0
    total_skipped = 0
    total_failed = 0
    completed = 0
    
    WORKERS = 6
    with ThreadPoolExecutor(max_workers=WORKERS) as executor:
        futures = {executor.submit(download_and_upload, job): job for job in all_jobs}
        
        for future in as_completed(futures):
            completed += 1
            book_name, up, sk, fl = future.result()
            total_uploaded += up
            total_skipped += sk
            total_failed += fl
            
            if completed % 50 == 0 or completed == remaining:
                print(f"  Progress: {completed}/{remaining} "
                      f"(uploaded={total_uploaded}, skipped={total_skipped}, failed={total_failed})")
    
    print()
    print("=" * 60)
    print("DONE!")
    print(f"  Uploaded: {total_uploaded} chapters to R2")
    print(f"  Skipped: {total_skipped} (already exists)")
    print(f"  Failed: {total_failed}")
    print(f"  R2 URL pattern: https://{env.get('R2_PUBLIC_DOMAIN', 'media.churchonapp.com')}/{R2_PREFIX}/{{Book}}/{{Chapter}}.mp3")
    print()
    print("Next: Run seed_bible_text.py to populate bible_audio_files table")


if __name__ == "__main__":
    main()
