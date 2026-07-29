#!/usr/bin/env python3
"""
Seed bible_books and bible_audio_files tables with all 66 books and 1189 R2 paths.
"""
import sys
import requests
from pathlib import Path

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

ALL_BOOKS = [
    ("Genesis", "Gen", "OT", 1, 50), ("Exodus", "Exod", "OT", 2, 40),
    ("Leviticus", "Lev", "OT", 3, 27), ("Numbers", "Num", "OT", 4, 36),
    ("Deuteronomy", "Deut", "OT", 5, 34), ("Joshua", "Josh", "OT", 6, 24),
    ("Judges", "Judg", "OT", 7, 21), ("Ruth", "Ruth", "OT", 8, 4),
    ("1 Samuel", "1 Sam", "OT", 9, 31), ("2 Samuel", "2 Sam", "OT", 10, 24),
    ("1 Kings", "1 Kgs", "OT", 11, 22), ("2 Kings", "2 Kgs", "OT", 12, 25),
    ("1 Chronicles", "1 Chr", "OT", 13, 29), ("2 Chronicles", "2 Chr", "OT", 14, 36),
    ("Ezra", "Ezra", "OT", 15, 10), ("Nehemiah", "Neh", "OT", 16, 13),
    ("Esther", "Esth", "OT", 17, 10), ("Job", "Job", "OT", 18, 42),
    ("Psalms", "Ps", "OT", 19, 150), ("Proverbs", "Prov", "OT", 20, 31),
    ("Ecclesiastes", "Eccl", "OT", 21, 12), ("Song of Solomon", "Song", "OT", 22, 8),
    ("Isaiah", "Isa", "OT", 23, 66), ("Jeremiah", "Jer", "OT", 24, 52),
    ("Lamentations", "Lam", "OT", 25, 5), ("Ezekiel", "Ezek", "OT", 26, 48),
    ("Daniel", "Dan", "OT", 27, 12), ("Hosea", "Hos", "OT", 28, 14),
    ("Joel", "Joel", "OT", 29, 3), ("Amos", "Amos", "OT", 30, 9),
    ("Obadiah", "Obad", "OT", 31, 1), ("Jonah", "Jonah", "OT", 32, 4),
    ("Micah", "Mic", "OT", 33, 7), ("Nahum", "Nah", "OT", 34, 3),
    ("Habakkuk", "Hab", "OT", 35, 3), ("Zephaniah", "Zeph", "OT", 36, 3),
    ("Haggai", "Hag", "OT", 37, 2), ("Zechariah", "Zech", "OT", 38, 14),
    ("Malachi", "Mal", "OT", 39, 4),
    ("Matthew", "Matt", "NT", 40, 28), ("Mark", "Mark", "NT", 41, 16),
    ("Luke", "Luke", "NT", 42, 24), ("John", "John", "NT", 43, 21),
    ("Acts", "Acts", "NT", 44, 28), ("Romans", "Rom", "NT", 45, 16),
    ("1 Corinthians", "1 Cor", "NT", 46, 16), ("2 Corinthians", "2 Cor", "NT", 47, 13),
    ("Galatians", "Gal", "NT", 48, 6), ("Ephesians", "Eph", "NT", 49, 6),
    ("Philippians", "Phil", "NT", 50, 4), ("Colossians", "Col", "NT", 51, 4),
    ("1 Thessalonians", "1 Thess", "NT", 52, 5), ("2 Thessalonians", "2 Thess", "NT", 53, 3),
    ("1 Timothy", "1 Tim", "NT", 54, 6), ("2 Timothy", "2 Tim", "NT", 55, 4),
    ("Titus", "Titus", "NT", 56, 3), ("Philemon", "Phlm", "NT", 57, 1),
    ("Hebrews", "Heb", "NT", 58, 13), ("James", "Jas", "NT", 59, 5),
    ("1 Peter", "1 Pet", "NT", 60, 5), ("2 Peter", "2 Pet", "NT", 61, 3),
    ("1 John", "1 John", "NT", 62, 5), ("2 John", "2 John", "NT", 63, 1),
    ("3 John", "3 John", "NT", 64, 1), ("Jude", "Jude", "NT", 65, 1),
    ("Revelation", "Rev", "NT", 66, 22),
]


