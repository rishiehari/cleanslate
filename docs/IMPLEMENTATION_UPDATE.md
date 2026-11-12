# Time-window implementation update

Supersedes an unverified draft that only calculated count limits while claiming a date filter.

The active implementation applies public PhotoKit creation-date predicates and a fetch limit in PhotoInventoryReader before resource enumeration. Suggested activity weeks and past-month/two-month scans are capped at 2,000 items. See implementation_summary.md and VALIDATION_LOG.md for actual evidence and pending device gates.
