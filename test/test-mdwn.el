;;; test-mdwn.el --- ERT tests for mdwn -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Code:

(require 'ert)
(require 'mdwn)

(defun test-mdwn--conv (md)
  (mdwn-to-org md))

(ert-deftest test-mdwn/headings ()
  (should (equal (test-mdwn--conv "# One\n\n### Three") "* One\n\n*** Three"))
  (should (equal (test-mdwn--conv "Title\n=====") "* Title")))

(ert-deftest test-mdwn/inline ()
  (should (equal (test-mdwn--conv "a **b** *c* `d` ~~e~~")
                 "a *b* /c/ ~d~ +e+"))
  (should (equal (test-mdwn--conv "**bold *and em***") "*bold /and em/*"))
  (should (equal (test-mdwn--conv "`*not em*` and *em*") "~*not em*~ and /em/"))
  (should (equal (test-mdwn--conv "[Beta](denote:20261009T100500)")
                 "[[denote:20261009T100500][Beta]]"))
  (should (equal (test-mdwn--conv "![alt](a.png)") "[[a.png]]"))
  (should (equal (test-mdwn--conv "<http://x.org>") "[[http://x.org]]"))
  (should (equal (test-mdwn--conv "one  \ntwo") "one\ntwo")))

(ert-deftest test-mdwn/lists ()
  (should (equal (test-mdwn--conv "- a\n  - nested\n- b") "- a\n  - nested\n- b"))
  (should (equal (test-mdwn--conv "3. one\n4. two") "3. one\n4. two"))
  (should (equal (test-mdwn--conv "- [ ] todo\n- [x] done") "- [ ] todo\n- [X] done")))

(ert-deftest test-mdwn/blocks ()
  (should (equal (test-mdwn--conv "> quote") "#+begin_quote\nquote\n#+end_quote"))
  (should (equal (test-mdwn--conv "```elisp\n(x)\n# not heading\n```")
                 "#+begin_src elisp\n(x)\n# not heading\n#+end_src"))
  (should (equal (test-mdwn--conv "```\nplain\n```") "#+begin_src\nplain\n#+end_src"))
  (should (equal (test-mdwn--conv "a\n\n---\n\nb") "a\n\n-----\n\nb"))
  (should (equal (test-mdwn--conv "| a | **b** |\n|---|---|\n| 1 | 2 |")
                 "| a | *b* |\n|-\n| 1 | 2 |")))

(ert-deftest test-mdwn/missing-grammar-signals-user-error ()
  (let ((mdwn-install-grammars nil))
    (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (&rest _) nil)))
      (should-error (mdwn-to-org "x") :type 'user-error))))

(ert-deftest test-mdwn/install-grammars-when-enabled ()
  (let ((mdwn-install-grammars t) installed)
    (cl-letf (((symbol-function 'treesit-language-available-p)
               (lambda (lang &rest _) (memq lang installed)))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (lang &rest _) (push lang installed))))
      (mdwn--ensure-grammars)
      (should (equal (sort (mapcar #'symbol-name installed) #'string<)
                     '("markdown" "markdown-inline"))))))

(provide 'test-mdwn)
;;; test-mdwn.el ends here
