;;; mdwn.el --- Convert Markdown to Org using tree-sitter -*- lexical-binding: t; -*-

;; Author: sam kleinman <sam@tychoish.com>
;; Maintainer: sam kleinman <sam@tychoish.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines, text, wp
;; URL: https://github.com/tychoish/denote-sync

;;; Commentary:
;; `mdwn-to-org' converts a Markdown string to Org markup by walking the
;; parse tree produced by the `markdown' and `markdown-inline' tree-sitter
;; grammars.  There is no external-process or regexp fallback: when a
;; grammar is missing it signals a `user-error', or installs it first when
;; `mdwn-install-grammars' is non-nil.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'treesit)

(defgroup mdwn nil
  "Markdown to Org conversion."
  :group 'text
  :prefix "mdwn-")

(defcustom mdwn-install-grammars nil
  "When non-nil, install missing tree-sitter grammars on demand.
Installation needs network access, git and a C compiler."
  :type 'boolean
  :group 'mdwn)

(defconst mdwn--grammar-sources
  '((markdown "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
              "split_parser" "tree-sitter-markdown/src")
    (markdown-inline "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                     "split_parser" "tree-sitter-markdown-inline/src"))
  "`treesit-language-source-alist' entries for the Markdown grammars.")

(defun mdwn--ensure-grammars ()
  "Make sure the Markdown grammars are usable, or signal a `user-error'."
  (unless (and (fboundp 'treesit-available-p) (treesit-available-p))
    (user-error "mdwn: this Emacs was built without tree-sitter support"))
  (dolist (entry mdwn--grammar-sources)
    (let ((lang (car entry)))
      (unless (treesit-language-available-p lang)
        (if mdwn-install-grammars
            (let ((treesit-language-source-alist
                   (append mdwn--grammar-sources treesit-language-source-alist)))
              (treesit-install-language-grammar lang))
          (user-error "mdwn: tree-sitter grammar `%s' is not installed; run `M-x treesit-install-language-grammar' or set `mdwn-install-grammars'"
                      lang))
        (unless (treesit-language-available-p lang)
          (user-error "mdwn: installing the `%s' grammar failed" lang))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inline content

(defun mdwn--text (node)
  "Return NODE's source text."
  (treesit-node-text node t))

(defun mdwn--child-text (node type)
  "Return the text of NODE's first child of TYPE, or nil."
  (when-let* ((c (seq-find (lambda (n) (equal (treesit-node-type n) type))
                           (treesit-node-children node))))
    (mdwn--text c)))

(defun mdwn--inline-range (node start end)
  "Render the inline region START..END of NODE, converting child nodes."
  (let ((pos start) (out nil))
    (dolist (child (treesit-node-children node))
      (let ((cs (treesit-node-start child)) (ce (treesit-node-end child)))
        (when (and (>= cs start) (<= ce end) (>= cs pos))
          (push (buffer-substring-no-properties pos cs) out)
          (push (mdwn--inline-node child) out)
          (setq pos ce))))
    (push (buffer-substring-no-properties pos end) out)
    (apply #'concat (nreverse out))))

(defun mdwn--delimited (node mark)
  "Render emphasis-like NODE wrapped in MARK."
  (let* ((kids (treesit-node-children node))
         (delims (seq-filter (lambda (n) (member (treesit-node-type n)
                                                 '("emphasis_delimiter" "code_span_delimiter")))
                             kids))
         (half (/ (length delims) 2))
         (start (treesit-node-end (nth (1- half) delims)))
         (end (treesit-node-start (nth half (reverse (reverse delims))))))
    (concat mark (mdwn--inline-range node start end) mark)))

(defun mdwn--link-destination (node)
  "Return NODE's link destination without angle brackets."
  (let ((d (or (mdwn--child-text node "link_destination") "")))
    (if (string-match "\\`<\\(.*\\)>\\'" d) (match-string 1 d) d)))

(defun mdwn--inline-node (node)
  "Render the inline NODE as Org."
  (pcase (treesit-node-type node)
    ("strong_emphasis" (mdwn--delimited-strong node))
    ("emphasis" (mdwn--delimited node "/"))
    ("strikethrough"
     ;; the grammar nests `~~x~~' as strikethrough-in-strikethrough, so trim by text
     (let* ((txt (mdwn--text node))
            (lead (- (length txt) (length (string-trim-left txt "~+"))))
            (trail (- (length txt) (length (string-trim-right txt "~+")))))
       (concat "+" (mdwn--inline-range node (+ (treesit-node-start node) lead)
                                       (- (treesit-node-end node) trail))
               "+")))
    ("code_span"
     (let ((delims (seq-filter (lambda (n) (equal (treesit-node-type n) "code_span_delimiter"))
                               (treesit-node-children node))))
       (concat "~" (string-trim (buffer-substring-no-properties
                                 (treesit-node-end (car delims))
                                 (treesit-node-start (car (last delims)))))
               "~")))
    ("inline_link"
     (let ((text (when-let* ((lt (seq-find (lambda (n) (equal (treesit-node-type n) "link_text"))
                                           (treesit-node-children node))))
                   (mdwn--inline-range lt (treesit-node-start lt) (treesit-node-end lt)))))
       (format "[[%s][%s]]" (mdwn--link-destination node) (or text ""))))
    ("image" (format "[[%s]]" (mdwn--link-destination node)))
    ("uri_autolink" (format "[[%s]]" (string-trim (mdwn--text node) "<" ">")))
    ("backslash_escape" (substring (mdwn--text node) 1))
    ("hard_line_break" "\n")
    (_ (mdwn--text node))))

(defun mdwn--delimited-strong (node)
  "Render strong-emphasis NODE as Org bold."
  (mdwn--delimited node "*"))

(defun mdwn--inline (text)
  "Convert inline Markdown TEXT to Org."
  (if (string-empty-p text)
      ""
    (with-temp-buffer
      (insert text)
      (let ((root (treesit-parser-root-node (treesit-parser-create 'markdown-inline))))
        (mdwn--inline-range root (point-min) (point-max))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Blocks

(defun mdwn--indent (text prefix &optional first-prefix)
  "Indent TEXT's lines with PREFIX (FIRST-PREFIX for line one)."
  (let ((first t))
    (mapconcat (lambda (l)
                 (prog1 (if (string-empty-p l) l (concat (if first (or first-prefix prefix) prefix) l))
                   (setq first nil)))
               (split-string text "\n") "\n")))

(defun mdwn--children-text (node)
  "Return NODE's block children converted and separated by blank lines."
  (string-join (delq nil (mapcar #'mdwn--block (treesit-node-children node t))) "\n\n"))

(defun mdwn--paragraph (node)
  "Render paragraph NODE."
  (mdwn--inline (string-trim (mapconcat #'mdwn--text
                                        (seq-filter (lambda (n) (equal (treesit-node-type n) "inline"))
                                                    (treesit-node-children node))
                                        "\n"))))

(defun mdwn--heading-level (node)
  "Return the heading level of atx or setext heading NODE."
  (let ((marker (seq-find (lambda (n) (string-match-p "\\`\\(atx_h[1-6]_marker\\|setext_h[12]_underline\\)\\'"
                                                      (treesit-node-type n)))
                          (treesit-node-children node))))
    (pcase (treesit-node-type marker)
      ((rx "atx_h" (let n digit)) (string-to-number n))
      ((rx "setext_h" (let n digit)) (string-to-number n)))))

(defun mdwn--list-item (node)
  "Render list item NODE."
  (let* ((kids (treesit-node-children node t))
         (marker (car (treesit-node-children node)))
         (ordered (string-match-p "dot\\|parenthesis" (treesit-node-type marker)))
         (bullet (if ordered
                     (format "%d. " (string-to-number (mdwn--text marker)))
                   "- "))
         (task (seq-find (lambda (n) (string-match-p "task_list_marker" (treesit-node-type n))) kids))
         (checkbox (when task
                     (if (string-match-p "checked" (treesit-node-type task))
                         (if (string-match-p "unchecked" (treesit-node-type task)) "[ ] " "[X] ")
                       "")))
         (body (string-join
                (delq nil (mapcar (lambda (n)
                                    (unless (string-match-p "task_list_marker" (treesit-node-type n))
                                      (mdwn--block n)))
                                  kids))
                "\n")))
    (concat bullet (or checkbox "")
            (mdwn--indent body (make-string (length bullet) ?\s) ""))))

(defun mdwn--list (node)
  "Render list NODE."
  (mapconcat #'mdwn--list-item
             (seq-filter (lambda (c) (equal (treesit-node-type c) "list_item"))
                         (treesit-node-children node t))
             "\n"))

(defun mdwn--code-fence (node)
  "Render fenced code block NODE."
  (let ((lang (or (mdwn--child-text (or (seq-find (lambda (n) (equal (treesit-node-type n) "info_string"))
                                                  (treesit-node-children node))
                                        node)
                                    "language")
                  ""))
        (content (or (mdwn--child-text node "code_fence_content") "")))
    (format "#+begin_src%s\n%s\n#+end_src"
            (if (string-empty-p lang) "" (concat " " lang))
            (string-trim-right content "\n+"))))

(defun mdwn--table-row (row)
  "Render pipe-table ROW."
  (concat "| " (mapconcat (lambda (c) (mdwn--inline (string-trim (mdwn--text c))))
                          (seq-filter (lambda (n) (equal (treesit-node-type n) "pipe_table_cell"))
                                      (treesit-node-children row))
                          " | ")
          " |"))

(defun mdwn--table (node)
  "Render pipe-table NODE."
  (mapconcat (lambda (row)
               (if (equal (treesit-node-type row) "pipe_table_delimiter_row")
                   "|-"
                 (mdwn--table-row row)))
             (treesit-node-children node t) "\n"))

(defun mdwn--block (node)
  "Render block NODE as Org, or nil for nodes that produce no output."
  (pcase (treesit-node-type node)
    ((or "document" "section") (mdwn--children-text node))
    ("paragraph" (mdwn--paragraph node))
    ((or "atx_heading" "setext_heading")
     (let ((content (or (treesit-node-child-by-field-name node "heading_content") node)))
       (concat (make-string (mdwn--heading-level node) ?*) " "
               (mdwn--inline (string-trim (mdwn--text
                                           (or (seq-find (lambda (n) (equal (treesit-node-type n) "inline"))
                                                         (treesit-node-children content))
                                               content)))))))
    ("list" (mdwn--list node))
    ("block_quote" (format "#+begin_quote\n%s\n#+end_quote" (mdwn--children-text node)))
    ("fenced_code_block" (mdwn--code-fence node))
    ("indented_code_block" (format "#+begin_example\n%s\n#+end_example"
                                   (string-trim-right (mdwn--text node) "\n+")))
    ("pipe_table" (mdwn--table node))
    ("thematic_break" "-----")
    ("html_block" (format "#+begin_export html\n%s\n#+end_export" (string-trim (mdwn--text node))))
    ((or "link_reference_definition" "block_continuation" "block_quote_marker") nil)
    ((rx bos (or "list_marker" "task_list_marker")) nil)
    (_ (mdwn--text node))))

;;;###autoload
(defun mdwn-to-org (markdown)
  "Convert the Markdown string MARKDOWN to Org markup."
  (mdwn--ensure-grammars)
  (with-temp-buffer
    (insert markdown "\n")
    (let ((root (treesit-parser-root-node (treesit-parser-create 'markdown))))
      (string-trim (or (mdwn--block root) "")))))

(provide 'mdwn)
;;; mdwn.el ends here
