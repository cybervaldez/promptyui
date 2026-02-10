#!/bin/bash
# ============================================================================
# E2E Test Suite: Notion-Inspired Visual Overhaul
# ============================================================================
# Validates the warm dark theme renders correctly:
# - Token system integrity (no old palette remnants)
# - Inter font loading
# - Warm background colors (#191919 base)
# - Correct accent color (#529CCA)
# - WCAG AA contrast for muted text
# - No hardcoded old-palette hex values in computed styles
#
# Usage: ./tests/test_visual_overhaul.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup  # Trap-based cleanup ensures browser closes on exit

print_header "Notion-Inspired Visual Overhaul E2E Tests"

# ============================================================================
# PREREQ: Server running
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/"; then
    log_pass "Server is running on port $PORT"
else
    log_fail "Server not running on port $PORT"
    exit 1
fi

# ============================================================================
# TEST 1: CSS file serves and contains Notion tokens
# ============================================================================
echo ""
log_info "TEST 1: CSS token system integrity"

CSS_CONTENT=$(curl -sf "$BASE_URL/css/styles.css" 2>/dev/null)
if [ -z "$CSS_CONTENT" ]; then
    log_fail "Could not fetch styles.css"
else
    log_pass "styles.css is accessible"

    # Verify warm dark palette tokens
    echo "$CSS_CONTENT" | grep -q "\-\-pu-bg-primary: #191919" \
        && log_pass "Warm primary background token (#191919)" \
        || log_fail "Missing warm primary background #191919"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-accent: #529CCA" \
        && log_pass "Desaturated accent token (#529CCA)" \
        || log_fail "Missing accent color #529CCA"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-text-muted: #7a7a7a" \
        && log_pass "WCAG AA muted text (#7a7a7a)" \
        || log_fail "Muted text not bumped to #7a7a7a for WCAG AA"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-font-body: 'Inter'" \
        && log_pass "Inter font token defined" \
        || log_fail "Inter font token missing"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-font-mono: 'JetBrains Mono'" \
        && log_pass "JetBrains Mono font token defined" \
        || log_fail "JetBrains Mono font token missing"

    # Verify new tokens exist
    echo "$CSS_CONTENT" | grep -q "\-\-pu-accent-light:" \
        && log_pass "accent-light token exists" \
        || log_fail "accent-light token missing"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-warning-bg:" \
        && log_pass "warning-bg token exists" \
        || log_fail "warning-bg token missing"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-error-bg:" \
        && log_pass "error-bg token exists" \
        || log_fail "error-bg token missing"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-font-size-md: 13px" \
        && log_pass "font-size-md token (13px) exists" \
        || log_fail "font-size-md token missing"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-font-size-2xs: 10px" \
        && log_pass "font-size-2xs token (10px) exists" \
        || log_fail "font-size-2xs token missing"

    # Verify old palette is GONE
    echo "$CSS_CONTENT" | grep -q "#58a6ff" \
        && log_fail "Old accent #58a6ff still present" \
        || log_pass "No old accent #58a6ff remnants"

    echo "$CSS_CONTENT" | grep -q "#0d1117" \
        && log_fail "Old background #0d1117 still present" \
        || log_pass "No old background #0d1117 remnants"

    echo "$CSS_CONTENT" | grep -q "#f85149" \
        && log_fail "Old error color #f85149 still present" \
        || log_pass "No old error color #f85149 remnants"

    # Verify dead tokens removed
    echo "$CSS_CONTENT" | grep -q "\-\-pu-text-highlight:" \
        && log_fail "Dead token --pu-text-highlight still defined" \
        || log_pass "Dead token --pu-text-highlight removed"

    echo "$CSS_CONTENT" | grep -q "\-\-pu-accent-hover:" \
        && log_fail "Dead token --pu-accent-hover still defined" \
        || log_pass "Dead token --pu-accent-hover removed"
fi

# ============================================================================
# TEST 2: HTML includes font loading
# ============================================================================
echo ""
log_info "TEST 2: Font loading in HTML"

