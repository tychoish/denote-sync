;;; build-pages.el --- Build HTML documentation site for denote-sync  -*- lexical-binding: t; -*-

;; Commentary:
;; Batch Elisp script to export docs/*.org files to HTML for GitHub Pages.
;; Supports static asset copying and Google Search Console verification
;; via both HTML <meta> tag and HTML verification file.
;;
;; Usage:
;;   emacs --script scripts/build-pages.el

(require 'ox-html)

(setq org-html-htmlize-output-type nil
      org-html-doctype "html5"
      org-html-html5-fancy t
      org-html-validation-link nil)

(defun build-pages-export-all (&optional docs-dir site-dir)
  "Export all .org files in DOCS-DIR to HTML into SITE-DIR."
  (let* ((root-dir (or (locate-dominating-file default-directory "docs") default-directory))
         (docs-directory (expand-file-name (or docs-dir "docs") root-dir))
         (output-directory (expand-file-name (or site-dir "_site") root-dir))
         ;; Extract verification tag and file tokens from environment
         (gsc-tag (or (getenv "GSC_VERIFICATION_TAG")
                      (getenv "GSC_VERIFICATION_CODE")
                      (getenv "GSC_SITE_VERIFICATION")))
         (gsc-file (or (getenv "GSC_VERIFICATION_FILE")
                       (getenv "GSC_VERIFICATION_TOKEN")
                       (getenv "GSC_VERIFICATION_CODE"))))
    
    (unless (file-directory-p docs-directory)
      (error "Docs directory does not exist: %s" docs-directory))
    
    (make-directory output-directory t)
    (message "Building documentation site:")
    (message "  Source: %s" docs-directory)
    (message "  Target: %s" output-directory)

    ;; 1. Inject HTML <meta> tag for Google Search Console
    (when (and gsc-tag (not (string-empty-p gsc-tag)))
      (setq org-html-head-extra
            (concat (or org-html-head-extra "")
                    (format "<meta name=\"google-site-verification\" content=\"%s\" />\n" gsc-tag)))
      (message "  [gsc] Injected <meta name=\"google-site-verification\" content=\"%s\" />" gsc-tag))

    ;; 2. Export each Org file to HTML
    (let ((org-files (directory-files docs-directory t "\\.org\\'")))
      (dolist (org-file org-files)
        (let ((outfile (expand-file-name
                        (concat (file-name-base org-file) ".html")
                        output-directory)))
          (message "  [org -> html] %s -> %s"
                   (file-name-nondirectory org-file)
                   (file-name-nondirectory outfile))
          (with-current-buffer (find-file-noselect org-file)
            (org-export-to-file 'html outfile)))))

    ;; 3. Copy static assets (png, svg, jpg, css, ico)
    (let ((assets (directory-files docs-directory t "\\.\\(png\\|svg\\|jpg\\|jpeg\\|css\\|ico\\)\\'")))
      (dolist (asset assets)
        (let ((dest (expand-file-name (file-name-nondirectory asset) output-directory)))
          (copy-file asset dest t)
          (message "  [asset] %s" (file-name-nondirectory asset)))))

    ;; 4. Google Search Console HTML verification file
    (when (and gsc-file (not (string-empty-p gsc-file)))
      (let* ((clean-name (if (string-suffix-p ".html" gsc-file)
                             (file-name-base gsc-file)
                           gsc-file))
             (filename (if (string-prefix-p "google" clean-name)
                           (format "%s.html" clean-name)
                         (format "google%s.html" clean-name)))
             (verify-file (expand-file-name filename output-directory))
             (content (format "google-site-verification: %s\n" filename)))
        (with-temp-file verify-file
          (insert content))
        (message "  [gsc] Emitted %s" filename)))

    ;; 5. Copy any static google*.html verification file if checked into docs/
    (let ((gsc-files (directory-files docs-directory t "\\`google.*\\.html\\'")))
      (dolist (gfile gsc-files)
        (let ((dest (expand-file-name (file-name-nondirectory gfile) output-directory)))
          (copy-file gfile dest t)
          (message "  [gsc] Copied %s" (file-name-nondirectory gfile)))))

    (message "Build complete. Artifacts written to %s" output-directory)))

;; Execute automatically in batch mode:
(when noninteractive
  (build-pages-export-all))

(provide 'build-pages)
;;; build-pages.el ends here
