#!/usr/bin/env python3
"""Make consolidated Markdown and plain Gherkin copies; no app build/testing occurs."""
from pathlib import Path
import re, json
ROOT=Path(__file__).resolve().parents[1]
feature_order=['N05-protection-rules.md','N04-storage-goal-planner.md','N07-screenshot-intelligence.md','N06-mistake-finder.md','N01-moment-intelligence.md','N02-similar-video-finder.md','N03-compression-lab.md','N08-album-inbox.md','N09-rescue-gems.md','N10-local-taste.md']
shared_order=['00_REPOSITORY_BASELINE.md','01_ENGINEERING_INVARIANTS.md','02_DATA_AND_MIGRATION_STRATEGY.md','10_CROSS_FEATURE_ARCHITECTURE.md','03_IPHONE_EXPERIENCE.md','04_IPAD_EXPERIENCE.md','05_FIRST_SESSION_AND_ENGAGEMENT.md','06_TEST_AND_RELEASE_GATES.md','07_DEPENDENCIES_AND_ROADMAP.md','09_FEATURE_PARITY_MATRIX.md','08_COMPETITOR_EVIDENCE.md']
parts=["# CleanSlate — TOP 10 Premium-Parity Features: Full Agent-Ready Specification\n\n2026-11-12 | Native SwiftUI / PhotoKit / Vision / AVFoundation / SQLite | 100% free on-device by design\n\n**This is a proposed implementation specification; the new features are not implemented or device-validated.** Individual editable files are available in this same package.\n", ROOT.joinpath('README.md').read_text()]
for fname in shared_order:
  path=ROOT/'shared'/fname
  parts.append(f"\n\n---\n\n<!-- Source: shared/{fname} -->\n\n"+path.read_text())
for fname in feature_order:
  path=ROOT/'features'/fname
  parts.append(f"\n\n---\n\n<!-- Source: features/{fname} -->\n\n"+path.read_text())
parts.append('\n\n---\n\n# Implementation-agent handoff\n\n'+(ROOT/'agents'/'MASTER_AGENT_HANDOFF.md').read_text())
full='\n'.join(parts)
out=ROOT/'CLEANSLATE_TOP10_AGENT_READY_FULL_SPEC.md'
out.write_text(full)
gherkin=ROOT/'tests'/'gherkin'; gherkin.mkdir(exist_ok=True)
count=0
for name in feature_order:
 s=(ROOT/'features'/name).read_text()
 blocks=re.findall(r'```gherkin\n(.*?)```',s,re.S)
 fid=name[:3]
 code='\n\n'.join(x.strip() for x in blocks)
 assert 'Scenario:' in code, name
 (gherkin/f'{fid}.feature').write_text(f'Feature: {fid} - {s.splitlines()[0].removeprefix("# ")}\n\n'+code+'\n')
 count += code.count('Scenario:')
print('Created',out,'words:',len(full.split()), 'bytes:',len(full.encode('utf-8')))
print('Gherkin scenarios:',count, 'in 10 source .feature files (not executed)')
