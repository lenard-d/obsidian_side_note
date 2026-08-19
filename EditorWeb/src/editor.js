import {Compartment, EditorState, StateEffect, StateField} from "@codemirror/state";
import {defaultKeymap, history, historyKeymap, indentLess, indentMore} from "@codemirror/commands";
import {markdown, markdownKeymap} from "@codemirror/lang-markdown";
import {syntaxHighlighting, indentUnit, syntaxTree} from "@codemirror/language";
import {Decoration, EditorView, keymap, WidgetType} from "@codemirror/view";
import {installEditorTestAdapter} from "./editor-test-adapter.js";
import {editorTheme, markdownHighlightStyle} from "./editor-theme.js";

const bridge = window.webkit?.messageHandlers?.editor;
const readOnlyViews = new WeakSet();

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
const imageExtensions = new Set(["apng", "avif", "gif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]);
const refreshMediaEmbedsEffect = StateEffect.define();
let mediaEmbedSources = new Map();
let textReplacements = new Map();

const inlineSyntaxPresentations = new Map([
  ["StrongEmphasis", {markerName: "EmphasisMark", className: "osn-inline-strong"}],
  ["Emphasis", {markerName: "EmphasisMark", className: "osn-inline-emphasis"}],
  ["InlineCode", {markerName: "CodeMark", className: "osn-inline-code"}]
]);

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

function inlineSyntaxPresentationDecorations(state) {
  const decorations = [];

  syntaxTree(state).iterate({
    enter(node) {
      const presentation = inlineSyntaxPresentations.get(node.name);
      if (!presentation) return;

      const markers = node.node.getChildren(presentation.markerName);
      if (markers.length < 2) return;

      const firstMarker = markers[0];
      const lastMarker = markers[markers.length - 1];
      addInlinePresentationDecorations(
        decorations,
        state,
        node.from,
        node.to,
        firstMarker.to,
        lastMarker.from,
        presentation.className,
        markers.map((marker) => ({from: marker.from, to: marker.to}))
      );
    }
  });

  addHighlightPresentationDecorations(decorations, state);

  return decorations;
}

function addInlinePresentationDecorations(
  decorations,
  state,
  from,
  to,
  contentFrom,
  contentTo,
  className,
  markers
) {
  if (contentFrom < contentTo) {
    decorations.push(
      Decoration.mark({class: className}).range(contentFrom, contentTo)
    );
  }

  if (selectionTouchesToken(state, from, to)) return;
  for (const marker of markers) {
    decorations.push(
      Decoration.replace({inclusive: false}).range(marker.from, marker.to)
    );
  }
}

function addHighlightPresentationDecorations(decorations, state) {
  for (let lineNumber = 1; lineNumber <= state.doc.lines; lineNumber += 1) {
    const line = state.doc.line(lineNumber);
    const pattern = /==(.+?)==/g;
    let match;

    while ((match = pattern.exec(line.text)) != null) {
      const from = line.from + match.index;
      const to = from + match[0].length;
      const contentFrom = from + 2;
      const contentTo = to - 2;
      addInlinePresentationDecorations(
        decorations,
        state,
        from,
        to,
        contentFrom,
        contentTo,
        "osn-inline-highlight",
        [
          {from, to: contentFrom},
          {from: contentTo, to}
        ]
      );
    }
  }
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
    const dot = document.createElement("span");
    dot.className = "list-bullet-dot";
    marker.appendChild(dot);
    return marker;
  }
}

class ImageEmbedWidget extends WidgetType {
  constructor(embed, source, position) {
    super();
    this.embed = embed;
    this.source = source;
    this.position = position;
  }

  eq(other) {
    return other.source === this.source &&
      other.embed.link === this.embed.link &&
      other.embed.title === this.embed.title &&
      other.position === this.position;
  }

  toDOM(view) {
    const figure = document.createElement("figure");
    figure.className = "image-embed";
    figure.title = this.embed.link;

    const image = document.createElement("img");
    image.src = this.source;
    image.alt = this.embed.title || this.embed.link;
    image.draggable = false;
    figure.appendChild(image);

    figure.addEventListener("mousedown", (event) => {
      event.preventDefault();
      view.dispatch({
        selection: {anchor: this.position},
        scrollIntoView: true
      });
      view.focus();
    });

    return figure;
  }

  ignoreEvent(event) {
    return event.type === "mousedown";
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

function imageEmbed(line) {
  const trimmed = line.trim();
  const wikiEmbed = /^!\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]$/.exec(trimmed);
  if (wikiEmbed) {
    const link = wikiEmbed[1].trim();
    if (!isImageLink(link)) return null;
    return {
      link,
      title: (wikiEmbed[2] || displayNameForLink(link)).trim()
    };
  }

  const markdownImage = /^!\[([^\]]*)\]\(([^)]+)\)$/.exec(trimmed);
  if (!markdownImage) return null;

  const link = markdownImage[2].trim();
  if (!isImageLink(link)) return null;
  return {
    link,
    title: (markdownImage[1] || displayNameForLink(link)).trim()
  };
}

