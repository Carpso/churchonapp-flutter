"""Run KJV Bible SQL batches via Supabase REST API."""
import json
import re
import sys
import time
from pathlib import Path
import requests

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

def parse_sql_file(sql_path):
    """Parse SQL INSERT blocks into structured data."""
    content = Path(sql_path).read_text(encoding="utf-8")
    blocks = []
    
    # Split by INSERT statements
    inserts = re.split(r'INSERT INTO bible_verses', content)
    
    for insert in inserts[1:]:  # skip header
        # Extract book name from CROSS JOIN
        book_match = re.search(r"bible_books WHERE name = '([^']+)'", insert)
        if not book_match:
            continue
        book_name = book_match.group(1)
        
        # Extract VALUES
        vals_match = re.search(r'FROM \(VALUES\n(.+?)\n\) AS v', insert, re.DOTALL)
        if not vals_match:
            continue
        
        values_str = vals_match.group(1)
        verses = []
        
        # Parse each value tuple
        for val_match in re.finditer(
            r"\('([^']+)', '([^']+)', (\d+), (\d+), E'((?:[^'\\]|\\'|\\\\)*)'\)", 
            values_str
        ):
            ch = int(val_match.group(3))
            verse = int(val_match.group(4))
            text = val_match.group(5).replace("\\'", "'").replace("\\\\", "\\")
            verses.append({"chapter": ch, "verse": verse, "text": text})
        
        blocks.append({"book_name": book_name, "verses": verses})
    
    return blocks

def main():
    env = load_env()
    url = env.get("SUPABASE_URL", "")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "")
    anon_key = env.get("SUPABASE_ANON_KEY", "")
    api_key = service_key or anon_key
    
    if not url:
        print("ERROR: Need SUPABASE_URL in .env")
        sys.exit(1)
    
    if not service_key:
        print("WARNING: No SUPABASE_SERVICE_ROLE_KEY, using anon key (may fail if RLS blocks inserts)")
    
    headers = {
        "apikey": api_key,
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    
    # Get KJV translation ID
    r = requests.get(f"{url}/rest/v1/bible_translations?code=eq.kjv&select=id",
        headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}, timeout=10)
    kjv_id = r.json()[0]["id"]
    print(f"KJV ID: {kjv_id}")
    
    # Get all book IDs
    r = requests.get(f"{url}/rest/v1/bible_books?select=id,name",
        headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}, timeout=10)
    book_map = {b["name"]: b["id"] for b in r.json()}
    print(f"Books loaded: {len(book_map)}")
    
    # Process batch files
    batch_dir = Path(__file__).parent.parent / "supabase" / "migrations" / "kjv_batches"
    batches = sorted(batch_dir.glob("batch_*.sql"))
    
    total_inserted = 0
    for batch_file in batches:
        print(f"\n--- {batch_file.name} ---")
        blocks = parse_sql_file(batch_file)
        
        batch_inserted = 0
        for block in blocks:
            book_name = block["book_name"]
            book_id = book_map.get(book_name)
            if not book_id:
                print(f"  WARNING: Book '{book_name}' not found in DB, skipping")
                continue
            
            verses = block["verses"]
            
            # Insert in chunks of 50
            for i in range(0, len(verses), 50):
                chunk = verses[i:i+50]
                rows = [{
                    "translation_id": kjv_id,
                    "book_id": book_id,
                    "chapter": v["chapter"],
                    "verse": v["verse"],
                    "text": v["text"],
                } for v in chunk]
                
                r = requests.post(
                    f"{url}/rest/v1/bible_verses",
                    headers=headers,
                    json=rows,
                    timeout=30,
                )
                
                if r.status_code not in (200, 201):
                    print(f"  ERROR: {r.status_code} {r.text[:200]}")
                    # Try one-by-one for failed batch
                    for row in rows:
                        r2 = requests.post(
                            f"{url}/rest/v1/bible_verses",
                            headers=headers,
                            json=row,
                            timeout=30,
                        )
                        if r2.status_code in (200, 201):
                            batch_inserted += 1
                        else:
                            print(f"    FAIL ch{row['chapter']}v{row['verse']}: {r2.status_code} {r2.text[:100]}")
                else:
                    batch_inserted += len(chunk)
        
        total_inserted += batch_inserted
        print(f"  Inserted: {batch_inserted} verses (running total: {total_inserted})")
    
    print(f"\nDone! Total inserted: {total_inserted} verses")

if __name__ == "__main__":
    main()
