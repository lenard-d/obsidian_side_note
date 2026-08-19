import {HighlightStyle} from "@codemirror/language";
import {EditorView} from "@codemirror/view";
import {tags} from "@lezer/highlight";

export const markdownHighlightStyle = HighlightStyle.define([
  {tag: tags.strong, fontWeight: "700"},
  {tag: tags.emphasis, fontStyle: "italic"},
  {tag: tags.monospace, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"},
  {tag: tags.heading, fontWeight: "inherit", fontSize: "inherit"}
]);

export const editorTheme = EditorView.theme({
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
  ".osn-inline-strong": {
    fontWeight: "700"
  },
  ".osn-inline-emphasis": {
    fontStyle: "italic"
  },
  ".osn-inline-highlight": {
    backgroundColor: "rgba(255, 214, 10, 0.32)",
    borderRadius: "2px"
  },
  ".osn-inline-code": {
    padding: "0 0.18em",
    borderRadius: "3px",
    backgroundColor: "rgba(255, 255, 255, 0.11)",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
  },
  ".cm-content .osn-wiki-link, .cm-content .osn-wiki-link-source, .cm-content .osn-markdown-link, .cm-content .osn-markdown-link-source": {
    color: "#409cff !important",
    textDecoration: "underline !important",
    textDecorationLine: "underline !important",
    textUnderlineOffset: "0.14em"
  },
  ".osn-wiki-link, .osn-markdown-link": {
    appearance: "none",
    display: "inline",
    margin: "0",
    padding: "0",
    border: "0",
    background: "transparent",
    font: "inherit",
    lineHeight: "inherit",
    textAlign: "left",
    whiteSpace: "normal",
    overflowWrap: "anywhere",
    cursor: "pointer"
  },
  ".cm-line.osn-list-line": {
    paddingLeft: "20px",
    textIndent: "-20px"
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
    position: "relative",
    display: "inline-block",
    width: "15px",
    height: "1cap",
    minWidth: "15px",
    margin: "0 5px 0 0",
    color: "rgb(255, 255, 255)",
    lineHeight: "1cap",
    verticalAlign: "baseline"
  },
  ".list-bullet-dot": {
    display: "block",
    position: "absolute",
    top: "50%",
    left: "50%",
    width: "5px",
    height: "5px",
    borderRadius: "50%",
    backgroundColor: "currentColor",
    transform: "translate(-50%, -50%)"
  },
  ".list-bullet-source": {
    boxSizing: "border-box",
    display: "inline-block",
    width: "20px",
    textIndent: "0"
  },
  ".image-embed": {
    boxSizing: "border-box",
    display: "block",
    maxWidth: "100%",
    margin: "6px 0",
    padding: "0",
    lineHeight: "0"
  },
  ".image-embed img": {
    display: "block",
    maxWidth: "100%",
    maxHeight: "260px",
    width: "auto",
    height: "auto",
    borderRadius: "7px",
    objectFit: "contain",
    backgroundColor: "rgba(255, 255, 255, 0.08)"
  }
});