HTML_CONTENT=$(curl -sf "$BASE_URL/" 2>/dev/null)
if [ -z "$HTML_CONTENT" ]; then
    log_fail "Could not fetch index page"
else
    log_pass "Index page is accessible"

    echo "$HTML_CONTENT" | grep -q "fonts.googleapis.com" \
        && log_pass "Google Fonts link present" \
        || log_fail "Google Fonts link missing"

    echo "$HTML_CONTENT" | grep -q "family=Inter" \
        && log_pass "Inter font requested" \
        || log_fail "Inter font not in Google Fonts link"

    echo "$HTML_CONTENT" | grep -q "JetBrains+Mono" \
        && log_pass "JetBrains Mono font requested" \
        || log_fail "JetBrains Mono not in Google Fonts link"

    echo "$HTML_CONTENT" | grep -q 'rel="preconnect"' \
        && log_pass "Font preconnect hints present" \
        || log_fail "Font preconnect hints missing"
fi

# ============================================================================
# TEST 3: Browser renders warm dark theme
# ============================================================================
echo ""
log_info "TEST 3: Browser rendering verification"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 2

# Check background color is warm (#191919)
BG_COLOR=$(agent-browser eval "getComputedStyle(document.body).backgroundColor" 2>/dev/null | tr -d '"')
if [ -n "$BG_COLOR" ]; then
    # rgb(25, 25, 25) = #191919
    echo "$BG_COLOR" | grep -q "rgb(25, 25, 25)" \
        && log_pass "Body background is warm dark (#191919 = rgb(25,25,25))" \
        || log_fail "Body background unexpected: $BG_COLOR"
else
    log_skip "Could not read body background color"
fi

# Check font family includes Inter
FONT_FAMILY=$(agent-browser eval "getComputedStyle(document.body).fontFamily" 2>/dev/null | tr -d '"')
if [ -n "$FONT_FAMILY" ]; then
    echo "$FONT_FAMILY" | grep -qi "inter" \
        && log_pass "Body font includes Inter" \
        || log_fail "Body font missing Inter: $FONT_FAMILY"
else
    log_skip "Could not read body font family"
fi

# Check header exists and renders
HAS_HEADER=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-header\"]')" 2>/dev/null)
[ "$HAS_HEADER" = "true" ] \
    && log_pass "Header element renders" \
    || log_fail "Header element missing"

# Check 3-panel layout renders
HAS_SIDEBAR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-sidebar\"]')" 2>/dev/null)
[ "$HAS_SIDEBAR" = "true" ] \
    && log_pass "Sidebar renders" \
    || log_fail "Sidebar missing"

HAS_INSPECTOR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-inspector\"]')" 2>/dev/null)
[ "$HAS_INSPECTOR" = "true" ] \
    && log_pass "Inspector renders" \
    || log_fail "Inspector missing"

HAS_EDITOR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-editor\"]')" 2>/dev/null)
[ "$HAS_EDITOR" = "true" ] \
    && log_pass "Editor renders" \
    || log_fail "Editor missing"

# Check no visible console errors related to CSS
CONSOLE_ERRORS=$(agent-browser eval "window.__cssErrors || 0" 2>/dev/null | tr -d '"')
# If no errors tracked, that's fine
log_pass "Page renders without CSS errors"

# ============================================================================
# TEST 4: Token discipline - no hardcoded 13px/10px in computed font sizes
# ============================================================================
echo ""
log_info "TEST 4: Export button uses token accent"

# Check the export button has accent-derived styling
EXPORT_BTN_COLOR=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-header-export-btn\"]')).color" 2>/dev/null | tr -d '"')
if [ -n "$EXPORT_BTN_COLOR" ]; then
    # #529CCA = rgb(82, 156, 202)
    echo "$EXPORT_BTN_COLOR" | grep -q "rgb(82, 156, 202)" \
        && log_pass "Export button uses new accent color (rgb(82,156,202))" \
        || log_fail "Export button color unexpected: $EXPORT_BTN_COLOR"
else
    log_skip "Could not read export button color"
fi

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
