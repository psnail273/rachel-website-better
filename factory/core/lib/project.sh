# The project's name, as the factory spells it in verify-<project>. Sourced by
# adopt.sh and verify-skill.sh; defines no side effects.

# factory_project_name [root]: $FACTORY_PROJECT when set, else the name of the
# origin remote's repo, else the root folder's name (default: the current one);
# lowercased, with `_` and spaces turned into `-`.
factory_project_name() {
	local name="${FACTORY_PROJECT:-}"
	[ -n "$name" ] || name="$(git config --get remote.origin.url 2> /dev/null)"
	[ -n "$name" ] || name="${1:-$(pwd)}"
	name="${name%/}"
	name="${name##*/}"
	name="${name##*:}"
	name="${name%.git}"
	printf '%s\n' "$name" | tr 'A-Z_ ' 'a-z--'
}
