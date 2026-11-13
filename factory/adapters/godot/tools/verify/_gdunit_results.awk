# Turns gdUnit4's JUnit report (results.xml) into `<suite file>\t<test>\t<status>`
# lines, one per testcase, for the test step. Run with gawk or any POSIX awk:
#   awk -f _gdunit_results.awk results.xml
#
# The suite file is <package>/<suite name>.gd. A parameterized test's cases
# (`test_x:0 (1)`) keep the bare function name; the test step merges them.
# A testcase's status comes from its first child element:
#   <failure type="FAILURE">  FAILURE (a failed assertion)
#   <failure> of another type, or <error>  ERROR (a crash, an abort, a timeout)
#   <skipped>                 SKIP
#   none                      PASS
# Failure messages (CDATA) are skipped, so their text can't be read as elements.

function attr(name,    s) {
	if (!match($0, " " name "=\"[^\"]*\"")) return ""
	s = substr($0, RSTART + length(name) + 3, RLENGTH - length(name) - 4)
	gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "'", s); gsub(/&amp;/, "\\&", s)
	return s
}
function emit() {
	if (test != "") print file "\t" test "\t" status
	test = ""
}
{ sub(/\r$/, "") }
cdata { if (index($0, "]]>")) cdata = 0; next }
/<!\[CDATA\[/ { if (!index($0, "]]>")) cdata = 1; next }
/<testsuite / { emit(); file = attr("package") "/" attr("name") ".gd"; next }
/<testcase / {
	emit()
	test = attr("name")
	sub(/[^A-Za-z0-9_].*$/, "", test)
	status = "PASS"
	if ($0 ~ /\/>[ \t]*$/) emit()
	next
}
/<\/testcase>/ { emit(); next }
test != "" && status == "PASS" && /<failure / { status = (attr("type") == "FAILURE") ? "FAILURE" : "ERROR"; next }
test != "" && status == "PASS" && /<error / { status = "ERROR"; next }
test != "" && status == "PASS" && /<skipped/ { status = "SKIP"; next }
END { emit() }
