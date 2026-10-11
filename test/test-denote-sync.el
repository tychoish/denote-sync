;;; test-denote-sync.el --- ERT tests for denote-sync generic engine -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Code:

(require 'ert)
(require 'denote-sync)

(defconst test-denote-sync--fixture-empty-frontmatter
  "---
title: \"Test Note\"
date: 2026-01-05T17:52:00-05:00
tags: [\"test\"]
identifier: \"20260105T175200\"
---

Hello world body.
")

(ert-deftest test-denote-sync/backend-registration-and-retrieval ()
  "Backends can be registered, retrieved by name, and listed."
  (let ((dummy (denote-sync-backend-create :name 'test-backend :frontmatter-prefix "test")))
    (denote-sync-register-backend dummy)
    (should (eq (denote-sync-get-backend 'test-backend) dummy))
    (should (memq dummy (denote-sync-registered-backends)))
    (setq denote-sync-backends (assq-delete-all 'test-backend denote-sync-backends))))

(ert-deftest test-denote-sync/org-frontmatter-get-and-set ()
  "Org notes keep sync properties as #+KEY: lines, never a YAML block."
  (let ((file (make-temp-file "dsync-org" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+title: T\n#+identifier: 20260101T000000\n\nBody\n"))
          (denote-sync-frontmatter-set file "sync-silo-id" "20990101T000000")
          (should (equal (denote-sync-frontmatter-get file "sync-silo-id") "20990101T000000"))
          (denote-sync-frontmatter-set file "sync-silo-id" "20990202T000000")
          (denote-sync-frontmatter-set file "sync-silo-edited" t)
          (should (equal (denote-sync-frontmatter-get file "sync-silo-id") "20990202T000000"))
          (should (equal (denote-sync-frontmatter-get file "sync-silo-edited") "t"))
          (with-temp-buffer
            (insert-file-contents file)
            (should-not (string-match-p "^---" (buffer-string)))
            (should (string-match-p "\n\nBody\n" (buffer-string)))
            (should (= 1 (how-many "^#\\+sync-silo-id:" (point-min))))))
      (when-let* ((b (find-buffer-visiting file))) (kill-buffer b))
      (delete-file file))))

(ert-deftest test-denote-sync/export-title-prefers-front-matter ()
  (let ((dir (file-name-as-directory (make-temp-file "dsync-title" t))))
    (unwind-protect
        (let ((file (expand-file-name "20260101T000000--my-title__t.md" dir))
              (bare (expand-file-name "20260101T000001--only-slug__t.md" dir)))
          (with-temp-file file
            (insert "---\ntitle: \"My Title, Properly Cased\"\nidentifier: \"20260101T000000\"\n---\n\nx\n"))
          (with-temp-file bare (insert "no front matter\n"))
          (should (equal (denote-sync--export-title file) "My Title, Properly Cased"))
          (should (equal (denote-sync--export-title bare) "only-slug")))
      (delete-directory dir t))))

(ert-deftest test-denote-sync/dash-regexps-match-org-keyword-lines ()
  (let ((re (denote-sync--frontmatter-nonempty-value-regexp "sync-silo-id")))
    (should (string-match-p re "sync-silo-id: \"x\""))
    (should (string-match-p re "#+sync-silo-id: 2026"))
    (should-not (string-match-p re "#+sync-silo-id:"))))

(ert-deftest test-denote-sync/unknown-backend-signals-error ()
  "Querying an unregistered backend name signals an error."
  (should-error (denote-sync-get-backend 'nonexistent-backend)))

(ert-deftest test-denote-sync/frontmatter-get-and-set ()
  "Front-matter values can be retrieved and mutated."
  (let ((temp-file (make-temp-file "denote-sync-test-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file temp-file (insert test-denote-sync--fixture-empty-frontmatter))
          (should (equal (denote-sync-frontmatter-get temp-file "title") "\"Test Note\""))
          (should-not (denote-sync-frontmatter-get temp-file "test_prop"))
          (denote-sync-frontmatter-set temp-file "test_prop" "value123")
          (should (equal (denote-sync-frontmatter-get temp-file "test_prop") "\"value123\""))
          ;; Replace existing
          (denote-sync-frontmatter-set temp-file "test_prop" "newval")
          (should (equal (denote-sync-frontmatter-get temp-file "test_prop") "\"newval\"")))
      (delete-file temp-file))))

(ert-deftest test-denote-sync/frontmatter-set-creates-delimiters-when-missing ()
  "When a file has no YAML delimiters, `denote-sync-frontmatter-set' creates them."
  (let ((temp-file (make-temp-file "denote-sync-test-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file temp-file (insert "Plain body without front matter.\n"))
          (denote-sync-frontmatter-set temp-file "my_key" "my_val")
          (should (equal (denote-sync-frontmatter-get temp-file "my_key") "\"my_val\""))
          (with-temp-buffer
            (insert-file-contents temp-file)
            (should (string-prefix-p "---\nmy_key: \"my_val\"\n---" (buffer-string)))))
      (delete-file temp-file))))

(ert-deftest test-denote-sync/cache-compound-naming ()
  "Cache files are compound-named <backend>__<id> in `denote-sync-cache-directory'."
  (let ((denote-sync-cache-directory (make-temp-file "sync-cache-" t)))
    (unwind-protect
        (let ((path (denote-sync--cache-file-for 'notion "abc-123")))
          (should (equal (file-name-nondirectory path) "notion__abc-123"))
          (should (equal (file-name-directory path) (file-name-as-directory denote-sync-cache-directory))))
      (delete-directory denote-sync-cache-directory t))))

(ert-deftest test-denote-sync/cache-write-and-read ()
  "Content can be written and read back from the cache."
  (let ((denote-sync-cache-directory (make-temp-file "sync-cache-" t)))
    (unwind-protect
        (progn
          (should-not (denote-sync--cache-read 'google-docs "doc-456"))
          (denote-sync--cache-write 'google-docs "doc-456" "cached markdown text")
          (should (equal (denote-sync--cache-read 'google-docs "doc-456") "cached markdown text")))
      (delete-directory denote-sync-cache-directory t))))

(ert-deftest test-denote-sync/detect-backend-from-id ()
  "Target backend is inferred from known URL shapes."
  (let ((notion-b (denote-sync-backend-create :name 'notion))
        (gdoc-b (denote-sync-backend-create :name 'google-docs)))
    (let ((denote-sync-backends (list (cons 'notion notion-b) (cons 'google-docs gdoc-b))))
      (should (eq (denote-sync--detect-backend-from-id "https://www.notion.so/myworkspace/page-1234") notion-b))
      (should (eq (denote-sync--detect-backend-from-id "https://docs.google.com/document/d/1AbC-xyz/edit") gdoc-b))
      (should-not (denote-sync--detect-backend-from-id "bare-id-string")))))

(ert-deftest test-denote-sync/batch-run-bounded-concurrency ()
  "Batch runner runs items up to the max concurrent limit."
  (let* ((items '(1 2 3 4 5 6 7 8))
         (generator (gen-wrap (iter-make (dolist (item items) (iter-yield item)))))
         (in-flight 0)
         (max-seen 0)
         (completed 0)
         (done-called nil))
    (denote-sync--batch-run
     generator 3
     (lambda (item done)
       (setq in-flight (1+ in-flight))
       (when (> in-flight max-seen) (setq max-seen in-flight))
       (setq completed (1+ completed))
       (setq in-flight (1- in-flight))
       (funcall done))
     (lambda () (setq done-called t)))
    (should done-called)
    (should (= completed 8))
    (should (<= max-seen 3))))


(ert-deftest test-denote-sync/tracked-by-multiple-backends-disambiguation ()
  "A note tracked by both backends detects both and can target each individually."
  (let ((notion-b (denote-sync-backend-create :name 'notion :frontmatter-prefix "notion"))
        (gdoc-b (denote-sync-backend-create :name 'google-docs :frontmatter-prefix "gdoc"))
        (temp-file (make-temp-file "denote-sync-multitrack-" nil ".md")))
    (unwind-protect
        (let ((denote-sync-backends (list (cons 'notion notion-b) (cons 'google-docs gdoc-b))))
          (with-temp-file temp-file
            (insert "---\ntitle: \"Multi Note\"\nnotion_id: \"nid-1\"\ngdoc_id: \"gid-2\"\n---\n\nBody.\n"))
          (should (equal (denote-sync--tracked-backends temp-file) (list notion-b gdoc-b)))
          (should (denote-sync-tracked-p temp-file notion-b))
          (should (denote-sync-tracked-p temp-file gdoc-b))
          (should (equal (denote-sync--get-id temp-file notion-b) "nid-1"))
          (should (equal (denote-sync--get-id temp-file gdoc-b) "gid-2")))
      (delete-file temp-file))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sync- front-matter keys and legacy fallback

(ert-deftest test-denote-sync/prop-key-is-sync-prefixed-and-hyphenated ()
  (should (equal (denote-sync--prop-key "silo" "id") "sync-silo-id"))
  (should (equal (denote-sync--prop-key "silo" "sync_hash") "sync-silo-sync-hash"))
  (should (equal (denote-sync--legacy-key "sync-silo-sync-hash") "silo_sync_hash"))
  (should-not (denote-sync--legacy-key "title")))

(ert-deftest test-denote-sync/legacy-keys-read-and-migrate-markdown ()
  "A legacy `notion_id' line reads through the new key and is replaced on write."
  (let ((file (make-temp-file "denote-sync-legacy-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "---\ntitle: T\nnotion_id: \"abc\"\nnotion_sync_hash: \"h1\"\n---\nBody\n"))
          (should (equal (denote-sync-frontmatter-get file "sync-notion-id") "\"abc\""))
          (denote-sync-frontmatter-set file "sync-notion-sync-hash" "h2")
          (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "^sync-notion-sync-hash: \"h2\"$" text))
            (should-not (string-match-p "notion_sync_hash" text))
            (should (string-match-p "^notion_id: " text)))
          (should (equal (denote-sync-frontmatter-get file "sync-notion-sync-hash") "\"h2\"")))
      (when-let* ((b (find-buffer-visiting file))) (kill-buffer b))
      (delete-file file))))

(ert-deftest test-denote-sync/legacy-keys-read-and-migrate-org ()
  (let ((file (make-temp-file "denote-sync-legacy-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+title: T\n#+silo_id: 20260101T000000\n#+silo_dir: /tmp/x/\n\n* Body\n"))
          (should (equal (denote-sync-frontmatter-get file "sync-silo-id") "20260101T000000"))
          (denote-sync-frontmatter-set file "sync-silo-id" "20260202T000000")
          (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "^#\\+sync-silo-id: 20260202T000000$" text))
            (should-not (string-match-p "^#\\+silo_id" text))
            (should (string-match-p "^#\\+silo_dir: /tmp/x/$" text))))
      (when-let* ((b (find-buffer-visiting file))) (kill-buffer b))
      (delete-file file))))

(ert-deftest test-denote-sync/dash-regexps-match-both-spellings ()
  (let ((re (format "^\\(?:#\\+\\)?%s:[ \t]*t[ \t]*$"
                    (denote-sync--legacy-alternation "sync-notion-remote-dirty"))))
    (should (string-match-p re "sync-notion-remote-dirty: t"))
    (should (string-match-p re "#+notion_remote_dirty: t"))
    (should-not (string-match-p re "sync-notion-remote-dirtys: t"))))

(provide 'test-denote-sync)
;;; test-denote-sync.el ends here

;;; Format-independent change key

(defun test-denote-sync--change-key-note (body)
  "Write an org note with BODY to a temp dir and return its path."
  (let* ((dir (make-temp-file "dsync-key-" t))
         (file (expand-file-name "20261011T100000--key__t.org" dir)))
    (with-temp-file file
      (insert "#+title: key\n#+identifier: 20261011T100000\n\n" body "\n"))
    file))

(ert-deftest test-denote-sync/change-key-ignores-front-matter ()
  (let* ((file (test-denote-sync--change-key-note "Body text"))
         (b (denote-sync-backend-create :name 'fake :frontmatter-prefix "fake"))
         (before (denote-sync--change-key file b)))
    (should (string-match-p "\\`[0-9a-f]\\{40\\}\\'" before))
    (with-temp-file file
      (insert "#+title: renamed\n#+identifier: 20261011T100000\n#+sync-fake-id: x\n\nBody text\n"))
    (should (equal before (denote-sync--change-key file b)))))

(ert-deftest test-denote-sync/change-key-tracks-body-edits ()
  (let* ((file (test-denote-sync--change-key-note "Body text"))
         (b (denote-sync-backend-create :name 'fake :frontmatter-prefix "fake"))
         (before (denote-sync--change-key file b)))
    (denote-sync--write-body file "Body text, edited")
    (should-not (equal before (denote-sync--change-key file b)))))

(ert-deftest test-denote-sync/change-key-tracks-link-target-becoming-tracked ()
  (let* ((file (test-denote-sync--change-key-note "See [[denote:20261011T110000][other]]"))
         (b (denote-sync-backend-create :name 'fake :frontmatter-prefix "fake"))
         (target (test-denote-sync--change-key-note "x")))
    (cl-letf (((symbol-function 'denote-get-path-by-id) (lambda (_id) target)))
      (let ((untracked (denote-sync--change-key file b)))
        (denote-sync-frontmatter-set target "sync-fake-id" "remote-1")
        (should-not (equal untracked (denote-sync--change-key file b)))))))

(ert-deftest test-denote-sync/local-changed-p-compares-change-key ()
  (let* ((file (test-denote-sync--change-key-note "Body text"))
         (b (denote-sync-backend-create :name 'fake :frontmatter-prefix "fake"))
         (key (denote-sync--change-key file b)))
    (should-not (denote-sync--local-changed-p file b key))
    (should (denote-sync--local-changed-p file b "stale"))
    (should (denote-sync--local-changed-p file b ""))
    ;; a pre-change-key SHA-1 reads as changed
    (should (denote-sync--local-changed-p file b (secure-hash 'sha1 "Body text")))))

;;; Batched front matter

(ert-deftest test-denote-sync/frontmatter-set-many-saves-once ()
  (let* ((file (test-denote-sync--change-key-note "Body text"))
         (saves 0))
    (add-hook 'after-save-hook (lambda () (when (equal buffer-file-name file) (cl-incf saves))) nil nil)
    (unwind-protect
        (progn
          (denote-sync-frontmatter-set-many
           file '(("sync-fake-id" . "abc") ("sync-fake-edited" . "2026-10-11") ("sync-fake-sync-hash" . "h")))
          (should (= saves 1))
          (should (equal (denote-sync-frontmatter-get file "sync-fake-id") "abc"))
          (should (equal (denote-sync-frontmatter-get file "sync-fake-edited") "2026-10-11"))
          (should (equal (denote-sync-frontmatter-get file "sync-fake-sync-hash") "h"))
          ;; no pairs, no visit, no save
          (denote-sync-frontmatter-set-many file nil)
          (should (= saves 1)))
      (when-let* ((buf (find-buffer-visiting file))) (kill-buffer buf)))))

(ert-deftest test-denote-sync/record-synced-content-writes-hash-edited-and-extras-in-one-save ()
  (let* ((file (test-denote-sync--change-key-note "Body text"))
         (b (denote-sync-backend-create :name 'fake :frontmatter-prefix "fake"))
         (denote-sync-cache-directory (make-temp-file "dsync-cache-" t))
         (calls 0))
    (cl-letf* ((orig (symbol-function 'denote-sync-frontmatter-set-many))
               ((symbol-function 'denote-sync-frontmatter-set-many)
                (lambda (&rest args) (cl-incf calls) (apply orig args))))
      (denote-sync--record-synced-content file b "r1" "body" "2026-10-11"
                                          '(("sync-fake-id" . "r1")))
      (should (= calls 1))
      (should (equal (denote-sync--get-id file b) "r1"))
      (should (equal (denote-sync--get-edited file b) "2026-10-11"))
      (should (equal (denote-sync--get-sync-hash file b) (denote-sync--change-key file b))))))
