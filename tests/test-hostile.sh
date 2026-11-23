#!/bin/bash
# Names, slugs, ids and dates come from the API, and anybody who can write in a world can choose them.
# This test runs the backups against a fake API that answers with names made to escape their folder
# (../../x, .., a backslash path, a path as the id, a path as the date, a name of 400 characters)
# and checks that every file lands in its own folder, and that nothing is written anywhere else.
# Run it from anywhere:  ./tests/test-hostile.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BASE="$OUT/testworld"

rm -rf "$OUT"
mkdir -p "$OUT"
python3 tests/mock_wa_api.py --port "$PORT" --quiet --data tests/fixtures-hostile.json &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null' EXIT
sleep 1

fail=0
check() {   # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 = $3"
    else
        echo "  FAIL  $1: expected $2, got $3"
        fail=1
    fi
}
count() { find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l; }

echo "--- the backups against the hostile fake API --------------------"
misc=$(python3 backup-misc.py --settings tests/settings-test.cfg --type secrets --type categories 2>&1)
articles=$(python3 backup-articles.py --settings tests/settings-test.cfg 2>&1)
echo "$articles" | grep -E "WARNING|not saved"

echo "--- nothing outside the folders of the test ----------------------"
check "the world folder has only the expected entries" "all_articles.json articles categories secrets" "$(ls "$BASE" | tr '\n' ' ' | sed 's/ *$//')"
check "no file with 'escape' in its name outside secrets/ and articles/" 0 "$(find tests "$OUT" -name '*escape*' -not -path "$BASE/secrets/*" -not -path "$BASE/articles/*" -not -name 'fixtures-hostile.json' -not -name 'test-hostile.sh' 2>/dev/null | wc -l)"
check "the folder above the world folder has only the world" "testworld" "$(ls "$OUT" | tr '\n' ' ' | sed 's/ *$//')"
check "every file is directly in its folder (no sub-folders in secrets, categories, articles)" 0 "$(find "$BASE/secrets" "$BASE/categories" "$BASE/articles" -mindepth 1 -type d | wc -l)"
check "no file name has a path separator or is hidden by a leading dot" 0 "$(find "$BASE" -type f \( -name '.*' -o -name '*\\*' \) | wc -l)"
check "the longest file name is below 255 bytes" 1 "$(python3 -c "
import os, sys
print(1 if max(len(n.encode()) for _, _, fs in os.walk('$BASE') for n in fs) < 255 else 0)")"

echo "--- the files that must exist, with their cleaned names ---------"
check "a path as the title: slashes and leading dots are gone, nothing is hidden" 1 "$(count "$BASE/secrets" 'escape-secret_s1111111_*.json')"
check ".. as the title and a path as the date: named by the id, dated by the run" 1 "$(count "$BASE/secrets" 's2222222_20*.json')"
check "a slash in the middle of the title (the real case): nothing is cut" 1 "$(count "$BASE/secrets" 'bow (-baʊ-) - front part of the ship_s3333333_*.json')"
check "a slash with spaces" 1 "$(count "$BASE/secrets" 'Action - Feat_s4444444_*.json')"
check "backslashes" 1 "$(count "$BASE/secrets" 'a-b-..-..-c_s5555555_*.json')"
check "a path as the id: the id part of the name has no path in it" 1 "$(count "$BASE/secrets" 'Hostile id_escape-i_*.json')"
check "a name of 400 characters is cut" 1 "$(count "$BASE/secrets" 'xxxxxxxxxx*_s7777777_*.json')"
check "the characters \" ' / \\ ? % together: quotes and ? gone, / and \\ became -, ' % [ ] stay" 1 "$(count "$BASE/secrets" "say hi it's 100% ok \[x\] yes-no-maybe_s8888888_*.json")"
check "invisible characters and the right-to-left override are gone" 1 "$(count "$BASE/secrets" 'evilgpj.exe_s9999999_*.json')"
check "all 13 secrets are saved" 13 "$(find "$BASE/secrets" -maxdepth 1 -type f ! -name 'all_*' | wc -l)"
# text that a shell would run (backticks, $( ), ; && ||) is only text for Python: it is saved as it is, and nothing runs
check "names with backticks, \$( ), ; && || run nothing (no PWNED file anywhere)" 0 "$(find . -maxdepth 4 -name 'PWNED*' -not -path './.git/*' 2>/dev/null | wc -l)"
check "a name with backticks is saved as plain text" 1 "$(count "$BASE/secrets" '*touch tests-out-PWNED-backtick*_s1010101_*.json')"
check "a name with \$( ) is saved as plain text" 1 "$(count "$BASE/secrets" '*touch tests-out-PWNED-dollar*_s1111112_*.json')"
check "a name with ; is saved as plain text" 1 "$(count "$BASE/secrets" 'x; touch tests-out-PWNED-semicolon_s1212123_*.json')"
check "a name with && and || is saved as plain text (the | is removed as before)" 1 "$(count "$BASE/secrets" 'y && touch tests-out-PWNED-and  touch tests-out-PWNED-or_s1313134_*.json')"
check ".. as the title of a category: named by the id" 1 "$(count "$BASE/categories" 'c1111111_*.json')"
check ". as the title of a category: named by the id" 1 "$(count "$BASE/categories" 'c2222222_*.json')"
check "a path as the slug of an article" 1 "$(count "$BASE/articles" 'escape-article_2026-03-01_100000.json')"
check "a normal article" 1 "$(count "$BASE/articles" 'normal-article_2026-03-01_100000.json')"
check "an article with .. as the slug is not saved" 1 "$(echo "$articles" | grep -c 'article a3333333-0000-0000-0000-000000000003 is not saved')"
check "an article with a path as the date is not saved" 1 "$(echo "$articles" | grep -c 'article a4444444-0000-0000-0000-000000000004 is not saved')"
check "only the two good articles are files" 2 "$(count "$BASE/articles" '*.json' | tr -d ' ')"
check "the run says how many were not saved" 1 "$(echo "$articles" | grep -c '2 articles were not saved')"

echo "--- the same again: names with [ ] ' % must be found again ------"
files_before=$(find "$BASE" -type f | wc -l)
again=$(python3 backup-misc.py --settings tests/settings-test.cfg --type secrets --type categories --full 2>&1 | grep -o 'Wrote [0-9]* files')
check "a run that reads and compares everything writes nothing" "Wrote 0 files" "$again"
check "no file was added" "$files_before" "$(find "$BASE" -type f | wc -l)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