def main():
    env = load_env()
    url = env.get("SUPABASE_URL", "")
    key = env.get("SUPABASE_ANON_KEY", "")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", key)
    
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    
    # Step 1: Check if bible_books already seeded
    r = requests.get(f"{url}/rest/v1/bible_books?select=count", headers={
        "apikey": key, "Authorization": f"Bearer {key}",
        "Prefer": "count=exact", "Range-Unit": "items", "Range": "0-0"
    }, timeout=10)
    count = int(r.headers.get("content-range", "*/0").split("/")[1])
    
    if count == 66:
        print("bible_books already seeded (66 rows)")
    else:
        print(f"Seeding bible_books ({count} existing, need 66)...")
        
        # Get KJV translation id
        r = requests.get(f"{url}/rest/v1/bible_translations?code=eq.kjv&select=id", headers={
            "apikey": key, "Authorization": f"Bearer {key}"
        }, timeout=10)
        kjv_id = r.json()[0]["id"]
        print(f"  KJV translation_id: {kjv_id}")
        
        # Insert books in batches
        rows = []
        for name, abbrev, testament, order, chapters in ALL_BOOKS:
            rows.append({
                "name": name,
                "abbreviation": abbrev,
                "testament": testament,
                "book_order": order,
                "testament_order": testament,
                "chapters": chapters,
            })
        
        # Batch insert (Supabase limits ~100 rows per request)
        batch_size = 50
        for i in range(0, len(rows), batch_size):
            batch = rows[i:i+batch_size]
            r = requests.post(f"{url}/rest/v1/bible_books", json=batch, headers=headers, timeout=30)
            if r.status_code >= 400:
                print(f"  ERROR inserting books batch {i//batch_size+1}: {r.status_code} {r.text[:200]}")
                sys.exit(1)
            print(f"  Inserted books batch {i//batch_size+1}: {len(batch)} rows")
        
        print("  bible_books seeded!")
    
    # Step 2: Get book IDs (name -> id mapping)
    r = requests.get(f"{url}/rest/v1/bible_books?select=id,name,book_order", headers={
        "apikey": key, "Authorization": f"Bearer {key}"
    }, timeout=15)
    book_map = {b["name"]: b["id"] for b in r.json()}
    print(f"  Book ID map: {len(book_map)} books")
    
    # Get KJV translation id
    r = requests.get(f"{url}/rest/v1/bible_translations?code=eq.kjv&select=id", headers={
        "apikey": key, "Authorization": f"Bearer {key}"
    }, timeout=10)
    kjv_id = r.json()[0]["id"]
    
    # Step 3: Check bible_audio_files count
    r = requests.get(f"{url}/rest/v1/bible_audio_files?select=count", headers={
        "apikey": key, "Authorization": f"Bearer {key}",
        "Prefer": "count=exact", "Range-Unit": "items", "Range": "0-0"
    }, timeout=10)
    audio_count = int(r.headers.get("content-range", "*/0").split("/")[1])
    
    if audio_count == 1189:
        print("bible_audio_files already seeded (1189 rows)")
    else:
        print(f"\nSeeding bible_audio_files ({audio_count} existing, need 1189)...")
        
        # Build all audio file rows
        rows = []
        for name, abbrev, testament, order, chapters in ALL_BOOKS:
            book_id = book_map[name]
            for ch in range(1, chapters + 1):
                rows.append({
                    "translation_id": kjv_id,
                    "book_id": book_id,
                    "chapter": ch,
                    "storage_provider": "r2",
                    "storage_bucket": "choa-sermons-vault",
                    "storage_path": f"audio/kjv/{name}/{ch:03d}.mp3",
                    "format": "mp3",
                    "generation_status": "completed",
                })
        
        print(f"  Total rows to insert: {len(rows)}")
        
        # Batch insert
        batch_size = 100
        total_inserted = 0
        for i in range(0, len(rows), batch_size):
            batch = rows[i:i+batch_size]
            r = requests.post(f"{url}/rest/v1/bible_audio_files", json=batch, headers=headers, timeout=30)
            if r.status_code >= 400:
                print(f"  ERROR inserting audio batch {i//batch_size+1}: {r.status_code} {r.text[:200]}")
                # Try smaller batches
                for j, row in enumerate(batch):
                    r2 = requests.post(f"{url}/rest/v1/bible_audio_files", json=[row], headers=headers, timeout=10)
                    if r2.status_code >= 400:
                        print(f"    FAILED row {i+j}: {row['storage_path']} -> {r2.status_code} {r2.text[:100]}")
                continue
            total_inserted += len(batch)
            if (i // batch_size + 1) % 5 == 0 or i + batch_size >= len(rows):
                print(f"  Progress: {total_inserted}/{len(rows)}")
        
        print(f"  bible_audio_files seeded: {total_inserted} rows")
    
    print("\nDone!")


if __name__ == "__main__":
    main()
