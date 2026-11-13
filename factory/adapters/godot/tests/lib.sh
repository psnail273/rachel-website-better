# Helpers for the Godot adapter's tests, sourced by each Godot *_test.sh after the
# Core's tests/lib.sh.
#
# A real GODOT_BIN becomes isolated_godot.sh, which runs it with the test's own
# user data and under the machine's Godot slot pool; FACTORY_TEST_GODOT keeps the
# real one. A test that sets GODOT_BIN itself (a fake, or empty) bypasses it.
if [ -n "${GODOT_BIN:-}" ] && [ -z "${FACTORY_TEST_GODOT:-}" ]; then
	export FACTORY_TEST_GODOT="$GODOT_BIN"
	export GODOT_BIN="$FACTORY_CORE/../adapters/godot/tests/isolated_godot.sh"
fi

# No Godot a test starts runs adb (#10). Godot's editor (an --import, an export)
# takes its Android SDK from its editor settings, whose default is $ANDROID_HOME,
# or ~/Android/Sdk when that is unset; it polls that SDK's platform-tools/adb for
# devices and runs `adb kill-server` as it exits. So a test's Godot started an adb
# server, which read the human's ~/.android/adbkey, and killed any adb server
# running on the machine. A test's Godot starts on fresh editor settings (its own
# user data: isolated_godot.sh, or each mutate worker's), so ANDROID_HOME here, a
# folder that never exists, leaves it no adb to find. It is exported, so every
# Godot a test starts inherits it, through isolated_godot.sh or not. A project's
# own runs (its Playtest step, the verify skill's adb steps) never source this.
if [ -n "${TEST_TMP:-}" ]; then
	export TEST_TMP ANDROID_HOME="$TEST_TMP/no-android-sdk"
fi

# gdunit4_source: print the folder of a gdUnit4 addon at the version the
# adapter's pins name: $FACTORY_GDUNIT4 when set, else the host project's
# addons/gdUnit4. False when neither holds that version, so a test that needs
# gdUnit4 skips rather than run another one.
gdunit4_source() {
	local pin src
	pin="$(tr -d '\r' < "$FACTORY_CORE/../adapters/godot/tools/verify/pins" | sed -n 's/^gdunit4 //p')"
	for src in "${FACTORY_GDUNIT4:-}" "$FACTORY_CORE/../../addons/gdUnit4"; do
		[ -n "$src" ] && [ -f "$src/plugin.cfg" ] || continue
		[ "$(tr -d '\r' < "$src/plugin.cfg" | sed -n 's/^version="\(.*\)"$/\1/p')" = "$pin" ] || continue
		(cd "$src" && pwd)
		return 0
	done
	return 1
}

# real_formatter: skip unless gdscript-formatter 0.27.0 runs (GDSCRIPT_FORMATTER,
# else on PATH). real_gdmutant: skip unless gdmutant 0.1.4 runs (GDMUTANT_BIN,
# else on PATH). Each is its tool's one skip: names_test.sh reads a test that
# skips with it as starting that tool, so the test's name ends in _with_<tool>.
real_formatter() {
	[ "$("${GDSCRIPT_FORMATTER:-gdscript-formatter}" --version 2> /dev/null | tr -d '\r')" = "gdscript-formatter 0.27.0" ] ||
		skip "no gdscript-formatter 0.27.0 (set GDSCRIPT_FORMATTER, or put it on PATH)"
}

real_gdmutant() {
	[ "$("${GDMUTANT_BIN:-gdmutant}" --version 2> /dev/null)" = "gdmutant 0.1.4" ] ||
		skip "no gdmutant 0.1.4 (set GDMUTANT_BIN, or put it on PATH)"
}
