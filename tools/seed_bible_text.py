#!/usr/bin/env python3
"""
Download KJV from GitHub (aruljohn/Bible-kjv) and seed bible_verses via REST API.
Requires SUPABASE_SERVICE_ROLE_KEY in .env.
"""
import sys
import time
import requests
from pathlib import Path

BOOKS = [
    ("Genesis", "01", "Genesis"), ("Exodus", "02", "Exodus"), ("Leviticus", "03", "Leviticus"), ("Numbers", "04", "Numbers"),
    ("Deuteronomy", "05", "Deuteronomy"), ("Joshua", "06", "Joshua"), ("Judges", "07", "Judges"), ("Ruth", "08", "Ruth"),
    ("1 Samuel", "09", "1Samuel"), ("2 Samuel", "10", "2Samuel"), ("1 Kings", "11", "1Kings"), ("2 Kings", "12", "2Kings"),
    ("1 Chronicles", "13", "1Chronicles"), ("2 Chronicles", "14", "2Chronicles"), ("Ezra", "15", "Ezra"), ("Nehemiah", "16", "Nehemiah"),
    ("Esther", "17", "Esther"), ("Job", "18", "Job"), ("Psalms", "19", "Psalms"), ("Proverbs", "20", "Proverbs"),
    ("Ecclesiastes", "21", "Ecclesiastes"), ("Song of Solomon", "22", "SongofSolomon"), ("Isaiah", "23", "Isaiah"),
    ("Jeremiah", "24", "Jeremiah"), ("Lamentations", "25", "Lamentations"), ("Ezekiel", "26", "Ezekiel"), ("Daniel", "27", "Daniel"),
    ("Hosea", "28", "Hosea"), ("Joel", "29", "Joel"), ("Amos", "30", "Amos"), ("Obadiah", "31", "Obadiah"), ("Jonah", "32", "Jonah"),
    ("Micah", "33", "Micah"), ("Nahum", "34", "Nahum"), ("Habakkuk", "35", "Habakkuk"), ("Zephaniah", "36", "Zephaniah"),
    ("Haggai", "37", "Haggai"), ("Zechariah", "38", "Zechariah"), ("Malachi", "39", "Malachi"),
    ("Matthew", "40", "Matthew"), ("Mark", "41", "Mark"), ("Luke", "42", "Luke"), ("John", "43", "John"),
    ("Acts", "44", "Acts"), ("Romans", "45", "Romans"), ("1 Corinthians", "46", "1Corinthians"), ("2 Corinthians", "47", "2Corinthians"),
    ("Galatians", "48", "Galatians"), ("Ephesians", "49", "Ephesians"), ("Philippians", "50", "Philippians"), ("Colossians", "51", "Colossians"),
    ("1 Thessalonians", "52", "1Thessalonians"), ("2 Thessalonians", "53", "2Thessalonians"), ("1 Timothy", "54", "1Timothy"),
    ("2 Timothy", "55", "2Timothy"), ("Titus", "56", "Titus"), ("Philemon", "57", "Philemon"), ("Hebrews", "58", "Hebrews"),
    ("James", "59", "James"), ("1 Peter", "60", "1Peter"), ("2 Peter", "61", "2Peter"), ("1 John", "62", "1John"),
    ("2 John", "63", "2John"), ("3 John", "64", "3John"), ("Jude", "65", "Jude"), ("Revelation", "66", "Revelation"),
]

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

def fetch_book(book_name, num, github_filename):
    url = f"https://raw.githubusercontent.com/aruljohn/Bible-kjv/master/{github_filename}.json"
    for attempt in range(3):
        try:
            r = requests.get(url, timeout=30)
            if r.status_code == 200:
                data = r.json()
                verses = []
                for ch in data['chapters']:
                    ch_num = int(ch['chapter'])
                    for v in ch['verses']:
                        verses.append((ch_num, int(v['verse']), v['text']))
                return verses
        except Exception as e:
            if attempt < 2:
                time.sleep(2)
            else:
                print(f"  FAILED: {e}")
    return []