function isImageLink(link) {
  const extension = extensionForLink(link);
  return imageExtensions.has(extension);
}

function extensionForLink(link) {
  const cleanLink = link.split(/[?#]/)[0];
  const lastPathComponent = cleanLink.split("/").pop() || cleanLink;
  const dotIndex = lastPathComponent.lastIndexOf(".");
  return dotIndex >= 0 ? lastPathComponent.slice(dotIndex + 1).toLowerCase() : "";
}

function displayNameForLink(link) {
  const cleanLink = link.split(/[?#]/)[0].split("|")[0];
  const lastPathComponent = cleanLink.split("/").pop() || cleanLink;
  const dotIndex = lastPathComponent.lastIndexOf(".");
  return dotIndex > 0 ? lastPathComponent.slice(0, dotIndex) : lastPathComponent;
}

function wikiLinksInLine(line) {
  const links = [];
  const pattern = /\[\[([^\]\n]+)\]\]/g;
  let match;

  while ((match = pattern.exec(line)) != null) {
    if (match.index > 0 && line[match.index - 1] === "!") continue;

    const separator = match[1].indexOf("|");
    const destination = (separator >= 0 ? match[1].slice(0, separator) : match[1]).trim();
    const alias = separator >= 0 ? match[1].slice(separator + 1).trim() : "";
    if (!destination) continue;

    links.push({
      from: match.index,
      to: match.index + match[0].length,
      target: destination,
      displayText: alias || wikiLinkDisplayText(destination)
    });
  }

  return links;
}

function wikiLinkDisplayText(destination) {
  const hashIndex = destination.indexOf("#");
  const file = hashIndex >= 0 ? destination.slice(0, hashIndex) : destination;
  const heading = hashIndex >= 0 ? destination.slice(hashIndex + 1) : "";
  const pieces = [];
  const fileName = displayNameForLink(file);
  if (fileName) pieces.push(fileName);
  if (heading) {
    pieces.push(...heading.split("#").filter(Boolean));
  }
  return pieces.join(" › ") || destination;
}

function markdownLinksInLine(line) {
  const links = [];
  let cursor = 0;

  while (cursor < line.length) {
    const from = line.indexOf("[", cursor);
    if (from < 0) break;
    cursor = from + 1;

    if ((from > 0 && line[from - 1] === "!") || line[from + 1] === "[") {
      continue;
    }

    const asciiLabelTo = line.indexOf("](", from + 1);
    if (asciiLabelTo < 0) continue;

    const destinationFrom = asciiLabelTo + 2;
    let parenthesisDepth = 0;
    let to = -1;
    for (let index = destinationFrom; index < line.length; index += 1) {
      const character = line[index];
      if (character === "\\") {
        index += 1;
      } else if (character === "(") {
        parenthesisDepth += 1;
      } else if (character === ")") {
        if (parenthesisDepth === 0) {
          to = index + 1;
          break;
        }
        parenthesisDepth -= 1;
      }
    }
    if (to < 0) continue;

    const label = line.slice(from + 1, asciiLabelTo);
    const target = normalizedMarkdownLinkTarget(line.slice(destinationFrom, to - 1));
    if (!label || !target) {
      cursor = to;
      continue;
    }

    links.push({from, to, target, displayText: label});
    cursor = to;
  }

  return links;
}

function normalizedMarkdownLinkTarget(rawTarget) {
  let target = rawTarget.trim();
  if (target.startsWith("<")) {
    const closingBracket = target.indexOf(">");
    if (closingBracket > 0) {
      return target.slice(1, closingBracket).trim();
    }
  }

  const title = /\s+(?:"[^"]*"|'[^']*'|\([^)]*\))\s*$/.exec(target);
  if (title) {
    target = target.slice(0, title.index).trim();
  }
  return target;
}

let linkPreviewSessionSequence = 0;

function installLinkPreviewHover(element, kind, target) {
  const sessionID = `link-preview-${++linkPreviewSessionSequence}`;
  const report = (phase) => {
    const rect = element.getBoundingClientRect();
    post({
      type: "linkPreviewHover",
      phase,
      sessionID,
      kind,
      target,
      anchor: {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height
      }
    });
  };
  element.addEventListener("mouseenter", () => report("entered"));
  element.addEventListener("mouseleave", () => report("exited"));
}

class WikiLinkWidget extends WidgetType {
  constructor(target, displayText) {
    super();
    this.target = target;
    this.displayText = displayText;
  }

  eq(other) {
    return other.target === this.target && other.displayText === this.displayText;
  }

  toDOM() {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "osn-wiki-link";
    button.textContent = this.displayText;
    button.setAttribute("aria-label", `Open note ${this.displayText}`);
    installLinkPreviewHover(button, "wiki", this.target);
    button.addEventListener("mousedown", (event) => event.preventDefault());
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      post({
        type: "wikiLink",
        target: this.target,
        newWindow: event.metaKey
      });
    });
    return button;
  }

  ignoreEvent() {
    return true;
  }
}

class MarkdownLinkWidget extends WidgetType {
  constructor(target, displayText) {
    super();
    this.target = target;
    this.displayText = displayText;
  }

  eq(other) {
    return other.target === this.target && other.displayText === this.displayText;
  }

  toDOM() {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "osn-markdown-link";
    button.textContent = this.displayText;
    button.setAttribute("aria-label", `Open link ${this.displayText}`);
    installLinkPreviewHover(button, "markdown", this.target);
    button.addEventListener("mousedown", (event) => event.preventDefault());
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      post({
        type: "markdownLink",
        target: this.target,
        newWindow: event.metaKey
      });
    });
    return button;
  }

  ignoreEvent() {
    return true;
  }
}

