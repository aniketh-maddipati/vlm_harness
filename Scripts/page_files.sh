# The design page's file names: one place for the scripts and CI. SetsSchemeHandler.pageFiles and
# SetsPageBytesTests repeat them for the app. A handoff that renames a file shows up in
# sets_sync_design.sh step 1; update the names here, there and in the scenarios' "page".
# Edit is its own page, mounted inside Sets by support.js (<dc-import name="Lumina Edit v21">).
PAGE="Lumina Sets v8.dc.html"
EDIT_PAGE="Lumina Edit v21.dc.html"
CORE="lumina-core-v4.js"
CORE_TEST="lumina-core-v4.test.mjs"
PAGE_FILES=("$PAGE" "$EDIT_PAGE" support.js "$CORE" lumina-v4-data.js lumina-measure.js lumina-selftest.js)
