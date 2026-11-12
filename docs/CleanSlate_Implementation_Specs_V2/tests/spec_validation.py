#!/usr/bin/env python3
"""Static lint for completeness of the CleanSlate Nxx agent handoff package.
Does not test iOS application code or validate algorithm correctness."""
from pathlib import Path
import re
import json
ROOT = Path(__file__).resolve().parents[1]
feature_files = sorted((ROOT / 'features').glob('N[0-9][0-9]-*.md'))
assert len(feature_files) == 10, f"Expected 10 features; found {len(feature_files)}"
required = [r'## .*iPhone', r'## .*iPad', r'```swift', r'```sql', r'```gherkin', r'(?i)rollback', r'(?i)privacy', r'(?i)test', r'(?i)edge', r'(?i)source']
ids = set()
summary = []
for path in feature_files:
    body = path.read_text()
    ident = path.name[:3]
    assert ident not in ids, f"Duplicate ID {ident}"
    ids.add(ident)
    assert body.startswith('# '), f"Missing title {path}"
    assert body.count('```') % 2 == 0, f"Unbalanced code fence {path}"
    for pattern in required:
        assert re.search(pattern, body, re.I), f"Missing {pattern} in {path.name}"
    assert body.count('Scenario:') >= 4, f"Need at least 4 Gherkin scenarios in {path.name}"
    assert len(body.split()) >= 1200, f"Feature too terse: {path.name}: {len(body.split())} words"
    assert 'http' in body, f"Need evidence links {path.name}"
    summary.append({'id':ident,'path':str(path.relative_to(ROOT)),'words':len(body.split()),'gherkin_scenarios':body.count('Scenario:')})
assert ids == {f'N{i:02d}' for i in range(1,11)}
shared = sorted((ROOT/'shared').glob('*.md'))
assert len(shared) >= 9
for path in shared:
    assert path.read_text().startswith('# ')
    assert path.read_text().count('```') % 2 == 0, f"Unbalanced fences: {path.name}"
summary.sort(key=lambda x:int(x['id'][1:]))
metadata={'name':'CleanSlate implementation specs V2','date':'2026-11-12','feature_count':len(feature_files),
          'feature_words':sum(x['words'] for x in summary),
          'shared_words':sum(len(x.read_text().split()) for x in shared),
          'gherkin_scenarios':sum(x['gherkin_scenarios'] for x in summary),
          'features':summary}
(ROOT/'manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps({k:v for k,v in metadata.items() if k!='features'},indent=2))
for x in summary: print(x['id'],x['words'],'words',x['gherkin_scenarios'],'scenarios')
print('Static documentation audit PASSED; no iOS build or product tests performed.')