function mediaSourceForLink(link) {
  if (mediaEmbedSources.has(link)) return mediaEmbedSources.get(link);
  try {
    const decodedLink = decodeURIComponent(link);
    return mediaEmbedSources.get(decodedLink) || null;
  } catch {
    return null;
  }
}

function buildMarkdownDecorations(state) {
  const decorations = inlineSyntaxPresentationDecorations(state);

  for (let lineNumber = 1; lineNumber <= state.doc.lines; lineNumber += 1) {
    const line = state.doc.line(lineNumber);
    const media = imageEmbed(line.text);
    const mediaSource = media ? mediaSourceForLink(media.link) : null;
    if (media && mediaSource && !selectionTouchesLine(state, line)) {
      decorations.push(
        Decoration.replace({
          widget: new ImageEmbedWidget(media, mediaSource, line.from),
          block: true
        }).range(line.from, line.to)
      );
      continue;
    }

    for (const wikiLink of wikiLinksInLine(line.text)) {
      const from = line.from + wikiLink.from;
      const to = line.from + wikiLink.to;
      if (selectionTouchesToken(state, from, to)) {
        decorations.push(
          Decoration.mark({class: "osn-wiki-link-source"}).range(from, to)
        );
      } else {
        decorations.push(
          Decoration.replace({
            widget: new WikiLinkWidget(wikiLink.target, wikiLink.displayText),
            inclusive: false
          }).range(from, to)
        );
      }
    }

    for (const markdownLink of markdownLinksInLine(line.text)) {
      const from = line.from + markdownLink.from;
      const to = line.from + markdownLink.to;
      if (selectionTouchesToken(state, from, to)) {
        decorations.push(
          Decoration.mark({class: "osn-markdown-link-source"}).range(from, to)
        );
      } else {
        decorations.push(
          Decoration.replace({
            widget: new MarkdownLinkWidget(markdownLink.target, markdownLink.displayText),
            inclusive: false
          }).range(from, to)
        );
      }
    }

    const heading = atxHeadingMarker(line.text);
    if (heading) {
      decorations.push(
        Decoration.line({class: `osn-heading-line osn-heading-line-${heading.level}`}).range(line.from)
      );
      if (!selectionTouchesLine(state, line)) {
        decorations.push(
          Decoration.replace({inclusive: false}).range(
            line.from + heading.from,
            line.from + heading.to
          )
        );
      }
    }

    const task = taskMarker(line.text);
    if (task) {
      decorations.push(Decoration.line({class: "osn-list-line"}).range(line.from));
      decorations.push(
        Decoration.replace({inclusive: false}).range(
          line.from + task.listMarkerFrom,
          line.from + task.listMarkerTo
        )
      );

      const checkboxFrom = line.from + task.checkboxFrom;
      const checkboxTo = line.from + task.checkboxTo;
      if (!selectionTouchesToken(state, checkboxFrom, checkboxTo)) {
        decorations.push(
          Decoration.replace({
            widget: new TaskCheckboxWidget(task.checked, checkboxFrom),
            inclusive: false
          }).range(checkboxFrom, checkboxTo)
        );
      }
    } else {
      const bullet = bulletMarker(line.text);
      if (bullet) {
        decorations.push(Decoration.line({class: "osn-list-line"}).range(line.from));
        const markerFrom = line.from + bullet.from;
        const markerTo = line.from + bullet.to;
        const tokenFrom = line.from + bullet.tokenFrom;
        const tokenTo = line.from + bullet.tokenTo;
        if (!selectionTouchesToken(state, tokenFrom, tokenTo)) {
          decorations.push(
            Decoration.replace({
              widget: new BulletMarkerWidget(),
              inclusive: false
            }).range(markerFrom, markerTo)
          );
        } else {
          decorations.push(
            Decoration.mark({class: "list-bullet-source"}).range(markerFrom, markerTo)
          );
        }
      }
    }
  }

  return Decoration.set(decorations, true);
}

