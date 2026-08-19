export function installEditorTestAdapter(view, helpers) {
  window.editorTest = {
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
    setSelectionRange(anchor, head) {
      const boundedAnchor = Math.max(0, Math.min(Number(anchor) || 0, view.state.doc.length));
      const boundedHead = Math.max(0, Math.min(Number(head) || 0, view.state.doc.length));
      view.dispatch({selection: {anchor: boundedAnchor, head: boundedHead}, scrollIntoView: true});
    },
    simulateBlankAreaMouseDown() {
      const event = {
        button: 0,
        target: view.scrollDOM,
        preventDefault() {}
      };
      return helpers.focusBlankEditorArea(view, event);
    },
    visibleText() {
      return view.contentDOM.innerText;
    },
    taskCheckboxCount() {
      return view.dom.querySelectorAll(".task-checkbox").length;
    },
    bulletMarkerCount() {
      return view.dom.querySelectorAll(".list-bullet-marker").length;
    },
    imageEmbedCount() {
      return view.dom.querySelectorAll(".image-embed img").length;
    },
    imageEmbedSources() {
      return [...view.dom.querySelectorAll(".image-embed img")].map((image) => image.getAttribute("src"));
    },
    firstTaskCheckboxMetrics() {
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
    selectAll() {
      view.dispatch({
        selection: {anchor: 0, head: view.state.doc.length},
        scrollIntoView: true
      });
    },
    taskCheckboxAlignment() {
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
    dispatchKey(key, modifiers = {}) {
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
    applyTextInput(text) {
      const selection = view.state.selection.main;
      return helpers.applyTextReplacement(view, selection.from, selection.to, text);
    },
    presentationStyles() {
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
          dotCount: bullet.querySelectorAll(".list-bullet-dot").length,
          color: getComputedStyle(bullet).color,
          display: getComputedStyle(bullet).display,
          height: getComputedStyle(bullet).height,
          alignItems: getComputedStyle(bullet).alignItems,
          justifyContent: getComputedStyle(bullet).justifyContent,
          verticalAlign: getComputedStyle(bullet).verticalAlign,
          usesCapHeight: CSS.supports("height", "1cap")
        } : null,
        scrollerLineHeight: scroller ? getComputedStyle(scroller).lineHeight : null,
        headingLines
      };
    },
    lineLayout() {
      return [...view.dom.querySelectorAll(".cm-line")].map((line) => {
        const style = getComputedStyle(line);
        return {
          text: line.innerText,
          isList: line.classList.contains("osn-list-line"),
          paddingLeft: style.paddingLeft,
          textIndent: style.textIndent,
          fontWeight: style.fontWeight
        };
      });
    },
    textColors() {
      return [...view.dom.querySelectorAll(".cm-content, .cm-content *")]
        .filter((element) => element.innerText && element.innerText.trim().length > 0)
        .map((element) => getComputedStyle(element).color);
    },
    setTextReplacements(replacements) {
      helpers.setTextReplacements(replacements);
    }
  };
}
