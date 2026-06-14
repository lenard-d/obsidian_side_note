import {EditorState, RangeSetBuilder, StateField} from "@codemirror/state";
import {defaultKeymap, history, historyKeymap, indentLess, indentMore} from "@codemirror/commands";
import {markdown, markdownKeymap} from "@codemirror/lang-markdown";
import {syntaxHighlighting, defaultHighlightStyle, indentUnit} from "@codemirror/language";
import {Decoration, EditorView, keymap, WidgetType} from "@codemirror/view";

const bridge = window.webkit?.messageHandlers?.editor;

function post(message) {
  bridge?.postMessage(message);
}

window.addEventListener("error", (event) => {
  post({type: "error", message: `${event.message || "JavaScript error"} at ${event.filename || "editor"}:${event.lineno || 0}`});
});

window.addEventListener("unhandledrejection", (event) => {
  post({type: "error", message: String(event.reason || "Unhandled editor promise rejection")});
});

function utf16Length(value) {
  return [...value].reduce((length, character) => length + character.length, 0);
}

function taskMarker(line) {
  const match = /^(\s*)([-*+]\s+)(\[[ xX]\])(\s*)/.exec(line);
  if (!match) return null;
  const indentLength = utf16Length(match[1]);
  const listMarkerLength = utf16Length(match[2]);
  const checkboxLength = utf16Length(match[3]);
  const checkboxFrom = indentLength + listMarkerLength;
  return {
    listMarkerFrom: indentLength,
    listMarkerTo: checkboxFrom,
    checkboxFrom,
    checkboxTo: checkboxFrom + checkboxLength,
    checked: /x/i.test(match[3])
  };
}

function atxHeadingMarker(line) {
  const match = /^(\s{0,3})(#{1,6})(\s+|$)/.exec(line);
  if (!match) return null;
  const indentLength = utf16Length(match[1]);
  const markerLength = utf16Length(match[2]) + utf16Length(match[3] || "");
  return {
    level: match[2].length,
    from: indentLength,
    to: indentLength + markerLength
  };
}

function bulletMarker(line) {
  const match = /^(\s*)([-*+])(\s+)/.exec(line);
  if (!match) return null;
  const indentLength = utf16Length(match[1]);
  const tokenLength = utf16Length(match[2]);
  const markerLength = tokenLength + utf16Length(match[3]);
  return {
    from: indentLength,
    to: indentLength + markerLength,
    tokenFrom: indentLength,
    tokenTo: indentLength + tokenLength
  };
}

const listIndent = "  ";

function listItemMarker(line) {
  const task = /^(\s*)([-*+]\s+\[[ xX]\]\s*)/.exec(line);
  if (task) {
    const indentation = task[1];
    const marker = task[2];
    return {
      indentation,
      indentationLength: utf16Length(indentation),
      markerTo: utf16Length(indentation) + utf16Length(marker),
      continuation: `${indentation}${marker.replace(/\[[ xX]\]/, "[ ]")}`
    };
  }

  const unordered = /^(\s*)([-*+]\s+)/.exec(line);
  if (unordered) {
    const indentation = unordered[1];
    const marker = unordered[2];
    return {
      indentation,
      indentationLength: utf16Length(indentation),
      markerTo: utf16Length(indentation) + utf16Length(marker),
      continuation: `${indentation}${marker}`
    };
  }

  const ordered = /^(\s*)(\d+)([.)]\s+)/.exec(line);
  if (ordered) {
    const indentation = ordered[1];
    const number = Number.parseInt(ordered[2], 10) || 1;
    const delimiter = ordered[3];
    return {
      indentation,
      indentationLength: utf16Length(indentation),
      markerTo: utf16Length(indentation) + utf16Length(ordered[2]) + utf16Length(delimiter),
      continuation: `${indentation}${number + 1}${delimiter}`
    };
  }

  return null;
}

function selectedLineNumbers(state) {
  const lineNumbers = new Set();

  for (const range of state.selection.ranges) {
    const startLine = state.doc.lineAt(range.from);
    const endLine = state.doc.lineAt(range.to);
    for (let lineNumber = startLine.number; lineNumber <= endLine.number; lineNumber += 1) {
      lineNumbers.add(lineNumber);
    }
  }

  return [...lineNumbers].sort((left, right) => left - right);
}