function insertListNewline(view) {
  const selection = view.state.selection.main;
  if (!selection.empty) return false;

  const line = view.state.doc.lineAt(selection.head);
  const marker = listItemMarker(line.text);
  if (!marker || selection.head < line.from + marker.markerTo) return false;

  const content = line.text.slice(marker.markerTo);
  if (content.trim().length === 0) {
    view.dispatch({
      changes: {
        from: line.from + marker.indentationLength,
        to: line.from + marker.markerTo,
        insert: ""
      },
      selection: {anchor: line.from + marker.indentationLength},
      scrollIntoView: true
    });
    view.focus();
    return true;
  }

  const insertion = `\n${marker.continuation}`;
  view.dispatch({
    changes: {from: selection.head, insert: insertion},
    selection: {anchor: selection.head + insertion.length},
    scrollIntoView: true
  });
  view.focus();
  return true;
}

function applyTextReplacement(view, from, to, text) {
  if (from !== to || textReplacements.size === 0 || !/^[\s.,!?;:]$/.test(text)) return false;

  const line = view.state.doc.lineAt(from);
  const prefix = view.state.sliceDoc(line.from, from);
  let matchedShortcut = null;
  for (const shortcut of textReplacements.keys()) {
    if (prefix.endsWith(shortcut) && (!matchedShortcut || shortcut.length > matchedShortcut.length)) {
      matchedShortcut = shortcut;
    }
  }
  if (!matchedShortcut) return false;

  const replacement = textReplacements.get(matchedShortcut);
  const replacementFrom = from - matchedShortcut.length;
  const insertion = `${replacement}${text}`;
  view.dispatch({
    changes: {from: replacementFrom, to: from, insert: insertion},
    selection: {anchor: replacementFrom + insertion.length},
    scrollIntoView: true,
    userEvent: "input.type"
  });
  return true;
}

