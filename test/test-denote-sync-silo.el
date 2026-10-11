;;; test-denote-sync-silo.el --- ERT tests for the silo backend -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Code:

(require 'ert)
(require 'denote-sync)
(require 'denote-sync-silo)

(defun test-silo--map (seq &rest opts)
  (apply #'denote-sync-silo--map-sequence seq opts))

(ert-deftest test-denote-sync-silo/map-sequence-numeric-rebase ()
  (let ((o '(:source-prefix "1=2" :target-prefix "5")))
    (should (equal (apply #'test-silo--map "1=2" o) "5"))
    (should (equal (apply #'test-silo--map "1=2=1" o) "5=1"))
    (should (equal (apply #'test-silo--map "1=2=2=3" o) "5=2=3"))
    (should-error (apply #'test-silo--map "1=3" o) :type 'user-error)))

(ert-deftest test-denote-sync-silo/map-sequence-identity-strip-scheme ()
  (should (equal (test-silo--map "1=2=1") "1=2=1"))
  (should (null (test-silo--map "1=2=1" :strip t)))
  (should (equal (test-silo--map "1=2=1" :scheme 'alphanumeric) "1b1"))
  (should (equal (test-silo--map "1b1" :scheme 'numeric) "1=2=1")))

(ert-deftest test-denote-sync-silo/map-sequence-alternation ()
  ;; root ends in digit -> root ends in letter: children flip digit/letter.
  (let ((o '(:source-prefix "1" :target-prefix "5a")))
    (should (equal (apply #'test-silo--map "1" o) "5a"))
    (should (equal (apply #'test-silo--map "1a" o) "5a1"))
    (should (equal (apply #'test-silo--map "1a1" o) "5a1a"))
    (should (equal (apply #'test-silo--map "1b2" o) "5a2b")))
  ;; letter -> digit
  (let ((o '(:source-prefix "1a" :target-prefix "7")))
    (should (equal (apply #'test-silo--map "1a2" o) "7b"))
    (should (equal (apply #'test-silo--map "1a2b" o) "7b2")))
  ;; same type: unchanged
  (should (equal (test-silo--map "1a2" :source-prefix "1" :target-prefix "9")
                 "9a2")))

(ert-deftest test-denote-sync-silo/split-front-matter ()
  (pcase-let ((`(,front . ,body)
               (denote-sync-silo--split-front-matter "+++\ntitle = \"x\"\n+++\n\nBody\n" 'markdown-toml)))
    (should (string-match-p "title" front))
    (should (equal body "Body")))
  (pcase-let ((`(,_ . ,body)
               (denote-sync-silo--split-front-matter "#+title: x\n#+date: y\n\nBody\n" 'org)))
    (should (equal body "Body")))
  (pcase-let ((`(,_ . ,body)
               (denote-sync-silo--split-front-matter "title: x\n---------------------------\n\nBody\n" 'text)))
    (should (equal body "Body"))))

(ert-deftest test-denote-sync-silo/replace-denote-ids ()
  (should (equal (denote-sync-silo--replace-denote-ids
                  "a [[denote:20260101T000000][x]] b denote:20260202T000000"
                  (lambda (id) (when (equal id "20260101T000000") "20990101T000000")))
                 "a [[denote:20990101T000000][x]] b denote:20260202T000000")))

(ert-deftest test-denote-sync-silo/replace-denote-ids-survives-matching-callback ()
  "A callback that runs its own regexp matches must not corrupt the replacement."
  (should (equal (denote-sync-silo--replace-denote-ids
                  "long prefix text denote:20260101T000000 and more text after"
                  (lambda (id)
                    (string-match "x" "x")
                    (concat id "9")))
                 "long prefix text denote:20260101T0000009 and more text after")))

(ert-deftest test-denote-sync-silo/prompts-use-annotated-completing-read-table-api ()
  "Interactive pickers hand ACR a candidate table, with the prompt as a keyword."
  (let ((denote-sync-silo-rules (list (list :name "R1" :source-prefix "1" :directory "/tmp/x/")))
        (denote-sync-parent-registry '(("P1" notion (data-source . "ds"))))
        seen)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt coll &rest _)
                 (push (all-completions "" coll) seen)
                 "R1")))
      (should (equal (eval (cadr (interactive-form 'denote-sync-silo-export-tree)) t)
                     '("R1"))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "P1")))
      (should (equal (car (denote-sync--acr-select-parent)) "P1")))))

;;; End-to-end

(defmacro test-silo--with-silos (&rest body)
  "Run BODY with `src' and `tgt' temp directories; `src' is the denote-directory."
  `(let* ((src (file-name-as-directory (make-temp-file "silo-src" t)))
          (tgt (file-name-as-directory (make-temp-file "silo-tgt" t)))
          (denote-directory src)
          (denote-sync-cache-directory (make-temp-file "silo-cache" t))
          (denote-sync-silo-rules nil)
          (denote-sync-parent-registry nil))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (or (string-prefix-p src (buffer-file-name b))
                        (string-prefix-p tgt (buffer-file-name b))))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory src t) (delete-directory tgt t))))

(defun test-silo--note (dir id sig title body &optional ext)
  (let* ((ext (or ext "md"))
         (file (expand-file-name
                (format "%s%s--%s__t.%s" id (if sig (concat "==" sig) "") title ext) dir)))
    (with-temp-file file
      (if (equal ext "org")
          (insert (format "#+title: %s\n#+date: [2026-10-09 Fri 10:00]\n#+filetags: :t:\n#+identifier: %s\n\n%s\n" title id body))
        (insert (format "---\ntitle: %S\ndate: 2026-10-09T10:00:00-04:00\ntags: [\"t\"]\nidentifier: %S\n---\n\n%s\n" title id body))))
    file))

(ert-deftest test-denote-sync-silo/single-push-and-update ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Hello"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt :target-format 'markdown-yaml) nil b)
     (let* ((id (denote-sync--get-id file b))
            (path (denote-sync-silo-with-target tgt (denote-get-path-by-id id))))
       (should (equal id "20261009T100000"))
       (should (file-exists-p path))
       (should (string-suffix-p ".md" path))
       (should (equal (denote-sync--body-without-front-matter path) "Hello"))
       (should (denote-sync--get-sync-hash file b))
       (should (eq (denote-sync--sync-state file b) 'unchanged))
       ;; local edit -> update
       (denote-sync--write-body file "Hello again")
       (should (eq (denote-sync--sync-state file b) 'local-only))
       (denote-sync-push file)
       (should (equal (denote-sync--body-without-front-matter path) "Hello again"))
       (should (eq (denote-sync--sync-state file b) 'unchanged))))))

(ert-deftest test-denote-sync-silo/conflict-detection ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Hello"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt) nil b)
     (let ((path (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000"))))
       (sleep-for 0.01)
       (with-temp-file path (insert-file-contents path)
                       (goto-char (point-max)) (insert "remote edit\n"))
       (should (eq (denote-sync--sync-state file b) 'remote-only))
       (denote-sync--write-body file "local edit")
       (should (eq (denote-sync--sync-state file b) 'both-changed))
       (denote-sync-push file)
       (should (denote-sync--get-conflict file b))))))

(ert-deftest test-denote-sync-silo/org-to-markdown-and-id-collision ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Some *bold* text" "org"))
          (b (denote-sync-get-backend 'silo)))
     ;; pre-existing different note with the same id in the target
     (test-silo--note tgt "20261009T100000" nil "other" "x")
     (cl-letf (((symbol-function 'denote-sync-frontmatter-set)
                (lambda (f k v)
                  (with-temp-buffer
                    (insert-file-contents f)
                    (goto-char (point-min))
                    (re-search-forward "^$" nil t)
                    (insert k ": " (format "%S" v) "\n")
                    (write-region nil nil f))))
               ((symbol-function 'denote-sync--record-synced-content) #'ignore))
       (let ((result (denote-sync-silo--create
                      file (list :directory tgt :target-format 'markdown-yaml)
                      (car (denote-sync--export-body file b)))))
         (should-not (equal (plist-get result :id) "20261009T100000"))
         (let ((path (plist-get result :url)))
           (should (string-suffix-p ".md" path))
           (should (string-match-p "\\*\\*bold\\*\\*\\|_bold_\\|\\*bold\\*"
                                   (denote-sync--body-without-front-matter path)))))))))

(ert-deftest test-denote-sync-silo/markdown-to-org-target ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" "1" "alpha" "# Head\n\nText"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt :target-format 'org) nil b)
     (let ((path (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000"))))
       (should (string-suffix-p ".org" path))
       (should (equal (denote-retrieve-filename-signature path) "1"))
       (should (string-match-p "^\\* Head" (denote-sync--body-without-front-matter path)))
       ;; remote body comes back canonical; pull across formats is refused
       (should-error (denote-sync-pull nil file b t) :type 'user-error)))))

(ert-deftest test-denote-sync-silo/tree-export-rewrites-links ()
  (test-silo--with-silos
   (let* ((root (test-silo--note src "20261009T100000" "1=2" "alpha"
                                 "See [Beta](denote:20261009T100500) and [Out](denote:20250101T000000)"))
          (child (test-silo--note src "20261009T100500" "1=2=1" "beta" "Child body"))
          (child2 (test-silo--note src "20261009T100600" "1=2=2" "gamma" "Second"))
          (_other (test-silo--note src "20261009T100700" "1=3" "delta" "Not in tree"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-silo-add-rule :name "pub" :source-prefix "1=2" :target-directory tgt
                                :target-prefix "5" :target-format 'markdown-yaml)
     (should (assoc "pub" denote-sync-parent-registry))
     (denote-sync-silo-export-tree "pub")
     (let ((sigs (mapcar (lambda (f) (denote-retrieve-filename-signature f))
                         (denote-sync-silo-with-target tgt (denote-directory-files)))))
       (should (equal (sort sigs #'string<) '("5" "5=1" "5=2"))))
     (should (= 3 (length (denote-sync-silo-with-target tgt (denote-directory-files)))))
     (let* ((tpath (denote-sync-silo-with-target tgt (denote-get-path-by-id (denote-sync--get-id root b))))
            (body (denote-sync--body-without-front-matter tpath)))
       (should (string-match-p (regexp-quote "[Beta](denote:20261009T100500)") body))
       (should-not (string-match-p "20250101T000000" body)))
     (should (denote-sync--get-id child2 b))
     ;; idempotent
     (denote-sync-silo-export-tree "pub")
     (should (eq (denote-sync--sync-state child b) 'unchanged))
     (should (= 3 (length (denote-sync-silo-with-target tgt (denote-directory-files))))))))

(ert-deftest test-denote-sync-silo/tree-export-target-parent-and-fresh-ids ()
  (test-silo--with-silos
   (let ((root (test-silo--note src "20261009T100000" "1" "alpha" "A"))
         (b (denote-sync-get-backend 'silo)))
     (test-silo--note src "20261009T100500" "1=1" "beta" "B")
     ;; target already has note 5 and 5=1, plus an id collision with the root
     (test-silo--note tgt "20261009T100000" "5" "existing" "E")
     (test-silo--note tgt "20250101T000000" "5=1" "existing child" "E")
     (denote-sync-silo-add-rule :name "sub" :source-prefix "1" :target-directory tgt
                                :target-parent "5" :target-format 'same)
     (denote-sync-silo-export-tree "sub")
     (let ((sigs (sort (mapcar #'denote-retrieve-filename-signature
                               (denote-sync-silo-with-target tgt (denote-directory-files)))
                       #'string<)))
       (should (equal sigs '("5" "5=1" "5=2" "5=2=1"))))
     (should-not (equal (denote-sync--get-id root b) "20261009T100000"))
     ;; re-running keeps the allocated slot
     (denote-sync-silo-export-tree "sub")
     (should (= 4 (length (denote-sync-silo-with-target tgt (denote-directory-files))))))))

(ert-deftest test-denote-sync-silo/refresh-pulls-target-edit ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Hello"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt) nil b)
     (let ((path (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000"))))
       (sleep-for 0.01)
       (let ((text (with-temp-buffer (insert-file-contents path) (buffer-string))))
         (with-temp-file path (insert (string-replace "Hello" "Edited remotely" text))))
       (should (eq (denote-sync--sync-state file b) 'remote-only))
       (denote-sync-pull nil file b)
       (should (equal (denote-sync--body-without-front-matter file) "Edited remotely"))
       (should (eq (denote-sync--sync-state file b) 'unchanged))))))

(ert-deftest test-denote-sync-silo/visiting-buffer-with-unsaved-edits-is-protected ()
  (test-silo--with-silos
   (let ((path (test-silo--note tgt "20261009T100000" nil "alpha" "x")))
     (with-current-buffer (find-file-noselect path)
       (insert "unsaved"))
     (should-error (denote-sync-silo--write-file path "new") :type 'user-error))))

(ert-deftest test-denote-sync-silo/rewrite-links-nil-keeps-org-links ()
  (test-silo--with-silos
   (let ((file (test-silo--note src "20261009T100000" "1" "alpha"
                                "See [[denote:20261009T100500][Beta]]" "org")))
     (test-silo--note src "20261009T100500" "1=1" "beta" "B" "org")
     (denote-sync-silo-add-rule :name "raw" :source-prefix "1" :target-directory tgt
                                :target-prefix "9" :target-format 'org :rewrite-links nil)
     (cl-letf (((symbol-function 'denote-sync-frontmatter-set) #'ignore)
               ((symbol-function 'denote-sync--record-synced-content) #'ignore))
       (let* ((entry (cdr (assoc file (denote-sync-silo--plan-tree (denote-sync-silo--find-rule "raw")))))
              (denote-sync-silo--directory tgt)
              (denote-sync-silo--plan (make-hash-table :test #'equal)))
         (puthash "20261009T100000" entry denote-sync-silo--plan)
         (let* ((r (denote-sync-silo--update file (plist-get entry :id) "" nil))
                (_ r))
           (should (string-match-p (regexp-quote "denote:20261009T100500")
                                   (denote-sync--body-without-front-matter
                                    (plist-get r :url))))))))))

(ert-deftest test-denote-sync-silo/async-callback-invoked-once ()
  (let ((calls 0))
    (should-error
     (denote-sync-silo--async-fetch-remote
      "20260101T000000" (lambda (&rest _) (cl-incf calls) (error "boom")))
     )
    (should (= calls 1))))

(ert-deftest test-denote-sync-silo/split-front-matter-rejects-malformed ()
  (should-error (denote-sync-silo--split-front-matter "---\ntitle: x\nBody" 'markdown-yaml) :type 'user-error)
  (should-error (denote-sync-silo--split-front-matter "no front matter" 'markdown-yaml) :type 'user-error)
  (should-error (denote-sync-silo--split-front-matter "Body\n" 'org) :type 'user-error)
  (should-error (denote-sync-silo--split-front-matter "Body\n" 'text) :type 'user-error)
  (should-error (denote-sync-silo--split-front-matter "x" 'bogus) :type 'user-error))

(ert-deftest test-denote-sync-silo/org-source-tracks-with-keyword-properties ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" "1" "alpha" "Some /em/ text" "org"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt :target-format 'same) nil b)
     (should (equal (denote-sync--get-id file b) "20261009T100000"))
     (should (equal (denote-sync-frontmatter-get file "sync-silo-id") "20261009T100000"))
     (with-temp-buffer (insert-file-contents file)
                       (should-not (string-match-p "^---" (buffer-string))))
     (let ((path (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000"))))
       (should (string-suffix-p ".org" path))
       (should (equal (denote-sync--body-without-front-matter path) "Some /em/ text")))
     (should (eq (denote-sync--sync-state file b) 'unchanged)))))

(ert-deftest test-denote-sync-silo/toml-and-text-targets ()
  (test-silo--with-silos
   (let ((b (denote-sync-get-backend 'silo))
         (f1 (test-silo--note src "20261009T100000" nil "alpha" "One"))
         (f2 (test-silo--note src "20261009T100100" nil "beta" "Two")))
     (denote-sync-push f1 (list :directory tgt :target-format 'markdown-toml) nil b)
     (denote-sync-push f2 (list :directory tgt :target-format 'text) nil b)
     (let ((p1 (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000")))
           (p2 (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100100"))))
       (should (eq (denote-filetype-heuristics p1) 'markdown-toml))
       (should (string-suffix-p ".txt" p2))
       (should (equal (cddr (denote-sync-silo--read-note p1)) "One"))
       (should (equal (cddr (denote-sync-silo--read-note p2)) "Two"))
       (should (equal (plist-get (denote-sync-silo--fetch-remote "20261009T100000" t) :body) "One"))
       (should (equal (plist-get (denote-sync-silo--fetch-remote "20261009T100100" t) :body) "Two"))))))

(ert-deftest test-denote-sync-silo/overlapping-directories-are-refused ()
  (test-silo--with-silos
   (let ((file (test-silo--note src "20261009T100000" nil "alpha" "x"))
         (sub (expand-file-name "sub/" src)))
     (make-directory sub)
     (should-error (denote-sync-push file (list :directory sub) nil (denote-sync-get-backend 'silo))
                   :type 'user-error)
     (should-error (denote-sync-push file (list :directory src) nil (denote-sync-get-backend 'silo))
                   :type 'user-error)
     (should-not (denote-sync--get-id file (denote-sync-get-backend 'silo))))))

(ert-deftest test-denote-sync-silo/overlap-can-be-allowed ()
  (test-silo--with-silos
   (let ((file (test-silo--note src "20261009T100000" nil "alpha" "x"))
         (sub (expand-file-name "sub/" src))
         (denote-sync-silo-allow-overlap t))
     (make-directory sub)
     (denote-sync-push file (list :directory sub) nil (denote-sync-get-backend 'silo))
     (should (denote-sync--get-id file (denote-sync-get-backend 'silo))))))

(ert-deftest test-denote-sync-silo/preflight-reports-all-problems-before-writing ()
  (test-silo--with-silos
   (let ((bad (expand-file-name "20261009T100500==1=1--beta__t.md" src)))
     (test-silo--note src "20261009T100000" "1" "alpha" "A")
     (with-temp-file bad (insert "no front matter here\n"))
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt
                                :target-prefix "5")
     (let ((err (should-error (denote-sync-silo-export-tree "p") :type 'user-error)))
       (should (string-match-p "Malformed" (cadr err))))
     (should-not (denote-sync-silo-with-target tgt (denote-directory-files)))
     (should-not (denote-sync-frontmatter-get
                  (expand-file-name "20261009T100000==1--alpha__t.md" src) "sync-silo-id")))))

(ert-deftest test-denote-sync-silo/failed-push-unseeds-remaining-notes ()
  (test-silo--with-silos
   (let ((f1 (test-silo--note src "20261009T100000" "1" "alpha" "A"))
         (f2 (test-silo--note src "20261009T100500" "1=1" "beta" "B"))
         (real (symbol-function 'denote-sync-push))
         (b (denote-sync-get-backend 'silo)))
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt
                                :target-prefix "5")
     (cl-letf (((symbol-function 'denote-sync-push)
                (lambda (file &rest args)
                  (if (equal file f2) (error "boom") (apply real file args)))))
       (should-error (denote-sync-silo-export-tree "p")))
     (should (denote-sync--get-id f1 b))
     (should-not (denote-sync--get-id f2 b)))))

(ert-deftest test-denote-sync-silo/rule-change-moves-existing-target ()
  (test-silo--with-silos
   (let ((root (test-silo--note src "20261009T100000" "1" "alpha" "A"))
         (b (denote-sync-get-backend 'silo)))
     (test-silo--note src "20261009T100500" "1=1" "beta" "B")
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt :target-prefix "5")
     (denote-sync-silo-export-tree "p")
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt :target-prefix "7")
     (denote-sync-silo-export-tree "p")
     (let ((sigs (sort (mapcar #'denote-retrieve-filename-signature
                               (denote-sync-silo-with-target tgt (denote-directory-files)))
                       #'string<)))
       (should (equal sigs '("7" "7=1"))))
     (should (equal (denote-sync--get-id root b) "20261009T100000")))))

(ert-deftest test-denote-sync-silo/missing-root-with-target-parent-is-refused ()
  (test-silo--with-silos
   (let ((root (test-silo--note src "20261009T100000" "1" "alpha" "A")))
     (test-silo--note src "20261009T100500" "1=1" "beta" "B")
     (test-silo--note tgt "20250101T000000" "5" "p" "P")
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt :target-parent "5")
     (denote-sync-silo-export-tree "p")
     (delete-file (denote-sync-silo-with-target tgt (denote-get-path-by-id (denote-sync--get-id root (denote-sync-get-backend 'silo)))))
     (should-error (denote-sync-silo-export-tree "p") :type 'user-error))))

(ert-deftest test-denote-sync-silo/import-creates-tracked-note ()
  (test-silo--with-silos
   (let ((denote-sync-silo-default-directory tgt)
         (denote-file-type 'markdown-yaml)
         (b (denote-sync-get-backend 'silo)))
     (test-silo--note tgt "20260101T000000" "3" "from-silo" "See [x](denote:20260101T000000)")
     (let ((new (denote-sync-silo--import "20260101T000000")))
       (should (file-exists-p new))
       (should (string-prefix-p src new))
       (should (equal (denote-retrieve-filename-signature new) "3"))
       (should (equal (denote-sync--get-id new b) "20260101T000000"))
       (should (equal (denote-sync-frontmatter-get new "sync-silo-dir") (format "%S" (expand-file-name tgt))))
       (should (eq (denote-sync--sync-state new b) 'unchanged))))))

(provide 'test-denote-sync-silo)
;;; test-denote-sync-silo.el ends here

(ert-deftest test-denote-sync-silo/map-keywords ()
  (should (equal (denote-sync-silo--map-keywords '("a" "b") nil) '("a" "b")))
  (should (equal (denote-sync-silo--map-keywords '("a" "b") '(:tags ("x"))) '("x")))
  (should (equal (denote-sync-silo--map-keywords '("a" "b") '(:tags nil :add-tags ("z"))) '("z")))
  (should (equal (denote-sync-silo--map-keywords '("a" "b") '(:remove-tags ("a") :add-tags ("c" "b")))
                 '("b" "c")))
  (should (equal (denote-sync-silo--map-keywords '("a") `(:tags ,(lambda (k) (append k '("f")))))
                 '("a" "f"))))

(ert-deftest test-denote-sync-silo/tree-export-changes-tags-and-moves-on-rule-change ()
  (test-silo--with-silos
   (test-silo--note src "20261009T100000" "1" "alpha" "A")
   (let ((tags (lambda ()
                 (mapcar #'denote-extract-keywords-from-path
                         (denote-sync-silo-with-target tgt (denote-directory-files))))))
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt
                                :add-tags '("pub") :remove-tags '("t"))
     (denote-sync-silo-export-tree "p")
     (should (equal (funcall tags) '(("pub"))))
     (denote-sync-silo-add-rule :name "p" :source-prefix "1" :target-directory tgt
                                :tags '("only"))
     (denote-sync-silo-export-tree "p")
     (should (equal (funcall tags) '(("only"))))
     (should (= 1 (length (denote-sync-silo-with-target tgt (denote-directory-files))))))))

;;; Deferred rendering

(ert-deftest test-denote-sync-silo/org-to-org-push-skips-markdown-export ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261011T100000" nil "alpha" "Some *bold* text" "org"))
          (b (denote-sync-get-backend 'silo))
          (exports 0))
     (cl-letf* ((orig (symbol-function 'denote-sync--org-to-markdown))
                ((symbol-function 'denote-sync--org-to-markdown)
                 (lambda (&rest args) (cl-incf exports) (apply orig args))))
       (denote-sync-push file (list :directory tgt :target-format 'org) nil b)
       (should (= exports 0))
       (let ((path (denote-sync-silo-with-target tgt
                     (denote-get-path-by-id (denote-sync--get-id file b)))))
         (should (string-suffix-p ".org" path))
         (should (equal (denote-sync--body-without-front-matter path) "Some *bold* text")))
       ;; a status check needs no export either
       (should (eq (denote-sync--sync-state file b) 'unchanged))
       (should (= exports 0))))))

(ert-deftest test-denote-sync-silo/org-to-markdown-push-still-exports ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261011T100000" nil "alpha" "Some *bold* text" "org"))
          (b (denote-sync-get-backend 'silo)))
     (denote-sync-push file (list :directory tgt :target-format 'markdown-yaml) nil b)
     (let ((path (denote-sync-silo-with-target tgt
                   (denote-get-path-by-id (denote-sync--get-id file b)))))
       (should (string-suffix-p ".md" path))
       (should (string-match-p "\\*\\*bold\\*\\*\\|_bold_\\|\\*bold\\*"
                               (denote-sync--body-without-front-matter path)))))))

(ert-deftest test-denote-sync-silo/deferred-render-reports-dangling-links ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261011T100000" nil "alpha"
                                 "See [[denote:20261011T999999][ghost]]" "org"))
          (b (denote-sync-get-backend 'silo))
          (result (denote-sync--export-body file b)))
     (should (null (car result)))
     (should (equal (mapcar (lambda (d) (list (nth 1 d) (nth 2 d))) (cdr result))
                    '(("20261011T999999" missing-file)))))))

(ert-deftest test-denote-sync-silo/deferred-record-drops-stale-cache ()
  (let ((denote-sync-cache-directory (make-temp-file "dsync-cache-" t))
        (file (make-temp-file "dsync-rec-" nil ".org"))
        (b (denote-sync-get-backend 'silo)))
    (with-temp-file file (insert "#+title: x\n#+identifier: 20261011T100000\n\nBody\n"))
    (denote-sync--cache-write 'silo "id-1" "old markdown ancestor")
    (denote-sync--record-synced-content file b "id-1" nil)
    (should-not (denote-sync--cache-read 'silo "id-1"))
    (should (equal (denote-sync--get-sync-hash file b) (denote-sync--change-key file b)))))

(ert-deftest test-denote-sync-silo/push-and-pull-report-up-to-date-and-force ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Hello"))
          (b (denote-sync-get-backend 'silo))
          (path-fn (lambda () (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000")))))
     (denote-sync-push file (list :directory tgt) nil b)
     (should (eq denote-sync--push-outcome 'pushed))
     ;; nothing changed: skipped, and says so
     (denote-sync-push file nil nil b)
     (should (eq denote-sync--push-outcome 'in-sync))
     (let ((msg nil))
       (cl-letf (((symbol-function 'message) (lambda (f &rest a) (setq msg (apply #'format f a)))))
         (denote-sync-pull nil file b))
       (should (string-match-p "already up to date" msg)))
     ;; force overrides
     (denote-sync-push file nil t b)
     (should (eq denote-sync--push-outcome 'pushed))
     ;; both sides edited: no write, reported as a conflict, force overwrites
     (sleep-for 0.01)
     (let ((text (with-temp-buffer (insert-file-contents (funcall path-fn)) (buffer-string))))
       (with-temp-file (funcall path-fn) (insert (string-replace "Hello" "Remote" text))))
     (denote-sync--write-body file "Local")
     (denote-sync-push file nil nil b)
     (should (eq denote-sync--push-outcome 'conflict))
     ;; interactively, a conflict offers the merge session
     (let ((noninteractive nil) merged)
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                 ((symbol-function 'denote-sync-resolve-conflict)
                  (lambda (f bk) (setq merged (list f bk)))))
         (denote-sync-push file nil nil b))
       (should (equal merged (list file b))))
     (should (string-match-p "Remote" (denote-sync--body-without-front-matter (funcall path-fn))))
     ;; pull is conflict guarded too: it offers the merge, not an overwrite
     (let ((noninteractive nil) merged)
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                 ((symbol-function 'denote-sync-resolve-conflict)
                  (lambda (f bk) (setq merged (list f bk)))))
         (denote-sync-pull nil file b))
       (should (equal merged (list file b)))
       (should (equal (denote-sync--body-without-front-matter file) "Local")))
     (denote-sync-pull nil file b t)
     (should (equal (denote-sync--body-without-front-matter file) "Remote"))
     (denote-sync--write-body file "Local")
     (denote-sync-push file nil t b)
     (should (string-match-p "Local" (denote-sync--body-without-front-matter (funcall path-fn)))))))

(ert-deftest test-denote-sync-silo/one-sided-changes-are-guarded-both-ways ()
  (test-silo--with-silos
   (let* ((file (test-silo--note src "20261009T100000" nil "alpha" "Hello"))
          (b (denote-sync-get-backend 'silo))
          (path-fn (lambda () (denote-sync-silo-with-target tgt (denote-get-path-by-id "20261009T100000")))))
     (denote-sync-push file (list :directory tgt) nil b)
     ;; remote-only: a push would discard the remote edit
     (sleep-for 0.01)
     (let ((text (with-temp-buffer (insert-file-contents (funcall path-fn)) (buffer-string))))
       (with-temp-file (funcall path-fn) (insert (string-replace "Hello" "Remote" text))))
     (denote-sync-push file nil nil b)
     (should (eq denote-sync--push-outcome 'remote-changed))
     (should (string-match-p "Remote" (denote-sync--body-without-front-matter (funcall path-fn))))
     (denote-sync-pull nil file b)
     (should (equal (denote-sync--body-without-front-matter file) "Remote"))
     ;; local-only: a pull would discard the local edit
     (denote-sync--write-body file "Local")
     (denote-sync-pull nil file b)
     (should (equal (denote-sync--body-without-front-matter file) "Local"))
     (denote-sync-pull nil file b t)
     (should (equal (denote-sync--body-without-front-matter file) "Remote"))
     (denote-sync--write-body file "Local")
     (denote-sync-push file nil nil b)
     (should (eq denote-sync--push-outcome 'pushed)))))