function applyChangesPreservingSelection(view, changes) {
  if (changes.length === 0) return false;
  const changeSet = view.state.changes(changes);
  view.dispatch({
    changes: changeSet,
    selection: view.state.selection.map(changeSet, 1),
    scrollIntoView: true
  });
  view.focus();
  return true;
}

function indentSelectedListItems(view) {
  if (!selectionContainsListItem(view.state)) return false;
  return indentMore(view);
}

function outdentLength(lineText) {
  if (lineText.startsWith(listIndent)) return listIndent.length;
  if (lineText.startsWith("\t")) return 1;
  if (lineText.startsWith(" ")) return 1;
  return 0;
}

function outdentSelectedListItems(view) {
  if (!selectionContainsListItem(view.state)) return false;
  indentLess(view);
  return true;
}

function indentListOrInsertSpaces(view) {
  if (indentSelectedListItems(view)) return true;
  insertText(view, listIndent);
  return true;
}

function outdentListOrConsumeKey(view) {
  outdentSelectedListItems(view);
  return true;
}

function selectionContainsListItem(state) {
  return selectedLineNumbers(state).some((lineNumber) => {
    const line = state.doc.line(lineNumber);
    return listItemMarker(line.text) != null;
  });
}

function outdentEmptyListItem(view) {
  const selection = view.state.selection.main;
  if (!selection.empty) return false;

  const line = view.state.doc.lineAt(selection.head);
  const marker = listItemMarker(line.text);
  if (!marker || marker.indentationLength === 0) return false;
  if (selection.head < line.from + marker.markerTo) return false;

  const content = line.text.slice(marker.markerTo);
  if (content.trim().length > 0) return false;

  const removalLength = outdentLength(line.text);
  if (removalLength === 0) return false;

  return applyChangesPreservingSelection(view, [
    {from: line.from, to: line.from + removalLength}
  ]);
}

function selectionTouchesLine(state, line) {
  return state.selection.ranges.some((range) => {
    if (range.empty) return range.head >= line.from && range.head <= line.to;
    return range.from <= line.to && range.to >= line.from;
  });
}

function selectionTouchesToken(state, from, to) {
  return state.selection.ranges.some((range) => {
    if (!range.empty) return range.from < to && range.to > from;
    const head = range.head;
    return head >= from && head <= to;
  });
}

class TaskCheckboxWidget extends WidgetType {
  constructor(checked, position) {
    super();
    this.checked = checked;
    this.position = position;
  }

  eq(other) {
    return other.checked === this.checked && other.position === this.position;
  }

  toDOM(view) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `task-checkbox ${this.checked ? "checked" : ""}`;
    button.setAttribute("aria-label", this.checked ? "Mark task incomplete" : "Mark task complete");
    button.addEventListener("mousedown", (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    button.addEventListener("mouseup", (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      toggleTaskCheckbox(view, this.position, this.checked);
    });
    return button;
  }

  ignoreEvent(event) {
    return event.type === "mousedown" || event.type === "mouseup" || event.type === "click";
  }
}

class BulletMarkerWidget extends WidgetType {
  eq() {
    return true;
  }