const markdownDecorationField = StateField.define({
  create(state) {
    return buildMarkdownDecorations(state);
  },
  update(decorations, transaction) {
    if (
      transaction.docChanged ||
      transaction.selection ||
      transaction.effects.some((effect) => effect.is(refreshMediaEmbedsEffect))
    ) {
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
      key: "Enter",
      run(view) {
        return insertListNewline(view);
      }
    },
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
  if (readOnlyViews.has(view)) return view.state.doc.toString();
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
  return view.state.doc.toString();
}

function wrapSelection(view, wrapper) {
  const selection = view.state.selection.main;
  const documentText = view.state.doc.toString();

  if (selection.empty) {
    const markerBeforeCursor = documentText.slice(
      selection.from - wrapper.length,
      selection.from
    );
    const markerAfterCursor = documentText.slice(
      selection.from,
      selection.from + wrapper.length
    );

    if (markerBeforeCursor === wrapper && markerAfterCursor === wrapper) {
      const cursor = selection.from - wrapper.length;
      view.dispatch({
        changes: [
          {from: cursor, to: selection.from},
          {from: selection.from, to: selection.from + wrapper.length}
        ],
        selection: {anchor: cursor},
        scrollIntoView: true
      });
      view.focus();
      return;
    }

    const insertion = `${wrapper}${wrapper}`;
    const cursor = selection.from + wrapper.length;
    view.dispatch({
      changes: {from: selection.from, insert: insertion},
      selection: {anchor: cursor},
      scrollIntoView: true
    });
    view.focus();
    return;
  }

  const selected = documentText.slice(selection.from, selection.to);
  const selectedIncludesMarkers = selected.length >= wrapper.length * 2 &&
    selected.startsWith(wrapper) &&
    selected.endsWith(wrapper);

  if (selectedIncludesMarkers) {
    const unwrapped = selected.slice(wrapper.length, selected.length - wrapper.length);
    view.dispatch({
      changes: {from: selection.from, to: selection.to, insert: unwrapped},
      selection: {anchor: selection.from, head: selection.from + unwrapped.length},
      scrollIntoView: true
    });
    view.focus();
    return;
  }

  const markersImmediatelySurroundSelection =
    documentText.slice(selection.from - wrapper.length, selection.from) === wrapper &&
    documentText.slice(selection.to, selection.to + wrapper.length) === wrapper;

  if (markersImmediatelySurroundSelection) {
    view.dispatch({
      changes: [
        {from: selection.from - wrapper.length, to: selection.from},
        {from: selection.to, to: selection.to + wrapper.length}
      ],
      selection: {
        anchor: selection.from - wrapper.length,
        head: selection.to - wrapper.length
      },
      scrollIntoView: true
    });
    view.focus();
    return;
  }

  const replacement = `${wrapper}${selected}${wrapper}`;
  view.dispatch({
    changes: {from: selection.from, to: selection.to, insert: replacement},
    selection: {
      anchor: selection.from + wrapper.length,
      head: selection.from + wrapper.length + selected.length
    },
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

function insertMediaEmbedBlock(view, markdown) {
  if (readOnlyViews.has(view)) return view.state.doc.toString();
  const selection = view.state.selection.main;
  const documentText = view.state.doc.toString();
  const characterBefore = selection.from > 0 ? documentText[selection.from - 1] : "\n";
  const characterAfter = selection.to < documentText.length ? documentText[selection.to] : "\n";
  let insertion = markdown.trim();

  if (!insertion) return documentText;
  if (selection.from > 0 && characterBefore !== "\n") {
    insertion = `\n${insertion}`;
  }
  if (!insertion.endsWith("\n")) {
    insertion += "\n";
  }
  if (selection.to < documentText.length && characterAfter !== "\n") {
    insertion += "\n";
  }

  view.dispatch({
    changes: {from: selection.from, to: selection.to, insert: insertion},
    selection: {anchor: selection.from + insertion.length},
    scrollIntoView: true
  });
  view.focus();
  return view.state.doc.toString();
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
  const editingMode = new Compartment();
  const root = document.getElementById("editor");
  const state = EditorState.create({
    doc: "",
    extensions: [
      history(),
      markdown({addKeymap: false}),
      editingMode.of([
        EditorState.readOnly.of(false),
        EditorView.editable.of(true)
      ]),
      indentUnit.of(listIndent),
      syntaxHighlighting(markdownHighlightStyle),
      markdownDecorationField,
      EditorView.inputHandler.of((view, from, to, text) => applyTextReplacement(view, from, to, text)),
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
          if (readOnlyViews.has(view)) {
            event.preventDefault();
            return true;
          }
          if (hasMediaPaste(event)) {
            event.preventDefault();
            post({type: "pasteMedia"});
            return true;
          }
          return false;
        },
        drop(event, view) {
          if (readOnlyViews.has(view)) {
            event.preventDefault();
            return true;
          }
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
      editorTheme
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
    focusEnd() {
      const end = view.state.doc.length;
      view.dispatch({selection: {anchor: end}, scrollIntoView: true});
      view.focus();
    },
    focus() {
      view.focus();
    },
    applyCommand(command) {
      return applyCommand(view, command);
    },
    insertMediaEmbed(markdown) {
      return insertMediaEmbedBlock(view, markdown);
    },
    setMediaEmbeds(sources) {
      mediaEmbedSources = new Map(Object.entries(sources || {}));
      view.dispatch({effects: refreshMediaEmbedsEffect.of(null)});
    },
    setAppearance(scheme) {
      applyAppearance(view, scheme);
    },
    setReadOnly(isReadOnly) {
      const readOnly = Boolean(isReadOnly);
      if (readOnly) {
        readOnlyViews.add(view);
      } else {
        readOnlyViews.delete(view);
      }
      view.dispatch({
        effects: editingMode.reconfigure([
          EditorState.readOnly.of(readOnly),
          EditorView.editable.of(!readOnly)
        ])
      });
    }
  };

  if (window.__OSN_EDITOR_TESTING__ === true) {
    installEditorTestAdapter(view, {
      focusBlankEditorArea,
      applyTextReplacement,
      setTextReplacements(replacements) {
        textReplacements = new Map(Object.entries(replacements || {}));
      }
    });
  }

  post({type: "ready"});
}

installEditor();
