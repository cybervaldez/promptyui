#!/bin/bash
# ============================================================================
# E2E Test Suite: ext_text Wildcard Resolution
# ============================================================================
# Tests that ext-defined wildcards (e.g., seniority from hiring/roles.yaml)
# are properly merged into wildcard_lookup and resolved in:
#   1. ext_text entries containing __wildcard__ placeholders
#   2. after-children of ext_text blocks
#   3. Precedence: prompt wildcards override ext wildcards
#   4. pipeline_runner.create_run loads ext files
#
# Usage: ./tests/test_ext_wildcards.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
PYTHON="./venv/bin/python"

setup_cleanup

print_header "ext_text Wildcard Resolution"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if $PYTHON -c "import yaml" 2>/dev/null; then
    log_pass "Python available"
else
    log_fail "Python not available"
    exit 1
fi

# ============================================================================
# TEST 1: ext wildcards merged into wildcard_lookup (build_jobs)
# ============================================================================
echo ""
log_info "TEST 1: ext wildcards merged into wildcard_lookup for ext-wildcard-test"

# Run build_jobs for ext-wildcard-test and check that __seniority__ is resolved
T1_OUTPUT=$($PYTHON -c "
from src.jobs import build_jobs
from src.config import load_yaml
from pathlib import Path
import yaml

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
task_conf = yaml.safe_load(open(job_dir / 'jobs.yaml'))

# Load ext files (mirrors pipeline_runner fix)
global_conf = {'ext': []}
ext_dir = Path.cwd() / 'ext' / 'hiring'
if ext_dir.exists():
    for ef in sorted(ext_dir.glob('*.yaml')):
        ed = load_yaml(ef)
        if ed and 'id' in ed:
            ed['_ext'] = 'hiring'
            global_conf['ext'].append(ed)

jobs = build_jobs(task_conf, Path('/dev/null'), 0.1, ' ', global_conf,
                  composition_id=0, wildcards_max=2, ext_text_max=2)

# Filter to ext-wildcard-test
ext_jobs = [j for j in jobs if j['prompt'].get('id') == 'ext-wildcard-test']
for j in ext_jobs:
    text = j['prompt'].get('text', '')
    print(text)
" 2>/dev/null)

# ext_text entries should have seniority resolved (not literal __seniority__)
if echo "$T1_OUTPUT" | grep -q "__seniority__"; then
    log_fail "ext wildcard __seniority__ NOT resolved (still literal)"
    echo "    Output: $(echo "$T1_OUTPUT" | head -3)"
else
    if echo "$T1_OUTPUT" | grep -qi "Junior\|Mid-level\|Senior\|Staff\|Principal"; then
        log_pass "ext wildcard __seniority__ resolved in ext_text entries"
    else
        log_fail "ext wildcard resolved but no expected values found"
        echo "    Output: $(echo "$T1_OUTPUT" | head -3)"
    fi
fi

# After-children should also have seniority resolved
if echo "$T1_OUTPUT" | grep -q "Describe .* level expectations"; then
    log_pass "ext wildcard resolved in after-children"
else
    log_fail "After-children text not found"
    echo "    Output: $(echo "$T1_OUTPUT" | head -5)"
fi

# ============================================================================
# TEST 2: Prompt wildcard overrides ext wildcard (precedence)
# ============================================================================
echo ""
log_info "TEST 2: Prompt wildcard takes precedence over ext wildcard"

T2_OUTPUT=$($PYTHON -c "
from src.jobs import build_jobs
from src.config import load_yaml
from pathlib import Path
import yaml

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
task_conf = yaml.safe_load(open(job_dir / 'jobs.yaml'))

global_conf = {'ext': []}
ext_dir = Path.cwd() / 'ext' / 'hiring'
if ext_dir.exists():
    for ef in sorted(ext_dir.glob('*.yaml')):
        ed = load_yaml(ef)
        if ed and 'id' in ed:
            ed['_ext'] = 'hiring'
            global_conf['ext'].append(ed)

jobs = build_jobs(task_conf, Path('/dev/null'), 0.1, ' ', global_conf,
                  composition_id=0, wildcards_max=2, ext_text_max=2)

prec_jobs = [j for j in jobs if j['prompt'].get('id') == 'ext-precedence-test']
for j in prec_jobs:
    text = j['prompt'].get('text', '')
    print(text)
" 2>/dev/null)

# Should use L1/L2 (prompt values) NOT Junior/Mid-level (ext values)
if echo "$T2_OUTPUT" | grep -q "L1\|L2"; then
    log_pass "Prompt wildcard values (L1, L2) used — takes precedence"
else
    log_fail "Prompt wildcard values not found"
    echo "    Output: $(echo "$T2_OUTPUT" | head -3)"
fi

if echo "$T2_OUTPUT" | grep -q "Junior\|Mid-level"; then
    log_fail "Ext wildcard values leaked through (precedence broken)"
else
    log_pass "Ext wildcard values correctly overridden by prompt"
fi

# ============================================================================
# TEST 3: pipeline_runner.create_run loads ext files
# ============================================================================
echo ""
log_info "TEST 3: pipeline_runner.create_run loads ext files for hiring theme"

T3_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from pathlib import Path

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='ext-wildcard-test')
# If we got here without error, ext files loaded and jobs built
print(f'jobs_count={len(tree_jobs)}')
for j in tree_jobs:
    text = j['prompt'].get('text', '')
    print(text)
" 2>/dev/null)

if echo "$T3_OUTPUT" | grep -q "jobs_count="; then
    JOBS_COUNT=$(echo "$T3_OUTPUT" | grep "jobs_count=" | head -1 | sed 's/jobs_count=//')
    if [ "$JOBS_COUNT" -gt "0" ]; then
        log_pass "create_run produced $JOBS_COUNT jobs for ext-wildcard-test"
    else
        log_fail "create_run produced 0 jobs"
    fi
else
    log_fail "create_run failed to run"
    echo "    Output: $(echo "$T3_OUTPUT" | head -3)"
fi

# Verify seniority resolved via pipeline_runner path
if echo "$T3_OUTPUT" | grep -q "__seniority__"; then
    log_fail "pipeline_runner path: __seniority__ NOT resolved"
else
    log_pass "pipeline_runner path: ext wildcards resolved"
fi

# ============================================================================
# TEST 4: Wildcard inside ext_text entries (roles.yaml has __seniority__)
# ============================================================================
echo ""
log_info "TEST 4: Wildcards inside ext_text entries expand correctly"

T4_OUTPUT=$($PYTHON -c "
from src.jobs import build_text_variations
# Simulate ext_text entries with embedded wildcards
ext_texts = {'roles': ['__seniority__ Engineer', '__seniority__ Designer']}
wildcard_lookup = {'seniority': ['Junior', 'Senior']}

items = [{'ext_text': 'roles'}]
results = build_text_variations(items, ext_texts, ext_text_max=0, wildcards_max=0,
                                wildcard_lookup=wildcard_lookup)
for r in results:
    print(r[0])  # resolved text
" 2>/dev/null)

# Should produce 4 combinations: 2 roles × 2 seniority levels
LINE_COUNT=$(echo "$T4_OUTPUT" | grep -c ".")
if [ "$LINE_COUNT" -eq "4" ]; then
    log_pass "Cartesian expansion: 2 ext_text × 2 wildcard = 4 combinations"
else
    log_fail "Expected 4 combinations, got $LINE_COUNT"
    echo "    Output: $T4_OUTPUT"
fi

if echo "$T4_OUTPUT" | grep -q "Junior Engineer" && echo "$T4_OUTPUT" | grep -q "Senior Designer"; then
    log_pass "Wildcard values correctly substituted in ext_text entries"
else
    log_fail "Wildcard substitution in ext_text entries incorrect"
    echo "    Output: $T4_OUTPUT"
fi

# ============================================================================
# TEST 5: Regression — existing nested-blocks prompt still works
# ============================================================================
echo ""
log_info "TEST 5: Regression — existing nested-blocks prompt unaffected"

T5_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from pathlib import Path

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='nested-blocks')
print(f'jobs_count={len(tree_jobs)}')
for j in tree_jobs:
    text = j['prompt'].get('text', '')
    print(text)
" 2>/dev/null)

if echo "$T5_OUTPUT" | grep -q "jobs_count="; then
    JOBS_COUNT=$(echo "$T5_OUTPUT" | grep "jobs_count=" | head -1 | sed 's/jobs_count=//')
    if [ "$JOBS_COUNT" -gt "0" ]; then
        log_pass "nested-blocks produced $JOBS_COUNT jobs (regression OK)"
    else
        log_fail "nested-blocks produced 0 jobs"
    fi
else
    log_fail "nested-blocks failed"
fi

# Verify tone wildcard still resolves
if echo "$T5_OUTPUT" | grep -q "formal\|casual"; then
    log_pass "Inline wildcards still resolve in nested-blocks"
else
    log_fail "Inline wildcards not resolved in nested-blocks"
    echo "    Output: $(echo "$T5_OUTPUT" | head -3)"
fi

# ============================================================================
# TEST 6: Regression — email-writer prompt still works
# ============================================================================
echo ""
log_info "TEST 6: Regression — email-writer prompt unaffected"

T6_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from pathlib import Path

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='email-writer')
print(f'jobs_count={len(tree_jobs)}')
" 2>/dev/null)

if echo "$T6_OUTPUT" | grep -q "jobs_count="; then
    JOBS_COUNT=$(echo "$T6_OUTPUT" | grep "jobs_count=" | head -1 | sed 's/jobs_count=//')
    if [ "$JOBS_COUNT" -gt "0" ]; then
        log_pass "email-writer produced $JOBS_COUNT jobs (regression OK)"
    else
        log_fail "email-writer produced 0 jobs"
    fi
else
    log_fail "email-writer failed"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
log_info "SUMMARY"

print_summary
exit $?
