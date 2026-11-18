const NBSP = " ";
const ZWSP = "​";
const WJ = "⁠";

// A word joiner after each hyphen, so the browser keeps the word whole.
function holdHyphens(word: string): string {
  return word.replaceAll("-", `-${WJ}`);
}

// Joins the words of text, tying the word at `gap` to the one before it.
function tieGap(text: string, gap: number): string {
  return text
    .split(" ")
    .map((raw, index) => {
      const word = index === gap || index === gap + 1 ? holdHyphens(raw) : raw;
      return index === 0 ? word : (index - 1 === gap ? NBSP : " ") + word;
    })
    .join("");
}

// Paragraphs and leads: ties the last two words.
export function tieLast(text: string): string {
  const count = text.split(" ").length;
  return count < 2 ? text : tieGap(text, count - 2);
}

// Headings, card titles, quotes: a three-word label is tied after its first
// word, a longer one before its last, a shorter one is left alone.
export function tieLabel(text: string): string {
  const count = text.split(" ").length;
  if (count < 3) return text;
  return tieGap(text, count === 3 ? 0 : count - 2);
}

// List items and rows: tieLabel's rule, counting the parts of a slash between
// words as words. A slash that is not tied gets a ZWSP after it, a tied one
// stays as it is.
export function tieItem(text: string): string {
  const pieces = text.split(/( |(?<=\S)\/(?=\S))/);
  const count = (pieces.length + 1) / 2;
  const tied = count < 3 ? -1 : count === 3 ? 0 : count - 2;
  const piece = (index: number): string => {
    const word = pieces[index * 2] ?? "";
    const inPair = tied >= 0 && (index === tied || index === tied + 1);
    return inPair ? holdHyphens(word) : word;
  };
  let out = piece(0);
  for (let part = 1; part < count; part += 1) {
    const separator = pieces[part * 2 - 1] ?? " ";
    const isTied = part - 1 === tied;
    if (separator === "/") {
      out += isTied ? "/" : `/${ZWSP}`;
    } else {
      out += isTied ? NBSP : " ";
    }
    out += piece(part);
  }
  return out;
}
