# The findings format. Sourced by the Core's scripts; defines no side effects.
#
# A finding is one line: `file:line rule message`. file is relative to the project
# root and has no spaces, line is a number (1 when the finding is about the whole
# file), rule is one word, and message is free text.

FACTORY_FINDING_RE='^[^[:space:]]+:[0-9]+ [^[:space:]]+ .+$'

# factory_finding <file> <line> <rule> <message...>: print one finding.
factory_finding() {
	local file="$1" line="$2" rule="$3"
	shift 3
	printf '%s:%s %s %s\n' "$file" "$line" "$rule" "$*"
}

# factory_sort_findings: sort stdin byte-wise, the same on every machine and locale.
factory_sort_findings() {
	LC_ALL=C sort
}

# factory_check_findings <step> <file>: print each line of <file> that isn't a
# finding as a finding against the step's script. Blank lines are ignored.
# Exit 1 if there were any.
factory_check_findings() {
	local step="$1" file="$2" bad=0 line
	while IFS= read -r line || [ -n "$line" ]; do
		[ -z "$line" ] && continue
		if ! [[ $line =~ $FACTORY_FINDING_RE ]]; then
			factory_finding "tools/verify/$step" 1 finding-format "not a 'file:line rule message' line: $line"
			bad=1
		fi
	done < "$file"
	return "$bad"
}
