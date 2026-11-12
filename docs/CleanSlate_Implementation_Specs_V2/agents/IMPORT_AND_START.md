# Import specification files into your local CleanSlate repository

**These commands are copy/paste suggestions; they were not executed against your Mac or repository.**

```bash
# Prerequisite: download and unzip CleanSlate_Implementation_Specs_V2.zip first.
cd ~/path/to/cleanslate
git status --short
git pull --ff-only origin main

git switch -c docs/next-feature-agent-specs
mkdir -p docs/next-features

# Adjust source directory to wherever you unzipped the artifact.
cp -R ~/Downloads/CleanSlate_Implementation_Specs_V2/{README.md,features,shared,agents,tests,manifest.json} docs/next-features/

python3 docs/next-features/tests/spec_validation.py

git add docs/next-features
git commit -m 'docs: add agent-ready specs for ten on-device premium parity features'
# Review this commit/PR before merging into main.
```

After reviewing the docs, start with N05 in a fresh feature branch. Pass `agents/MASTER_AGENT_HANDOFF.md` and `features/N05-protection-rules.md` to the coding agent together with the repository. The agent should confirm current HEAD, device gates and migration version, then write tests before code. Do not ask it to implement all ten simultaneously: the existing repo's F03 physical-device safety gate and active roadmap remain prerequisites.
