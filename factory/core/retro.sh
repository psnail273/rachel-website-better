#!/usr/bin/env bash
# The retro's numbers: total the factory-stats lines of a Feature's issues
# (factory-run's retro.md). It reads text on stdin, such as every comment of the
# Feature's closed issues fetched with the tracker's own commands, so it knows no
# tracker and needs no checkout:
#   bash factory/core/retro.sh < comments.txt
#
# A stats line is the one land.sh prints for the close comment, or state.sh
# stats for a parked issue (lib/run.sh, factory_stats_line). It counts anywhere
# in a line, so Markdown quoting, bold or code marks around it don't matter:
#   factory-stats: issue=<n> lane=<lane> rounds-red=<n> ... escalations=<n> self-ruled=<n> minutes=<n> ...
# self-ruled counts the Driver's calls (lib/run.sh); retro.md lists each one beside it.
# The minutes fields total like the counts. A line from an issue started before
# start.sh recorded the time has none, so a minutes total covers only the issues
# whose rows show minutes. So with the gate's counts (gate-runs, caught-<step>,
# seconds-<step>): only a line with gate-runs recorded them, and their totals
# cover those issues alone; a line without (an issue landed before verify.sh
# counted, or one that counted no gate run) is "not recorded", never 0.
# An issue's last line counts, so give each issue's comments oldest first: a
# close comment posted twice counts once. A line that doesn't parse, or names a
# field twice, is named on stderr and skipped.
#
# stdout:
#   retro: <n> issues
#   lane <lane>: <n>                one line per lane, sorted
#   gate counts: <n> of <m> issues  how many issues recorded the gate's counts
#   <count>: <total>                one line per count, in the stats line's order,
#                                   then one per minutes field
#   issue <n>: <count>=<value> ...  each issue's counts and minutes fields that aren't 0,
#                                   and its minutes whenever it has them, by number
# Exit codes: 0 done, 1 no stats line found, 2 usage.
set -u

if [ "$#" -ne 0 ]; then
	echo "usage: bash factory/core/retro.sh < comments.txt" >&2
	exit 2
fi

awk '
	# sorted(a, n, numeric): sort a[1..n] in place, as numbers or as strings.
	function sorted(a, n, numeric,    i, j, x) {
		for (i = 2; i <= n; i++) {
			x = a[i]
			for (j = i - 1; j >= 1 && (numeric ? a[j] + 0 > x + 0 : a[j] "" > x ""); j--) a[j + 1] = a[j]
			a[j + 1] = x
		}
	}
	{
		sub(/\r$/, "")
		if (!match($0, /factory-stats:[ \t][^`*]*/)) next
		line = substr($0, RSTART, RLENGTH)
		sub(/^factory-stats:[ \t]+/, "", line)
		sub(/[ \t]+$/, "", line)
		n = split(line, f, /[ \t]+/)
		issue = ""; lane = ""; ok = 1; counts = ""; split("", seen)
		for (i = 1; i <= n; i++) {
			if (f[i] !~ /^[a-z][a-z-]*=[^=]+$/) { ok = 0; break }
			k = substr(f[i], 1, index(f[i], "=") - 1)
			if (k in seen) { ok = 0; break }
			seen[k] = 1
			v = substr(f[i], index(f[i], "=") + 1)
			if (k == "issue") { if (v !~ /^[1-9][0-9]*$/) { ok = 0; break } issue = v }
			else if (k == "lane") lane = v
			else if (v ~ /^[0-9]+$/) counts = counts " " k "=" v
			else { ok = 0; break }
		}
		if (!ok || issue == "" || lane == "") {
			print "retro: skipped a stats line (it needs issue=<n> lane=<lane>, then <count>=<whole number>, each field once): " $0 > "/dev/stderr"
			next
		}
		if (!(issue in lane_of)) order[++issues] = issue
		lane_of[issue] = lane
		counts_of[issue] = counts
	}
	END {
		if (!issues) { print "retro: no factory-stats line found" > "/dev/stderr"; exit 1 }
		print "retro: " issues " issues"
		for (i = 1; i <= issues; i++) {
			is = order[i]
			lanes[lane_of[is]]++
			m = split(counts_of[is], kv, " ")
			for (j = 1; j <= m; j++) {
				k = substr(kv[j], 1, index(kv[j], "=") - 1)
				v = substr(kv[j], index(kv[j], "=") + 1) + 0
				if (!(k in total)) keys[++nk] = k
				total[k] += v
				if (v || k == "minutes") row[is] = row[is] " " k "=" v
			}
		}
		nl = 0
		for (l in lanes) lane_list[++nl] = l
		sorted(lane_list, nl, 0)
		for (j = 1; j <= nl; j++) print "lane " lane_list[j] ": " lanes[lane_list[j]]
		recorded = 0
		for (i = 1; i <= issues; i++) if ((" " counts_of[order[i]]) ~ / gate-runs=/) recorded++
		print "gate counts: " recorded " of " issues " issues"
		for (j = 1; j <= nk; j++) if (keys[j] !~ /^minutes/) print keys[j] ": " total[keys[j]]
		for (j = 1; j <= nk; j++) if (keys[j] ~ /^minutes/) print keys[j] ": " total[keys[j]]
		sorted(order, issues, 1)
		for (i = 1; i <= issues; i++) if (row[order[i]] != "") print "issue " order[i] ":" row[order[i]]
	}
'
