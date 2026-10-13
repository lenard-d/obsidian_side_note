import {EditorSelection, EditorState, StateEffect, StateField} from "@codemirror/state";
import {Decoration, EditorView} from "@codemirror/view";
import {parseDocument} from "yaml";

export const setFrontmatterMode = StateEffect.define();

function frontmatterIn(doc) {
  if (doc.line(1).text !== "---") return null;

  for (let number = 2; number <= doc.lines; number += 1) {
    const line = doc.line(number);
    if (line.text !== "---" && line.text !== "...") continue;

    const source = doc.sliceString(doc.line(1).to + 1, line.from);
    let value = null;
    let error = false;
    try {
      const parsed = parseDocument(source);
      error = parsed.errors.length > 0;
      if (!error) value = parsed.toJS();
    } catch {
      error = true;
    }
    return {
      to: line.to < doc.length ? line.to + 1 : line.to,
      entries: value && !Array.isArray(value) && typeof value === "object"
        ? Object.entries(value)
        : [],
      error: error || (value !== null && (Array.isArray(value) || typeof value !== "object"))
    };
  }

  return null;
}

function displayValue(value, ancestors = new Set()) {
  if (value === null) return "";
  if (typeof value === "object") {
    if (ancestors.has(value)) return "[Circular reference]";
    const nestedAncestors = new Set(ancestors).add(value);
    if (Array.isArray(value)) return value.map((item) => displayValue(item, nestedAncestors)).join(", ");
    const parents = [];
    return JSON.stringify(value, function (key, item) {
      if (item && typeof item === "object") {
        while (parents.length && parents.at(-1) !== this) parents.pop();
        if (parents.includes(item)) return "[Circular reference]";
        parents.push(item);
      }
      return item;
    });
  }
  return String(value);
}

export const frontmatterField = StateField.define({
  create(state) {
    return {mode: "collapsed", frontmatter: frontmatterIn(state.doc)};
  },
  update(value, transaction) {
    let mode = value.mode;
    for (const effect of transaction.effects) {
      if (effect.is(setFrontmatterMode)) mode = effect.value;
    }
    return {
      mode,
      frontmatter: transaction.docChanged ? frontmatterIn(transaction.state.doc) : value.frontmatter
    };
  },
  provide(field) {
    return EditorView.decorations.from(field, (value) => {
      if (!value.frontmatter || value.mode === "source") return Decoration.none;
      return Decoration.set([
        Decoration.replace({block: true}).range(0, value.frontmatter.to)
      ]);
    });
  }
});

export const frontmatterAtomicRanges = EditorView.atomicRanges.of((view) => {
  const {frontmatter, mode} = view.state.field(frontmatterField);
  if (!frontmatter || mode === "source") return Decoration.none;
  return Decoration.set([Decoration.replace({}).range(0, frontmatter.to)]);
});

// Hidden properties must survive edits that cross the start of the visible body.
export const protectHiddenFrontmatter = [
  EditorState.changeFilter.of((transaction) => {
    const {frontmatter, mode} = transaction.startState.field(frontmatterField);
    return frontmatter && mode !== "source" ? [0, frontmatter.to] : true;
  }),
  EditorState.transactionFilter.of((transaction) => {
    const start = transaction.startState.field(frontmatterField);
    if (start.frontmatter && start.mode !== "source"
        && start.frontmatter.to === transaction.startState.doc.length
        && transaction.docChanged && transaction.newDoc.length > start.frontmatter.to
        && transaction.newDoc.sliceString(start.frontmatter.to, start.frontmatter.to + 1) !== "\n") {
      return [transaction, {
        changes: {from: start.frontmatter.to, insert: "\n"}, sequential: true
      }];
    }
    const {frontmatter, mode} = transaction.state.field(frontmatterField);
    if (!frontmatter || mode === "source") return transaction;
    const selection = transaction.newSelection;
    if (selection.ranges.every((range) => range.from >= frontmatter.to)) return transaction;
    return [transaction, {
      selection: EditorSelection.create(selection.ranges.map((range) => EditorSelection.range(
        Math.max(range.anchor, frontmatter.to), Math.max(range.head, frontmatter.to)
      )), selection.mainIndex)
    }];
  })
];

export function moveSelectionAfterHiddenFrontmatter(view) {
  const {frontmatter, mode} = view.state.field(frontmatterField);
  if (!frontmatter || mode === "source") return;
  const selection = view.state.selection.main;
  if (selection.head >= frontmatter.to) return;
  view.dispatch({selection: {anchor: frontmatter.to}});
}

export function frontmatterProperties(view) {
  const {frontmatter, mode} = view.state.field(frontmatterField);
  return {
    hasFrontmatter: Boolean(frontmatter),
    entries: frontmatter?.entries.map(([key, value]) => ({key, value: displayValue(value)})) ?? [],
    error: frontmatter?.error ?? false,
    sourceVisible: mode === "source"
  };
}

export function toggleFrontmatterSource(view) {
  const {frontmatter, mode} = view.state.field(frontmatterField);
  if (!frontmatter) {
    view.dispatch({
      changes: {from: 0, insert: "---\n\n---\n\n"},
      effects: setFrontmatterMode.of("source"),
      selection: {anchor: 4}
    });
  } else {
    view.dispatch({effects: setFrontmatterMode.of(mode === "source" ? "collapsed" : "source")});
    moveSelectionAfterHiddenFrontmatter(view);
  }
  view.focus();
}
