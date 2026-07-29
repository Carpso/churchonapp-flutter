"""Check which GitHub filenames differ from book names."""
import requests

# Test failed book names with different formats
test_books = [
    ("1 Samuel", "1%20Samuel"), ("2 Samuel", "2%20Samuel"),
    ("1 Kings", "1%20Kings"), ("2 Kings", "2%20Kings"),
    ("1 Chronicles", "1%20Chronicles"), ("2 Chronicles", "2%20Chronicles"),
    ("Song of Solomon", "Song%20of%20Solomon"),
    ("1 Corinthians", "1%20Corinthians"), ("2 Corinthians", "2%20Corinthians"),
    ("1 Thessalonians", "1%20Thessalonians"), ("2 Thessalonians", "2%20Thessalonians"),
    ("1 Timothy", "1%20Timothy"), ("2 Timothy", "2%20Timothy"),
    ("1 Peter", "1%20Peter"), ("2 Peter", "2%20Peter"),
    ("1 John", "1%20John"), ("2 John", "2%20John"), ("3 John", "3%20John"),
]

for name, encoded in test_books:
    # Try the URL-encoded version
    url = f"https://raw.githubusercontent.com/aruljohn/Bible-kjv/master/{encoded}.json"
    try:
        r = requests.head(url, timeout=10)
        status = r.status_code
    except:
        status = "error"
    print(f"  {name}: {status}")
