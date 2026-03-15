#!/usr/bin/env bash
# update-readme.sh — Parses gh oss summary JSON and updates README.md
# between <!-- oss-start --> and <!-- oss-end --> markers.
# No-ops if there is no recent activity.

set -euo pipefail

README="${1:-README.md}"
SINCE="${2:-30d}"

# Ensure gh-oss extension is available
if ! gh extension list 2>/dev/null | grep -q "oss"; then
  echo "Installing gh-oss extension..."
  gh extension install maxbeizer/gh-oss || {
    echo "⚠️  Failed to install gh-oss. Skipping README update."
    exit 0
  }
fi

# Fetch recent activity
echo "Fetching OSS activity (since ${SINCE})..."
SUMMARY_JSON=$(gh oss summary --since "$SINCE" --format json 2>/dev/null || echo "[]")

# Check for empty results — no-op if nothing recent
if [ "$SUMMARY_JSON" = "[]" ] || [ -z "$SUMMARY_JSON" ]; then
  echo "No recent OSS activity found. Nothing to update."
  exit 0
fi

# Build markdown from JSON
# Expected JSON shape: [{"name": "repo", "description": "...", "url": "...", "pushedAt": "...", "activityType": "..."}]
MARKDOWN=$(echo "$SUMMARY_JSON" | python3 -c "
import json, sys
from datetime import datetime

repos = json.load(sys.stdin)
if not repos:
    sys.exit(0)

# Separate gh extensions from other repos
extensions = [r for r in repos if r.get('name', '').startswith('gh-')]
others = [r for r in repos if not r.get('name', '').startswith('gh-')]

lines = []
lines.append('### what i\'ve been building lately')
lines.append('')

if extensions:
    lines.append('**\`gh\` CLI extensions** — I\'ve been building tools that live where I already work.')
    lines.append('')
    lines.append('\`\`\`')
    for r in sorted(extensions, key=lambda x: x['name']):
        desc = r.get('description', '') or ''
        # Truncate long descriptions for the code block
        if len(desc) > 65:
            desc = desc[:62] + '...'
        lines.append(f\"  {r['name']}  {desc}\")
    lines.append('\`\`\`')
    lines.append('')
    for r in sorted(extensions, key=lambda x: x['name']):
        desc = r.get('description', '') or ''
        url = r.get('url', f\"https://github.com/maxbeizer/{r['name']}\")
        lines.append(f\"- [\`{r['name']}\`]({url}) — {desc}\")
    lines.append('')

if others:
    lines.append('**other recent work**')
    lines.append('')
    for r in sorted(others, key=lambda x: x['name']):
        desc = r.get('description', '') or ''
        url = r.get('url', f\"https://github.com/maxbeizer/{r['name']}\")
        lines.append(f\"- [\`{r['name']}\`]({url}) — {desc}\")
    lines.append('')

print('\n'.join(lines))
")

if [ -z "$MARKDOWN" ]; then
  echo "No markdown generated. Nothing to update."
  exit 0
fi

# Replace content between markers in README
python3 -c "
import sys

readme_path = sys.argv[1]
new_content = sys.argv[2]

with open(readme_path, 'r') as f:
    content = f.read()

start_marker = '<!-- oss-start -->'
end_marker = '<!-- oss-end -->'

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print('⚠️  Could not find oss markers in README. Skipping.')
    sys.exit(0)

# Build updated content
from datetime import datetime
month_year = datetime.utcnow().strftime('%B %Y')

before = content[:start_idx + len(start_marker)]
after = content[end_idx:]

updated = before + '\n' + new_content + '\n---\n\n' + after

# Also update the auto-updated timestamp
import re
updated = re.sub(
    r'<sub>auto-updated .*?</sub>',
    f'<sub>auto-updated {month_year}</sub>',
    updated
)

with open(readme_path, 'w') as f:
    f.write(updated)

print(f'✅ README updated with recent OSS activity ({month_year})')
" "$README" "$MARKDOWN"
