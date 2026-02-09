#!/bin/bash
# E2E Test: PromptyUI CSS Modernization (Phase 1)
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "PromptyUI CSS Modernization Tests"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running"
    exit 1
fi
log_pass "Server running"

# Test 1: Page loads with modernized CSS
log_info "TEST 1: Page loads"
agent-browser open "$BASE_URL"
TITLE=$(agent-browser get title 2>/dev/null)
[ "$TITLE" = "PromptyUI" ] && log_pass "Page loads" || log_fail "Page load: $TITLE"

# Test 2: Select a job to get blocks visible
log_info "TEST 2: Job selection for block tests"
agent-browser find text "hiring-templates" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Prompts" && log_pass "Job selected" || log_fail "Job not selected"

# Test 3: Block border is transparent by default (borderless blocks)
log_info "TEST 3: Borderless blocks - transparent default border"
BORDER=$(agent-browser eval 'const b = document.querySelector(".pu-block"); b ? getComputedStyle(b).borderColor : "none"' 2>/dev/null)
if echo "$BORDER" | grep -qi "transparent\|rgba(0, 0, 0, 0)"; then
    log_pass "Block border transparent by default"
else
    log_fail "Block border not transparent: $BORDER"
fi

# Test 4: Block spacing increased (margin-bottom: 12px)
log_info "TEST 4: Block spacing increase"
MARGIN=$(agent-browser eval 'const b = document.querySelector(".pu-block"); b ? getComputedStyle(b).marginBottom : "none"' 2>/dev/null)
if echo "$MARGIN" | grep -q "12px"; then
    log_pass "Block margin-bottom is 12px"
else
    log_fail "Block margin-bottom: $MARGIN (expected 12px)"
fi

# Test 5: Block header padding increased
log_info "TEST 5: Block header padding"
PADDING=$(agent-browser eval 'const h = document.querySelector(".pu-block-header"); h ? getComputedStyle(h).padding : "none"' 2>/dev/null)
if echo "$PADDING" | grep -q "12px.*16px\|12px 16px"; then
    log_pass "Block header padding is 12px 16px"
else
    log_fail "Block header padding: $PADDING (expected 12px 16px)"
fi

# Test 6: Block content padding increased
log_info "TEST 6: Block content padding"
PADDING=$(agent-browser eval 'const c = document.querySelector(".pu-block-content"); c ? getComputedStyle(c).padding : "none"' 2>/dev/null)
if echo "$PADDING" | grep -q "14px.*16px\|14px 16px"; then
    log_pass "Block content padding is 14px 16px"
else
    log_fail "Block content padding: $PADDING (expected 14px 16px)"
fi

# Test 7: Blocks container padding increased
log_info "TEST 7: Blocks container padding"
PADDING=$(agent-browser eval 'const c = document.querySelector(".pu-blocks-container"); c ? getComputedStyle(c).padding : "none"' 2>/dev/null)
if echo "$PADDING" | grep -q "20px"; then
    log_pass "Blocks container padding is 20px"
else
    log_fail "Blocks container padding: $PADDING (expected 20px)"
fi

# Test 8: Section headers use capitalize + font-weight 500
log_info "TEST 8: Section header reduced chrome"
TRANSFORM=$(agent-browser eval 'const t = document.querySelector(".pu-sidebar-title"); t ? getComputedStyle(t).textTransform : "none"' 2>/dev/null)
WEIGHT=$(agent-browser eval 'const t = document.querySelector(".pu-sidebar-title"); t ? getComputedStyle(t).fontWeight : "none"' 2>/dev/null)
FSIZE=$(agent-browser eval 'const t = document.querySelector(".pu-sidebar-title"); t ? getComputedStyle(t).fontSize : "none"' 2>/dev/null)
if echo "$TRANSFORM" | grep -qi "capitalize" && echo "$WEIGHT" | grep -q "500" && echo "$FSIZE" | grep -q "12px"; then
    log_pass "Sidebar title: capitalize, 500, 12px"
else
    log_fail "Sidebar title: transform=$TRANSFORM weight=$WEIGHT size=$FSIZE"
fi

# Test 9: Block entry animation keyframes exist
log_info "TEST 9: Block entry animation keyframes"
HAS_ANIM=$(agent-browser eval '
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.type === CSSRule.KEYFRAMES_RULE && rule.name === "pu-block-enter") {
                    found = true;
                    break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found
' 2>/dev/null)
echo "$HAS_ANIM" | grep -qi "true" && log_pass "pu-block-enter keyframes found" || log_fail "pu-block-enter keyframes missing"

# Test 10: Block exit animation keyframes exist
log_info "TEST 10: Block exit animation keyframes"
HAS_ANIM=$(agent-browser eval '
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.type === CSSRule.KEYFRAMES_RULE && rule.name === "pu-block-exit") {
                    found = true;
                    break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found
' 2>/dev/null)
echo "$HAS_ANIM" | grep -qi "true" && log_pass "pu-block-exit keyframes found" || log_fail "pu-block-exit keyframes missing"

# Test 11: Dropdown animation keyframes exist
log_info "TEST 11: Dropdown animation keyframes"
HAS_ANIM=$(agent-browser eval '
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.type === CSSRule.KEYFRAMES_RULE && rule.name === "pu-dropdown-in") {
                    found = true;
                    break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found
' 2>/dev/null)
echo "$HAS_ANIM" | grep -qi "true" && log_pass "pu-dropdown-in keyframes found" || log_fail "pu-dropdown-in keyframes missing"

# Test 12: Wildcard chip has transition property
log_info "TEST 12: Wildcard chip glow transition"
# Check the CSS rule exists even if no chip elements are on screen
HAS_RULE=$(agent-browser eval '
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText === ".pu-edit-wc-chip" && rule.style.transition) {
                    found = true;
                    break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found
' 2>/dev/null)
echo "$HAS_RULE" | grep -qi "true" && log_pass "Wildcard chip transition rule exists" || log_fail "Wildcard chip transition rule missing"

# Test 13: Preview mode still works
log_info "TEST 13: Preview mode navigation"
agent-browser find role button click --name "Preview" 2>/dev/null || \
    agent-browser find text "Preview" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Edit Mode" && log_pass "Preview mode works" || log_fail "Preview mode broken"

# Test 14: Back to edit mode
log_info "TEST 14: Return to edit mode"
agent-browser find role button click --name "Edit Mode" 2>/dev/null || \
    agent-browser find text "Edit Mode" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Preview" && log_pass "Edit mode works" || log_fail "Edit mode broken"

# Cleanup
agent-browser close 2>/dev/null

print_summary
exit $?
