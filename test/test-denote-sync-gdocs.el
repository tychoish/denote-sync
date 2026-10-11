;;; test-denote-sync-gdocs.el --- ERT tests for Google Docs backend -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Code:

(require 'ert)
(require 'denote-sync)
(require 'denote-sync-gdocs)

(ert-deftest test-denote-sync-gdocs/extract-doc-id ()
  "Extract doc ID from Google Docs URLs and bare IDs."
  (let ((id "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"))
    (should (equal (denote-sync-gdocs--extract-doc-id
                    (format "https://docs.google.com/document/d/%s/edit" id))
                   id))
    (should (equal (denote-sync-gdocs--extract-doc-id
                    (format "https://docs.google.com/document/d/%s/edit?usp=sharing" id))
                   id))
    (should (equal (denote-sync-gdocs--extract-doc-id id) id))))

(ert-deftest test-denote-sync-gdocs/link-url ()
  "Generate canonical Google Docs edit URL."
  (should (equal (denote-sync-gdocs--link-url "doc123")
                 "https://docs.google.com/document/d/doc123/edit")))

(ert-deftest test-denote-sync-gdocs/format-parent ()
  "Format account and folder for parent display."
  (should (equal (denote-sync-gdocs--format-parent '("user@example.com" . "folder456"))
                 "account: user@example.com, folder: folder456"))
  (should (equal (denote-sync-gdocs--format-parent '(nil . nil))
                 "account: default, folder: root")))

(ert-deftest test-denote-sync-gdocs/add-parent ()
  "`denote-sync-gdocs-add-parent' adds an entry to `denote-sync-parent-registry'."
  (let ((denote-sync-parent-registry nil))
    (denote-sync-gdocs-add-parent "Team Docs" "team@example.com" "folder-xyz")
    (let ((entry (assoc "Team Docs" denote-sync-parent-registry)))
      (should entry)
      (should (eq (cadr entry) 'google-docs))
      (should (equal (car (cddr entry)) '("team@example.com" . "folder-xyz"))))))

(ert-deftest test-denote-sync-gdocs/run-auth-failure-actionable-error ()
  "Exit code 2 in gog CLI signals an actionable authentication error."
  (cl-letf (((symbol-function 'call-process)
             (lambda (&rest _args) 2)))
    (let ((err (should-error (denote-sync-gdocs--run '("docs" "info" "abc"))
                             :type 'user-error)))
      (should (string-match-p "gog authentication failed for account default: run .gog auth login."
                              (error-message-string err))))))

(ert-deftest test-denote-sync-gdocs/org-table-exports-as-gfm-pipe-table ()
  "Org table in Denote note exports to GFM pipe table, preserving round-trip structure."
  (let* ((org-body "| header1 | header2 |\n|---+---|\n| val1 | val2 |\n")
         (md (denote-sync--org-to-markdown org-body)))
    (should (string-match-p (regexp-quote "| header1 | header2 |") md))
    (should (string-match-p (regexp-quote "| val1    | val2    |") md))
    (should-not (string-match-p "<table" md))))

(ert-deftest test-denote-sync-gdocs/org-src-block-exports-as-fenced-code ()
  "Org src block in Denote note exports to fenced ``` code block."
  (let* ((org-body "#+begin_src python\ndef hello():\n    return 42\n#+end_src\n")
         (md (denote-sync--org-to-markdown org-body)))
    (should (string-match-p "```python" md))
    (should (string-match-p "def hello():" md))))

(ert-deftest test-denote-sync-gdocs/rewrite-denote-link-to-gdocs-url ()
  "Links to tracked Google Docs notes are rewritten to Google Docs URLs."
  (let* ((backend (alist-get 'google-docs denote-sync-backends))
         (temp-target (make-temp-file "target-note-" nil ".md"))
         (temp-source (make-temp-file "source-note-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-target
            (insert "---\ntitle: Target\nidentifier: \"20260101T000000\"\ngdoc_id: \"gdoc-target-123\"\n---\nTarget body"))
          (cl-letf (((symbol-function 'denote-get-path-by-id)
                     (lambda (id) (when (equal id "20260101T000000") temp-target))))
            (pcase-let ((`(,rewritten . ,dangling)
                         (denote-sync--rewrite-denote-links
                          "[Target Note](denote:20260101T000000)" temp-source backend)))
              (should (equal rewritten "[Target Note](https://docs.google.com/document/d/gdoc-target-123/edit)"))
              (should-not dangling))))
      (delete-file temp-target)
      (delete-file temp-source))))

(ert-deftest test-denote-sync-gdocs/mock-create-and-update ()
  "Create and update protocol functions invoke gog and record tracking metadata."
  (let* ((backend (alist-get 'google-docs denote-sync-backends))
         (temp-file (make-temp-file "gdoc-note-" nil ".md"))
         (denote-sync-cache-directory (make-temp-file "gdoc-cache-" t)))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\ntitle: My GDoc\nidentifier: \"20260105T120000\"\n---\nInitial content.\n"))
          ;; Mock run-json for create
          (cl-letf (((symbol-function 'denote-sync-gdocs--run-json)
                     (lambda (args &optional _account)
                       (cond
                        ((equal (take 2 args) '("docs" "create"))
                         '((file . ((id . "new-gdoc-id")
                                    (webViewLink . "https://docs.google.com/document/d/new-gdoc-id/edit")))))
                        ((equal (take 2 args) '("drive" "get"))
                         '((file . ((id . "new-gdoc-id")
                                    (name . "My GDoc")
                                    (createdTime . "2026-10-06T12:00:00.000Z")
                                    (modifiedTime . "2026-10-06T12:05:00.000Z")))))
                        (t (error "Unexpected args: %S" args)))))
                    ((symbol-function 'denote-sync-gdocs--run)
                     (lambda (&rest _args) (list 0 "" ""))))
            (let ((res (funcall (denote-sync-backend-create-fn backend)
                                temp-file '("test@example.com" . "folder1") "Initial content.")))
              (should (equal (plist-get res :id) "new-gdoc-id"))
              (should (equal (plist-get res :created-time) "2026-10-06T12:00:00.000Z"))
              (should (equal (plist-get res :edited-time) "2026-10-06T12:05:00.000Z"))
              (should (equal (denote-sync-frontmatter-get temp-file "sync-gdoc-account") "\"test@example.com\""))
              (should (equal (denote-sync-frontmatter-get temp-file "sync-gdoc-folder") "\"folder1\"")))))
      (delete-file temp-file)
      (delete-directory denote-sync-cache-directory t))))


(ert-deftest test-denote-sync-gdocs/file-account-fallback ()
  "File account falls back to `denote-sync-gdocs-default-account' when not in front matter."
  (let ((temp-file (make-temp-file "gdoc-acc-" nil ".md"))
        (denote-sync-gdocs-default-account "fallback@example.com"))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\ntitle: Note\n---\nBody\n"))
          (should (equal (denote-sync-gdocs--file-account temp-file) "fallback@example.com"))
          (with-temp-file temp-file
            (insert "---\ntitle: Note\ngdoc_account: \"explicit@example.com\"\n---\nBody\n"))
          (should (equal (denote-sync-gdocs--file-account temp-file) "explicit@example.com")))
      (delete-file temp-file))))

(ert-deftest test-denote-sync-gdocs/create-sets-default-account ()
  "`denote-sync-gdocs--create' stamps `denote-sync-gdocs-default-account' when parent account is nil."
  (let* ((backend (alist-get 'google-docs denote-sync-backends))
         (temp-file (make-temp-file "gdoc-create-acc-" nil ".md"))
         (denote-sync-gdocs-default-account "mydefault@example.com")
         (denote-sync-cache-directory (make-temp-file "gdoc-cache-" t)))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\ntitle: Default Account Note\n---\nContent\n"))
          (cl-letf (((symbol-function 'denote-sync-gdocs--run-json)
                     (lambda (args &optional account)
                       (should (equal account "mydefault@example.com"))
                       '((file . ((id . "acc-doc-123")
                                  (webViewLink . "https://docs.google.com/document/d/acc-doc-123/edit"))))))
                    ((symbol-function 'denote-sync-gdocs--run)
                     (lambda (&rest _args) (list 0 "" ""))))
            (funcall (denote-sync-backend-create-fn backend)
                     temp-file '(nil . nil) "Content")
            (should (equal (denote-sync-frontmatter-get temp-file "sync-gdoc-account")
                           "\"mydefault@example.com\""))))
      (delete-file temp-file)
      (delete-directory denote-sync-cache-directory t))))


(ert-deftest test-denote-sync-gdocs/single-account-fallback ()
  "File account automatically falls back to single authorized account if default is nil."
  (let ((temp-file (make-temp-file "gdoc-acc-" nil ".md"))
        (denote-sync-gdocs-default-account nil))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\ntitle: Single Acc Note\n---\nBody\n"))
          (cl-letf (((symbol-function 'denote-sync-gdocs--available-accounts)
                     (lambda () '("onlyone@example.com"))))
            (should (equal (denote-sync-gdocs--file-account temp-file) "onlyone@example.com"))))
      (delete-file temp-file))))

(ert-deftest test-denote-sync-gdocs/set-account ()
  "`denote-sync-gdocs-set-account' updates the note's front-matter."
  (let ((temp-file (make-temp-file "gdoc-set-acc-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\ntitle: Note\n---\nBody\n"))
          (denote-sync-gdocs-set-account temp-file "changed@example.com")
          (should (equal (denote-sync-frontmatter-get temp-file "sync-gdoc-account")
                         "\"changed@example.com\""))
          (should (equal (denote-sync-gdocs--file-account temp-file) "changed@example.com")))
      (delete-file temp-file))))

(ert-deftest test-denote-sync-gdocs/title-heading-round-trip ()
  "A title H1 is added on push and stripped on pull."
  (should (equal (denote-sync-gdocs--with-title "My Note" "body")
                 "# My Note\n\nbody"))
  (should (equal (denote-sync-gdocs--strip-title
                  "My Note" (denote-sync-gdocs--with-title "My Note" "body"))
                 "body")))

(ert-deftest test-denote-sync-gdocs/strip-title-only-matching-heading ()
  "Only a leading H1 equal to the title is stripped."
  (should (equal (denote-sync-gdocs--strip-title "A (b)" "# A (b)\nbody") "body"))
  (should (equal (denote-sync-gdocs--strip-title "T" "# Other\n\nbody")
                 "# Other\n\nbody"))
  (should (equal (denote-sync-gdocs--strip-title "T" "body\n# T\n") "body\n# T\n")))

(ert-deftest test-denote-sync-gdocs/title-heading-disabled ()
  "With `denote-sync-gdocs-insert-title' nil, content passes through."
  (let ((denote-sync-gdocs-insert-title nil))
    (should (equal (denote-sync-gdocs--with-title "T" "body") "body"))
    (should (equal (denote-sync-gdocs--strip-title "T" "# T\n\nbody") "# T\n\nbody"))))

(ert-deftest test-denote-sync-gdocs/title-heading-prompts-on-existing-h1 ()
  "An existing H1 triggers a prompt, remembered per file; fences are ignored."
  (let ((denote-sync-gdocs--double-title-answers (make-hash-table :test #'equal))
        (asked 0))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) (cl-incf asked) t)))
      (should (equal (denote-sync-gdocs--with-title "T" "```\n# not a heading\n```\nx" "f")
                     "# T\n\n```\n# not a heading\n```\nx"))
      (should (= asked 0))
      (let ((noninteractive nil))
        (should (equal (denote-sync-gdocs--with-title "T" "# H\nx" "f") "# T\n\n# H\nx"))
        (denote-sync-gdocs--with-title "T" "# H\nx" "f")
        (should (= asked 1))))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil))
              (noninteractive nil))
      (should (equal (denote-sync-gdocs--with-title "T" "# H\nx" "g") "# H\nx")))
    ;; Non-interactive: no prompt, no doubling.
    (should (equal (denote-sync-gdocs--with-title "T" "# H\nx" "h") "# H\nx"))))

(ert-deftest test-denote-sync-gdocs/add-account-drive-scope-file ()
  "`denote-sync-gdocs-add-account' passes --drive-scope=file by default."
  (let ((captured-args nil))
    (cl-letf (((symbol-function 'start-process)
               (lambda (_name _buffer program &rest args)
                 (setq captured-args (cons program args))
                 nil))
              ((symbol-function 'display-buffer) #'ignore))
      (denote-sync-gdocs-add-account "test@example.com")
      (should captured-args)
      (should (member "--drive-scope=file" captured-args))
      (should (member "--services=docs,drive" captured-args))
      (should (member "test@example.com" captured-args)))))

(ert-deftest test-denote-sync-gdocs/add-account-custom-scope ()
  "`denote-sync-gdocs-add-account' respects custom `denote-sync-gdocs-drive-scope'."
  (let ((captured-args nil)
        (denote-sync-gdocs-drive-scope "readonly"))
    (cl-letf (((symbol-function 'start-process)
               (lambda (_name _buffer program &rest args)
                 (setq captured-args (cons program args))
                 nil))
              ((symbol-function 'display-buffer) #'ignore))
      (denote-sync-gdocs-add-account "custom@example.com")
      (should captured-args)
      (should (member "--drive-scope=readonly" captured-args)))))

(ert-deftest test-denote-sync-gdocs/custom-credentials-variables ()
  "Client ID, Client Secret, and drive scope custom variables exist."
  (should (boundp 'denote-sync-gdocs-client-id))
  (should (boundp 'denote-sync-gdocs-client-secret))
  (should (boundp 'denote-sync-gdocs-drive-scope))
  (should (equal denote-sync-gdocs-drive-scope "file")))

(require 'denote-sync-bootstrap)

(ert-deftest test-denote-sync-gdocs/bootstrap-format-user-config ()
  "`denote-sync-bootstrap-format-user-config' generates valid Elisp configuration."
  (let* ((dest "~/.emacs.d/user/personal.el")
         (snippet (denote-sync-bootstrap-format-user-config "user@example.com" "mypass123" dest)))
    (should (string-match-p "Destination: ~/.emacs.d/user/personal.el" snippet))
    (should (string-match-p "(setenv \"GOG_KEYRING_PASSWORD\" \"mypass123\")" snippet))
    (should (string-match-p "(setq denote-sync-gdocs-default-account \"user@example.com\")" snippet))
    (should (string-match-p "(setq denote-sync-gdocs-drive-scope \"file\")" snippet))
    (should (string-match-p "add-to-list 'denote-sync-parent-registry" snippet))
    ;; Verify it can be read without syntax errors
    (with-temp-buffer
      (insert snippet)
      (goto-char (point-min))
      (should (read (current-buffer))))))

(ert-deftest test-denote-sync-gdocs/bootstrap-check-gog-found ()
  "`denote-sync-bootstrap-check-gog' returns path when executable is found."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (_) "/custom/bin/gog")))
    (should (equal (denote-sync-bootstrap-check-gog) "/custom/bin/gog"))))

(ert-deftest test-denote-sync-gdocs/bootstrap-check-gog-missing ()
  "`denote-sync-bootstrap-check-gog' signals user-error when executable is missing."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (_) nil)))
    (should-error (denote-sync-bootstrap-check-gog) :type 'user-error)))

(ert-deftest test-denote-sync-gdocs/bootstrap-configure-keyring ()
  "`denote-sync-bootstrap-configure-keyring' sets file keyring backend."
  (let ((captured nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (program _infile _destination _display &rest args)
                 (setq captured (cons program args))
                 0)))
      (denote-sync-bootstrap-configure-keyring)
      (should (equal captured (list denote-sync-gdocs-gog-executable "auth" "keyring" "file"))))))

(ert-deftest test-denote-sync-gdocs/bootstrap-configure-credentials ()
  "`denote-sync-bootstrap-configure-credentials' invokes gog with credentials file."
  (let ((temp-creds (make-temp-file "test-creds-" nil ".json"))
        (captured nil))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'call-process)
                     (lambda (program _infile _destination _display &rest args)
                       (setq captured (cons program args))
                       0)))
            (denote-sync-bootstrap-configure-credentials temp-creds)
            (should (equal (car captured) denote-sync-gdocs-gog-executable))
            (should (member "credentials" captured))
            (should (member "set" captured))
            (should (member "--insecure" captured))))
      (delete-file temp-creds))))

(provide 'test-denote-sync-gdocs)
;;; test-denote-sync-gdocs.el ends here