  toDOM() {
    const marker = document.createElement("span");
    marker.className = "list-bullet-marker";
    marker.setAttribute("aria-hidden", "true");
    marker.textContent = "•";
    return marker;
  }
}

function toggleTaskCheckbox(view, position, checked) {
  const replacement = checked ? "[ ]" : "[x]";
  const hadFocus = view.hasFocus;
  const selection = view.state.selection;
  view.dispatch({
    changes: {from: position, to: position + 3, insert: replacement},
    selection
  });
  if (hadFocus) view.focus();
}

function buildMarkdownDecorations(state) {
  const builder = new RangeSetBuilder();

  for (let lineNumber = 1; lineNumber <= state.doc.lines; lineNumber += 1) {
    const line = state.doc.line(lineNumber);
    const heading = atxHeadingMarker(line.text);
    if (heading) {
      builder.add(line.from, line.from, Decoration.line({class: `osn-heading-line osn-heading-line-${heading.level}`}));
      if (!selectionTouchesLine(state, line)) {
        builder.add(
          line.from + heading.from,
          line.from + heading.to,
          Decoration.replace({inclusive: false})
        );
      }
    }

    const task = taskMarker(line.text);
    if (task) {
      builder.add(
        line.from + task.listMarkerFrom,
        line.from + task.listMarkerTo,
        Decoration.replace({inclusive: false})
      );

      const checkboxFrom = line.from + task.checkboxFrom;
      const checkboxTo = line.from + task.checkboxTo;
      if (!selectionTouchesToken(state, checkboxFrom, checkboxTo)) {
        builder.add(
          checkboxFrom,
          checkboxTo,
          Decoration.replace({
            widget: new TaskCheckboxWidget(task.checked, checkboxFrom),
            inclusive: false
          })
        );
      }
    } else {
      const bullet = bulletMarker(line.text);
      if (bullet) {
        const markerFrom = line.from + bullet.from;
        const markerTo = line.from + bullet.to;
        const tokenFrom = line.from + bullet.tokenFrom;
        const tokenTo = line.from + bullet.tokenTo;
        if (!selectionTouchesToken(state, tokenFrom, tokenTo)) {
          builder.add(
            markerFrom,
            markerTo,
            Decoration.replace({
              widget: new BulletMarkerWidget(),
              inclusive: false
            })
          );
        }
      }
    }
  }

  return builder.finish();
}

const markdownDecorationField = StateField.define({
  create(state) {
    return buildMarkdownDecorations(state);
  },
  update(decorations, transaction) {
    if (transaction.docChanged || transaction.selection) {
      return buildMarkdownDecorations(transaction.state);
    }
    return decorations.map(transaction.changes);
  },
  provide(field) {
    return EditorView.decorations.from(field);
  }
});

function hasMediaFile(dataTransfer) {
  if (!dataTransfer) return false;
  return [...dataTransfer.files].some((file) =>
    file.type.startsWith("image/") ||
    file.type.startsWith("video/") ||
    /\.(apng|avif|gif|jpe?g|m4v|mov|mp4|png|svg|tiff?|webp)$/i.test(file.name)
  );
}

function hasMediaPaste(event) {
  const items = event.clipboardData?.items;
  if (!items) return false;
  return [...items].some((item) => item.kind === "file" && (
    item.type.startsWith("image/") || item.type.startsWith("video/")
  ));
}

function markdownKeyBindings() {
  return [
    {
      key: "Tab",
      run(view) {
        return indentListOrInsertSpaces(view);
      }
    },
    {
      key: "Shift-Tab",
      run(view) {
        return outdentListOrConsumeKey(view);
      }
    },
    {
      key: "Mod-Shift-Tab",
      run(view) {
        return outdentListOrConsumeKey(view);
      }
    },
    {
      key: "Backspace",
      run(view) {
        return outdentEmptyListItem(view);
      }
    },
    {
      key: "Delete",
      run(view) {
        return outdentEmptyListItem(view);
      }
    },
    {
      key: "Mod-b",
      run(view) {
        applyCommand(view, {type: "wrap", wrapper: "**"});
        return true;
      }
    },
    {
      key: "Mod-i",
      run(view) {
        applyCommand(view, {type: "wrap", wrapper: "*"});
        return true;
      }
    },
    ...markdownKeymap,
    ...defaultKeymap,
    ...historyKeymap
  ];
}

function applyCommand(view, command) {
  switch (command.type) {
    case "wrap":
      wrapSelection(view, command.wrapper);
      break;
    case "insertLink":
      replaceSelection(view, "[link text](url)", "link text");
      break;
    case "insertPrefix":
      insertLinePrefix(view, command.prefix);
      break;
    case "insertText":
      insertText(view, command.text);
      break;
    default:
      break;
  }
}

function wrapSelection(view, wrapper) {
  const selection = view.state.selection.main;
  const selected = selection.empty ? "text" : view.state.sliceDoc(selection.from, selection.to);
  const replacement = `${wrapper}${selected}${wrapper}`;
  const anchor = selection.empty ? selection.from + wrapper.length : selection.from;
  const head = selection.empty ? anchor + selected.length : selection.from + replacement.length;
  view.dispatch({
    changes: {from: selection.from, to: selection.to, insert: replacement},
    selection: {anchor, head},
    scrollIntoView: true
  });
  view.focus();
}

function replaceSelection(view, replacement, selectedPlaceholder = null) {
  const selection = view.state.selection.main;
  const selected = selection.empty ? "" : view.state.sliceDoc(selection.from, selection.to);
  const finalText = selectedPlaceholder && !selection.empty
    ? replacement.replace(selectedPlaceholder, selected)
    : replacement;
  const placeholder = selectedPlaceholder && !selection.empty ? selected : selectedPlaceholder;
  const placeholderStart = placeholder ? finalText.indexOf(placeholder) : -1;
  const anchor = placeholderStart >= 0 ? selection.from + placeholderStart : selection.from;
  const head = placeholderStart >= 0 ? anchor + placeholder.length : selection.from + finalText.length;
  view.dispatch({
    changes: {from: selection.from, to: selection.to, insert: finalText},
    selection: {anchor, head},
    scrollIntoView: true
  });
  view.focus();
}

function insertText(view, text) {
  const selection = view.state.selection.main;
  view.dispatch({
    changes: {from: selection.from, to: selection.to, insert: text},
    selection: {anchor: selection.from + text.length},
    scrollIntoView: true
  });
  view.focus();
}

function insertLinePrefix(view, prefix) {
  const selection = view.state.selection.main;
  const startLine = view.state.doc.lineAt(selection.from);
  const endLine = view.state.doc.lineAt(selection.to);
  const changes = [];

  for (let lineNumber = startLine.number; lineNumber <= endLine.number; lineNumber += 1) {
    const line = view.state.doc.line(lineNumber);
    changes.push({from: line.from, insert: prefix});
  }

  view.dispatch({
    changes,
    selection: {
      anchor: selection.anchor + prefix.length,
      head: selection.head + prefix.length * changes.length
    },
    scrollIntoView: true
  });
  view.focus();
}

function applyAppearance(view, scheme) {
  const isDark = scheme !== "light";
  view.dom.classList.toggle("osn-dark", isDark);
  view.dom.classList.toggle("osn-light", !isDark);
}

function focusBlankEditorArea(view, event) {
  if (event.button !== 0) return false;
  if (event.target.closest?.(".task-checkbox")) return false;
  if (event.target.closest?.(".cm-line")) return false;

  event.preventDefault();
  view.dispatch({
    selection: {anchor: view.state.doc.length},
    scrollIntoView: true
  });
  view.focus();
  return true;
}

function installEditor() {
  let applyingExternalChange = false;
  const root = document.getElementById("editor");
  const state = EditorState.create({
    doc: "",
    extensions: [
      history(),
      markdown({addKeymap: false}),
      indentUnit.of(listIndent),
      syntaxHighlighting(defaultHighlightStyle, {fallback: true}),
      markdownDecorationField,
      keymap.of(markdownKeyBindings()),
      EditorView.lineWrapping,
      EditorView.updateListener.of((update) => {
        if (update.focusChanged) {
          post({type: update.view.hasFocus ? "focus" : "blur"});
        }
        if (update.docChanged && !applyingExternalChange) {
          post({type: "change", text: update.state.doc.toString()});
        }
      }),
      EditorView.domEventHandlers({
        mousedown(event, view) {
          return focusBlankEditorArea(view, event);
        },
        paste(event) {
          if (hasMediaPaste(event)) {
            event.preventDefault();
            post({type: "pasteMedia"});
            return true;
          }
          return false;
        },
        drop(event, view) {
          if (hasMediaFile(event.dataTransfer)) {
            post({type: "dropMedia"});
          }
          view.focus();
          return false;
        },
        click(_event, view) {
          view.focus();
          return false;
        }
      }),
      EditorView.theme({
        "&": {
          height: "100%",
          backgroundColor: "transparent",
          color: "#ffffff",
          font: "16px -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
        },
        "&.osn-light": {
          color: "#ffffff"
        },
        "&.osn-dark": {
          color: "#ffffff"
        },
        ".cm-scroller": {
          height: "100%",
          overflow: "auto",
          fontFamily: "inherit",
          lineHeight: "1.58"
        },
        ".cm-content": {
          minHeight: "100%",
          padding: "8px 12px 0",
          caretColor: "currentColor"
        },
        ".cm-content, .cm-content *, .cm-line, .cm-line *": {
          color: "#ffffff !important",
          textDecoration: "none !important",
          textDecorationLine: "none !important"
        },
        ".cm-cursor": {
          borderLeftColor: "currentColor",
          borderLeftWidth: "1.5px"
        },
        ".cm-line": {
          padding: "0"
        },
        ".cm-line.osn-heading-line": {
          lineHeight: "1.28",
          padding: "2px 0 1px"
        },
        ".cm-line.osn-heading-line-1": {
          fontSize: "1.42em",
          fontWeight: "820"
        },
        ".cm-line.osn-heading-line-2": {
          fontSize: "1.3em",
          fontWeight: "780"
        },
        ".cm-line.osn-heading-line-3": {
          fontSize: "1.18em",
          fontWeight: "740"
        },
        ".cm-line.osn-heading-line-4": {
          fontSize: "1.1em",
          fontWeight: "700"
        },
        ".cm-line.osn-heading-line-5, .cm-line.osn-heading-line-6": {
          fontSize: "1.04em",
          fontWeight: "680"
        },
        ".cm-focused": {
          outline: "none"
        },
        ".cm-selectionBackground, .cm-content ::selection": {
          backgroundColor: "SelectedTextBackgroundColor"
        },
        ".cm-gutters": {
          display: "none"
        },
        ".task-checkbox": {
          appearance: "none",
          boxSizing: "border-box",
          position: "relative",
          width: "15px",
          height: "15px",
          minWidth: "15px",
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          margin: "0 5px 0 0",
          padding: "0",
          borderRadius: "4px",
          border: "1px solid rgb(255, 255, 255)",
          background: "transparent",
          color: "white",
          font: "0 -apple-system, BlinkMacSystemFont, sans-serif",
          lineHeight: "15px",
          overflow: "hidden",
          textAlign: "center",
          verticalAlign: "-0.13em",
          cursor: "default"
        },
        ".task-checkbox.checked": {
          borderColor: "#0a84ff",
          background: "#0a84ff"
        },
        ".task-checkbox.checked::after": {
          content: '"✓"',
          position: "absolute",
          inset: "0",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "white",
          font: "11px -apple-system, BlinkMacSystemFont, sans-serif",
          lineHeight: "15px",
          pointerEvents: "none"
        },
        ".list-bullet-marker": {
          boxSizing: "border-box",
          display: "inline-flex",
          width: "15px",
          height: "15px",
          minWidth: "15px",
          alignItems: "center",
          justifyContent: "center",
          margin: "0 5px 0 0",
          color: "rgb(255, 255, 255)",
          fontSize: "18px",
          fontWeight: "700",
          lineHeight: "14px",
          verticalAlign: "-0.13em"
        }
      })
    ]
  });

  const view = new EditorView({state, parent: root});
  applyAppearance(view, "dark");

  root.addEventListener("mousedown", (event) => {
    if (event.target === root) {
      event.preventDefault();
      view.focus();
    }
  });

  window.editor = {
    setMarkdown(text) {
      const current = view.state.doc.toString();
      if (current === text) return;
      applyingExternalChange = true;
      view.dispatch({
        changes: {from: 0, to: current.length, insert: text},
        selection: {anchor: Math.min(view.state.selection.main.head, text.length)}
      });
      applyingExternalChange = false;
    },
    getMarkdown() {
      return view.state.doc.toString();
    },
    getSelection() {
      const selection = view.state.selection.main;
      return {
        from: selection.from,
        to: selection.to,
        anchor: selection.anchor,
        head: selection.head,
        docLength: view.state.doc.length,
        focused: view.hasFocus
      };
    },
    setSelection(position) {
      const boundedPosition = Math.max(0, Math.min(Number(position) || 0, view.state.doc.length));
      view.dispatch({selection: {anchor: boundedPosition}, scrollIntoView: true});
    },
    simulateBlankAreaMouseDownForTests() {
      const event = {
        button: 0,
        target: view.scrollDOM,
        preventDefault() {}
      };
      return focusBlankEditorArea(view, event);
    },
    visibleTextForTests() {
      return view.contentDOM.innerText;
    },
    taskCheckboxCountForTests() {
      return view.dom.querySelectorAll(".task-checkbox").length;
    },
    bulletMarkerCountForTests() {
      return view.dom.querySelectorAll(".list-bullet-marker").length;
    },
    firstTaskCheckboxMetricsForTests() {
      const checkbox = view.dom.querySelector(".task-checkbox");
      if (!checkbox) return null;
      const selection = view.state.selection.main;
      const before = {anchor: selection.anchor, head: selection.head};
      checkbox.dispatchEvent(new MouseEvent("mousedown", {bubbles: true, cancelable: true, button: 0}));
      checkbox.dispatchEvent(new MouseEvent("mouseup", {bubbles: true, cancelable: true, button: 0}));
      checkbox.dispatchEvent(new MouseEvent("click", {bubbles: true, cancelable: true, button: 0}));
      const after = view.state.selection.main;
      return {
        before,
        after: {anchor: after.anchor, head: after.head},
        markdown: view.state.doc.toString()
      };
    },
    selectAllForTests() {
      view.dispatch({
        selection: {anchor: 0, head: view.state.doc.length},
        scrollIntoView: true
      });
    },
    taskCheckboxAlignmentForTests() {
      return [...view.dom.querySelectorAll(".task-checkbox")].map((checkbox) => {
        const line = checkbox.closest(".cm-line");
        const rect = checkbox.getBoundingClientRect();
        const lineRect = line?.getBoundingClientRect();
        const style = getComputedStyle(checkbox);
        return {
          checked: checkbox.classList.contains("checked"),
          width: rect.width,
          height: rect.height,
          topWithinLine: lineRect ? rect.top - lineRect.top : null,
          centerDelta: lineRect ? (rect.top + rect.height / 2) - (lineRect.top + lineRect.height / 2) : null,
          bottomWithinLine: lineRect ? lineRect.bottom - rect.bottom : null,
          verticalAlign: style.verticalAlign,
          lineHeight: style.lineHeight,
          fontSize: style.fontSize
        };
      });
    },
    dispatchKeyForTests(key, modifiers = {}) {
      view.focus();
      const event = new KeyboardEvent("keydown", {
        key,
        bubbles: true,
        cancelable: true,
        shiftKey: Boolean(modifiers.shiftKey),
        metaKey: Boolean(modifiers.metaKey),
        ctrlKey: Boolean(modifiers.ctrlKey),
        altKey: Boolean(modifiers.altKey)
      });
      view.contentDOM.dispatchEvent(event);
      return event.defaultPrevented;
    },
    indentListItemForTests() {
      return indentSelectedListItems(view);
    },
    outdentListItemForTests() {
      return outdentSelectedListItems(view);
    },
    outdentEmptyListItemForTests() {
      return outdentEmptyListItem(view);
    },
    presentationStylesForTests() {
      const checkbox = view.dom.querySelector(".task-checkbox");
      const bullet = view.dom.querySelector(".list-bullet-marker");
      const scroller = view.dom.querySelector(".cm-scroller");
      const headingLines = [1, 2, 3].map((level) => {
        const line = view.dom.querySelector(`.osn-heading-line-${level}`);
        if (!line) return null;
        const style = getComputedStyle(line);
        return {
          level,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          lineHeight: style.lineHeight
        };
      });

      return {
        checkbox: checkbox ? {
          borderColor: getComputedStyle(checkbox).borderColor,
          display: getComputedStyle(checkbox).display,
          alignItems: getComputedStyle(checkbox).alignItems,
          justifyContent: getComputedStyle(checkbox).justifyContent,
          verticalAlign: getComputedStyle(checkbox).verticalAlign
        } : null,
        bullet: bullet ? {
          text: bullet.textContent,
          color: getComputedStyle(bullet).color,
          display: getComputedStyle(bullet).display,
          alignItems: getComputedStyle(bullet).alignItems,
          justifyContent: getComputedStyle(bullet).justifyContent,
          verticalAlign: getComputedStyle(bullet).verticalAlign
        } : null,
        scrollerLineHeight: scroller ? getComputedStyle(scroller).lineHeight : null,
        headingLines
      };
    },
    textColorsForTests() {
      return [...view.dom.querySelectorAll(".cm-content, .cm-content *")]
        .filter((element) => element.innerText && element.innerText.trim().length > 0)
        .map((element) => getComputedStyle(element).color);
    },
    focusEnd() {
      const end = view.state.doc.length;
      view.dispatch({selection: {anchor: end}, scrollIntoView: true});
      view.focus();
    },
    focus() {
      view.focus();
    },
    applyCommand(command) {
      applyCommand(view, command);
    },
    insertMarkdown(text) {
      applyCommand(view, {type: "insertText", text});
    },
    setAppearance(scheme) {
      applyAppearance(view, scheme);
    }
  };

  post({type: "ready"});
}

installEditor();
