"""Print EXTRACTED_URL / EXTRACTED_KEY from the deployed PWA's public JS.

The Next.js build inlines NEXT_PUBLIC_SUPABASE_URL and the anon key into its
client chunks. Both are public by design (RLS guards the data). Used by CI only
when the SUPABASE_URL / SUPABASE_ANON_KEY secrets are not set.
"""

import base64
import json
import re
import sys
import urllib.request

base = sys.argv[1].rstrip('/')


def get(url: str) -> str:
    req = urllib.request.Request(url, headers={'User-Agent': 'kharjook-ci'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', 'replace')


html = get(base + '/login')
chunks = sorted(set(re.findall(r'/_next/static/[^"\'\s]+?\.js', html)))
url = key = None
for c in chunks:
    try:
        js = get(base + c)
    except Exception:
        continue
    if not url:
        m = re.search(r'https://[a-z0-9]{10,}\.supabase\.co', js)
        if m:
            url = m.group(0)
    if not key:
        for jwt in re.findall(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', js):
            try:
                payload = jwt.split('.')[1]
                payload += '=' * (-len(payload) % 4)
                if json.loads(base64.urlsafe_b64decode(payload)).get('role') == 'anon':
                    key = jwt
                    break
            except Exception:
                pass
        if not key:
            m = re.search(r'sb_publishable_[A-Za-z0-9_-]+', js)
            if m:
                key = m.group(0)
    if url and key:
        break

if url and key:
    print(f'EXTRACTED_URL={url}')
    print(f'EXTRACTED_KEY={key}')
