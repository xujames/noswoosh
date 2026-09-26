#!/bin/bash
# List the lines an upstream change adds that touch what noswoosh is trusted
# with -- it runs with Accessibility permission, so it could read or fake input
# -- as Markdown for the sync pull request. A starting point for review, not a
# verdict: a line can be harmless, and a harmful one can dodge every pattern.
#
#   upstream-flags.sh <base> <head>     changes on <head> since it left <base>
set -euo pipefail

base=$1 head=$2
max=40  # lines shown per category

# Category|extended regex, matched against each added line of code.
categories=(
    'Network|URLSession|NSURL|URLRequest|CFNetwork|CFSocket|socket\(|NWConnection|nw_connection|https?://'
    'Runs other programs|Process\(|NSTask|posix_spawn|execv|system\(|popen|launchctl|osascript|NSAppleScript|/usr/bin/|/bin/(ba|z)?sh|curl|wget'
    'Sees, posts or blocks input|tapCreate|eventsOfInterest|CGEventMask|kCGEventKey|keyDown|keyUp|flagsChanged|addGlobalMonitor|RegisterEventHotKey|IOHIDManager|AXUIElement|\.post\(tap'
    'Writes files or settings|FileManager|write\(to|fopen|createFile|CFPreferencesSet|UserDefaults|defaults (write|delete)|LaunchAgents|killall|rm -'
    'Secrets, screen, clipboard|SecItem|Keychain|security |NSPasteboard|CGWindowListCreateImage|ScreenCaptureKit|CGDisplayStream'
    'Private APIs|dlopen|dlsym|@_silgen_name|SLS[A-Z]|CGS[A-Z]'
)

# Every added line of code as path:line:text. Docs and images are skipped.
added=$(git diff -U0 --no-color --no-ext-diff "$base...$head" -- . ':(exclude)*.md' ':(exclude)assets/*' |
    awk '/^\+\+\+ / { file = substr($0, 7); next }
         /^@@/      { split($3, a, ","); line = substr(a[1], 2); next }
         /^\+/      { printf "%s:%d:%s\n", file, line++, substr($0, 2); next }')

found=0
for entry in "${categories[@]}"; do
    name=${entry%%|*} pattern=${entry#*|}
    # Match the text only, never the path:line prefix. grep's 1 is no match;
    # anything else, a bad pattern included, stops the script rather than
    # passing for a clean change.
    hits=$(printf '%s\n' "$added" | grep -E -- "^[^:]*:[0-9]+:.*($pattern)") || [ $? -eq 1 ]
    [ -n "$hits" ] || continue
    found=1
    count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    printf '### %s (%s)\n\n```\n' "$name" "$count"
    printf '%s\n' "$hits" | head -n "$max" | cut -c1-200
    printf '```\n'
    [ "$count" -le "$max" ] || printf '\n...and %s more.\n' "$((count - max))"
    printf '\n'
done

# The build and CI themselves: changes here run on GitHub's machines, or on
# yours when you build.
build=$(git diff --name-only "$base...$head" -- .github scripts)
if [ -n "$build" ]; then
    found=1
    printf '### Build and CI files\n\n'
    printf -- '- `%s`\n' $build
    printf '\n'
fi

[ "$found" = 1 ] || printf 'No added line matches a flagged pattern, and no build or CI file changed.\n'
