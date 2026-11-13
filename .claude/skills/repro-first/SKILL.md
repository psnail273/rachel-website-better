---
name: repro-first
description: Fix a bug by committing a failing repro first, then proving the fix on the surface where the bug appeared. Use for a Kind: bug issue, or before fixing any reported bug.
---

A bug is fixed when a **repro** that went red on it goes green, and the bug is gone on the **surface** where it was seen. The surface is where the report came from: a phone, a desktop build, a headless run, the test suite, a CI log. A fix shown only on another surface is unproven.

Work the steps in order. Each ends on its completion criterion; skip one only with a written `skip:` reason in your report.

## 1. Reproduce on the surface

Read the report and name its surface, its trigger (the inputs, state and steps) and its symptom (what was seen, against what was expected). Make the bug happen there, through the project's `verify-<project>` skill (Launch, Drive, Evidence) where the surface is a running build.

Done when you have watched the symptom happen and kept the evidence: a command with its output or exit code, a log line, a capture. When it won't happen after a fair try, the result is **inconclusive**, and inconclusive counts as a fail: stop and report what you tried, what you saw and what you need. A fix for a bug you never saw is a guess.

## 2. Write the repro

Narrow the trigger to the smallest one that still shows the symptom, then capture it as an automated test at the lowest seam that holds the bug: a pure function before a component, a component before a full run. Follow the stack's `write-tests-<stack>` skill. The test's name says the behaviour that broke (`test_total_stays_right_after_an_item_is_removed`), and its expected value is the correct behaviour from the report or spec, written by hand.

Done when the repro fails **for the reported reason**: an assertion failure whose message matches the symptom. A crash, a parse error, a skip or a failure about something else is not the repro yet.

When no automated test can hold the symptom (how it looks or feels on a device), the repro is a scripted, repeatable reproduction on the surface instead: write its steps and expected result into the issue's report, and say why a test can't hold it.

## 3. Commit the repro alone

Commit the repro with no product change in the commit, so anyone can check out that commit and watch it go red. In a factory run this commit is the **Lock**: the repro stays as committed.

Done when `git show --stat HEAD` lists only test files and the repro is red at `HEAD`.

## 4. Fix

Change the product code until the repro goes green, and keep the fix to the cause the repro exposed. Then run the project's full verify.

Done when the repro passes, every other test still passes, and the full verify exits 0.

## 5. Verify on the surface

Repeat step 1's trigger on the same surface, with the fixed build.

Done when the symptom is gone and you hold evidence of the same kind as step 1's. Inconclusive counts as a fail here too: a surface you couldn't reach leaves the bug open, so report that rather than call it fixed.

## Report

Give the surface, step 1's evidence, the repro's name and its red commit, the fix commit, the verify result and step 5's evidence.
