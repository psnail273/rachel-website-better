// The mutate step's StrykerJS ignorer plugin (the mutate step registers it, by
// path, over the project's stryker.config.json): no StringLiteral mutant on a
// class string, which no unit test reads (styling is the design check's and
// smoke's layout check's to judge). A class string is a string literal, or a
// template literal with no ${} in it,
//   - that is a className attribute's value: className="p-4", className={"p-4"};
//   - or a module-level const's value whose name ends in Class or _CLASS:
//     const linkClass = "underline", export const LINK_CLASS = "x";
// or reaches one of those only through a branch of a ?: (not its test), a side
// of && || ??, an argument of a class-joining call (cn, clsx, classNames, cx,
// twMerge, twJoin), or an `as` or `satisfies`:
//   className={on ? "a" : "b"}, className={cn("m-2", on && "x")}.
// Only those literals are skipped: every other mutant on the attribute or the
// constant (the ?:'s test, the && itself, a ${} inside a template) still runs,
// and a template literal with a ${} in it is still mutated whole.
//
// Stryker reports a skipped mutant as Ignored, with the reason below as its
// statusReason; _stryker_mutants.mjs leaves those out of what it prints.
export const REASON = "factory: a class string (a className attribute or a *Class/*_CLASS constant)";

const JOINERS = new Set(["cn", "clsx", "classNames", "cx", "twMerge", "twJoin"]);
const CONSTANT = /(Class|_CLASS)$/;

const isString = (node) =>
  node.type === "StringLiteral" || (node.type === "TemplateLiteral" && node.expressions.length === 0);

// classTarget(path): whether the string at path is a class string, walking up
// through the wrappers above.
function classTarget(path) {
  let child = path;
  let parent = path.parentPath;
  while (parent) {
    const node = parent.node;
    switch (node.type) {
      case "JSXAttribute":
        return node.name?.type === "JSXIdentifier" && node.name.name === "className";
      case "JSXExpressionContainer":
      case "LogicalExpression":
      case "TSAsExpression":
      case "TSSatisfiesExpression":
        break;
      case "ConditionalExpression":
        if (child.key === "test") return false;
        break;
      case "CallExpression":
        if (child.listKey !== "arguments" || node.callee.type !== "Identifier" || !JOINERS.has(node.callee.name))
          return false;
        break;
      case "VariableDeclarator": {
        if (child.key !== "init" || node.id.type !== "Identifier" || !CONSTANT.test(node.id.name)) return false;
        const declaration = parent.parentPath;
        const holder = declaration?.parentPath;
        return (
          declaration?.node.kind === "const" &&
          (holder?.node.type === "Program" ||
            (holder?.node.type === "ExportNamedDeclaration" && holder.parentPath?.node.type === "Program"))
        );
      }
      default:
        return false;
    }
    child = parent;
    parent = parent.parentPath;
  }
  return false;
}

const ignorer = {
  shouldIgnore(path) {
    return isString(path.node) && classTarget(path) ? REASON : undefined;
  },
};

export const strykerPlugins = [{ kind: "Ignore", name: "factory-class-strings", value: ignorer }];
