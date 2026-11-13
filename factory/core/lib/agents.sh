# The factory's section of AGENTS.md. Sourced by agents.sh and adopt.sh; defines no
# side effects.
#
# The section is the lines from FACTORY_AGENTS_BEGIN to FACTORY_AGENTS_END, both
# included, holding templates/agents-section.md. It is generated: the template is
# the source, and the rest of AGENTS.md is the project's own.

# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_AGENTS_FILE="AGENTS.md"
FACTORY_AGENTS_BEGIN="<!-- factory:begin (generated from factory/core/templates/agents-section.md; edit that, then run bash factory/core/agents.sh generate) -->"
FACTORY_AGENTS_END="<!-- factory:end -->"

# factory_agents_markers <file>: true when the file holds the begin marker once,
# then the end marker once, or neither marker; false otherwise.
factory_agents_markers() {
	tr -d '\r' < "$1" | awk -v b="$FACTORY_AGENTS_BEGIN" -v e="$FACTORY_AGENTS_END" '
		$0 == b { nb++; if (ne) bad = 1 }
		$0 == e { ne++; if (!nb) bad = 1 }
		END { exit (bad || nb > 1 || ne > 1 || nb != ne) }
	'
}

# factory_agents_render <core> <file>: print the file with the section replaced by
# the template's, or appended (after a blank line) when it has none. A missing file
# becomes a heading and the section. False when the markers are broken
# (factory_agents_markers).
factory_agents_render() {
	local core="$1" file="$2"
	if [ ! -f "$file" ]; then
		printf '# AGENTS.md\n\n%s\n' "$FACTORY_AGENTS_BEGIN"
		tr -d '\r' < "$core/templates/agents-section.md"
		printf '%s\n' "$FACTORY_AGENTS_END"
		return 0
	fi
	factory_agents_markers "$file" || return 1
	tr -d '\r' < "$file" | awk -v b="$FACTORY_AGENTS_BEGIN" -v e="$FACTORY_AGENTS_END" -v tpl="$core/templates/agents-section.md" '
		function section(  line) {
			print b
			while ((getline line < tpl) > 0) { sub(/\r$/, "", line); print line }
			print e
			done = 1
		}
		$0 == b { section(); skip = 1; next }
		skip && $0 == e { skip = 0; next }
		skip { next }
		{ print; last = $0; n++ }
		END {
			if (!done) {
				if (n && last != "") print ""
				section()
			}
		}
	'
}