def main():
    env = load_env()
    url = env.get("SUPABASE_URL", "")
    anon_key = env.get("SUPABASE_ANON_KEY", "")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "")
    
    if not url or not anon_key:
        print("ERROR: Need SUPABASE_URL and SUPABASE_ANON_KEY in .env")
        sys.exit(1)
    
    # Use service role key if available, otherwise generate SQL file
    use_api = bool(service_key)
    api_key = service_key or anon_key
    
    if not use_api:
        print("No SUPABASE_SERVICE_ROLE_KEY in .env")
        print("Will generate SQL file for Dashboard paste.\n")
    
    headers = {
        "apikey": api_key,
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    
    # Get IDs
    r = requests.get(f"{url}/rest/v1/bible_translations?code=eq.kjv&select=id",
        headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}, timeout=10)
    kjv_id = r.json()[0]["id"]
    
    r = requests.get(f"{url}/rest/v1/bible_books?select=id,name",
        headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}, timeout=15)
    book_map = {b["name"]: b["id"] for b in r.json()}
    
    print(f"KJV ID: {kjv_id}")
    print(f"Books: {len(book_map)}")
    print()
    
    if use_api:
        # Insert via REST API
        total = 0
        failed = 0
        for i, (book_name, num) in enumerate(BOOKS, 1):
            book_id = book_map.get(book_name)
            if not book_id:
                print(f"[{i}/66] {book_name}: NOT IN DB")
                continue
            
            verses = fetch_book(book_name, num)
            if not verses:
                print(f"[{i}/66] {book_name}: FAILED")
                failed += 1
                continue
            
            batch = []
            for ch, verse, text in verses:
                batch.append({
                    "translation_id": kjv_id,
                    "book_id": book_id,
                    "chapter": ch,
                    "verse": verse,
                    "text": text,
                })
            
            for j in range(0, len(batch), 500):
                chunk = batch[j:j+500]
                r = requests.post(f"{url}/rest/v1/bible_verses", json=chunk, headers=headers, timeout=30)
                if r.status_code >= 400:
                    print(f"  INSERT ERROR: {r.status_code} {r.text[:200]}")
                    failed += len(chunk)
                else:
                    total += len(chunk)
            
            print(f"[{i}/66] {book_name}: {len(verses)} verses (total: {total})")
            time.sleep(0.5)
        
        print(f"\nDone! Inserted: {total}, Failed: {failed}")
    
    else:
        # Generate SQL file
        output = Path(__file__).parent.parent / "supabase" / "migrations" / "20260711_seed_kjjv_text.sql"
        
        with open(output, "w", encoding="utf-8") as f:
            f.write("-- KJV Bible text seed (~31,102 verses)\n")
            f.write("-- Paste into Supabase Dashboard SQL Editor and run.\n\n")
            
            total = 0
            for i, (book_name, num, github_name) in enumerate(BOOKS, 1):
                verses = fetch_book(book_name, num, github_name)
                if not verses:
                    print(f"[{i}/66] {book_name}: FAILED")
                    continue
                
                # Generate batched INSERT
                for j in range(0, len(verses), 100):
                    chunk = verses[j:j+100]
                    f.write(f"INSERT INTO bible_verses (translation_id, book_id, chapter, verse, text)\n")
                    f.write("SELECT t.id, b.id, v.chapter, v.verse, v.text\n")
                    f.write("FROM (VALUES\n")
                    
                    vals = []
                    for ch, verse, text in chunk:
                        safe = text.replace("'", "''").replace("\\", "\\\\")
                        vals.append(f"    ('{kjv_id}', '{book_map[book_name]}', {ch}, {verse}, E'{safe}')")
                    f.write(",\n".join(vals))
                    f.write("\n) AS v(chapter, verse, text)\n")
                    f.write("CROSS JOIN (SELECT id FROM bible_translations WHERE code = 'kjv') t\n")
                    f.write("CROSS JOIN (SELECT id FROM bible_books WHERE name = '")
                    f.write(book_name.replace("'", "''"))
                    f.write("') b\n")
                    f.write("ON CONFLICT DO NOTHING;\n\n")
                
                total += len(verses)
                print(f"[{i}/66] {book_name}: {len(verses)} verses (total: {total})")
                time.sleep(0.5)
        
        print(f"\nTotal: {total} verses")
        print(f"SQL file: {output}")
        print("Paste into Supabase Dashboard SQL Editor and run.")

if __name__ == "__main__":
    main()
