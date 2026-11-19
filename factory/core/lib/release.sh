# The factory's releases at its repo: its highest release tag. Sourced by sync.sh
# and new-project.sh, after lib/vendor.sh (factory_version_is,
# factory_version_greater) and lib/bounded.sh (factory_run_bounded); defines no
# side effects. Its reasons go to stderr through the caller's `say`.

# factory_latest_release <upstream>: print the upstream's highest v<major>.<minor>.<patch>
# tag. False, the reason on stderr, when ls-remote fails or times out, or the
# upstream has no such tag. The network is bounded: a limit on ls-remote
# (factory_run_bounded, lib/bounded.sh: `timeout`, or a watchdog where there is
# none, as on stock macOS), and ssh told to give up connecting after 5 seconds
# and never to prompt (appended to the ssh command git would use), as git is
# told for https.
factory_latest_release() {
	local upstream="$1" limit="${FACTORY_SYNC_TIMEOUT:-10}" ssh refs best="" t err
	ssh="${GIT_SSH_COMMAND:-$(git config --get core.sshCommand 2> /dev/null)}"
	if [ -n "$ssh" ] || [ -z "${GIT_SSH:-}" ]; then
		ssh="${ssh:-ssh} -o ConnectTimeout=5 -o BatchMode=yes"
	else
		ssh=""
	fi
	err="$(mktemp)"
	refs="$(
		export GIT_TERMINAL_PROMPT=0
		[ -z "$ssh" ] || export GIT_SSH_COMMAND="$ssh"
		factory_run_bounded "$limit" git ls-remote --tags --refs "$upstream" < /dev/null 2> "$err"
	)"
	case $? in
		0) ;;
		124)
			rm -f "$err"
			say "could not list the tags at $upstream: no answer in $limit seconds"
			return 1
			;;
		*)
			sed 's/^/  /' "$err" >&2
			rm -f "$err"
			say "could not list the tags at $upstream"
			return 1
			;;
	esac
	rm -f "$err"
	while IFS= read -r t; do
		t="${t##*refs/tags/}"
		factory_version_is "${t#v}" && [ "${t#v}" != "$t" ] || continue
		if [ -z "$best" ] || factory_version_greater "${t#v}" "${best#v}"; then best="$t"; fi
	done <<< "$refs"
	[ -n "$best" ] || {
		say "no release at $upstream (no tag v<major>.<minor>.<patch>)"
		return 1
	}
	printf '%s\n' "$best"
}
