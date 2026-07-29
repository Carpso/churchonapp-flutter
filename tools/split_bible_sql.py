"""Split the large KJV SQL file into smaller batch files for Dashboard upload."""
from pathlib import Path

SQL_FILE = Path(__file__).parent.parent / "supabase" / "migrations" / "20260711_seed_kjjv_text.sql"
OUTPUT_DIR = Path(__file__).parent.parent / "supabase" / "migrations" / "kjv_batches"

def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    
    content = SQL_FILE.read_text(encoding="utf-8")
    
    # Split by INSERT statements
    blocks = []
    current = []
    for line in content.splitlines(keepends=True):
        if line.startswith("INSERT INTO") and current:
            blocks.append("".join(current))
            current = []
        current.append(line)
    if current:
        blocks.append("".join(current))
    
    print(f"Total INSERT blocks: {len(blocks)}")
    
    # Group into batches of 50 blocks (~5000 verses each)
    BATCH_SIZE = 25
    batch_num = 1
    for i in range(0, len(blocks), BATCH_SIZE):
        batch = blocks[i:i+BATCH_SIZE]
        out_file = OUTPUT_DIR / f"batch_{batch_num:02d}.sql"
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(f"-- KJV batch {batch_num} (blocks {i+1}-{min(i+BATCH_SIZE, len(blocks))} of {len(blocks)})\n")
            f.write("-- Run this in Supabase Dashboard SQL Editor\n\n")
            f.write("".join(batch))
        
        size_kb = out_file.stat().st_size / 1024
        print(f"  batch_{batch_num:02d}.sql: {size_kb:.0f} KB ({len(batch)} blocks)")
        batch_num += 1
    
    print(f"\n{batch_num-1} batch files in {OUTPUT_DIR}")
    print("Run them in order: batch_01.sql, batch_02.sql, etc.")

if __name__ == "__main__":
    main()
