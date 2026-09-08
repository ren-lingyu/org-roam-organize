;;; org-roam-organize-biblatex-test.el --- Tests for Org-roam Organize BibLaTeX compatibility -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for managed bibliography metadata in BibLaTeX export.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ox)
(require 'ox-ascii)
(require 'ox-latex)
(require 'oc-biblatex)
(require 'org-roam-organize)
(require 'org-roam-organize-biblatex)

(defconst org-roam-organize-biblatex-test--uuid
  "2a54185a-1ae2-4cf6-8451-7f17cf7fccc8"
  "The managed UUID used by BibLaTeX export tests.")

(defun org-roam-organize-biblatex-test--info (files &optional processor)
  "Return minimal export information for FILES and PROCESSOR.

PROCESSOR defaults to `biblatex'.  The result is suitable for direct calls to
the final-output compatibility filter."
  (list :cite-export (list (or processor 'biblatex) nil nil)
        :bibliography files))

(defun org-roam-organize-biblatex-test--string-count (needle haystack)
  "Return the number of non-overlapping NEEDLE occurrences in HAYSTACK.

NEEDLE must be a non-empty string.  This helper uses `string-search' so the
test suite does not depend on a newer string-counting API."
  (let ((count 0)
        (start 0))
    (while (setq start (string-search needle haystack start))
      (setq count (1+ count)
            start (+ start (length needle))))
    count))

(ert-deftest org-roam-organize-biblatex-test-adds-missing-metadata ()
  (let* ((file "/managed/reference.bib")
         (output
          "\\documentclass{article}\n\\begin{document}\nText\n\\end{document}\n")
         (org-roam-organize-mode t)
         (org-cite-biblatex-options "backend=biber"))
    (cl-letf (((symbol-function 'org-roam-organize--bibliography-files)
               (lambda () (list file))))
      (let ((result
             (org-roam-organize-biblatex--filter-final-output
              output
              'latex
              (org-roam-organize-biblatex-test--info (list file)))))
        (should
         (string-search "\\usepackage[backend=biber]{biblatex}" result))
        (should
         (string-search "\\addbibresource{/managed/reference.bib}" result))
        (should
         (< (string-search "\\addbibresource" result)
            (string-search "\\begin{document}" result)))
        (should-not (string-search "\\printbibliography" result))))))

(ert-deftest org-roam-organize-biblatex-test-preserves-existing-metadata ()
  (let* ((file "/managed/reference.bib")
         (output
          (concat
           "\\documentclass{article}\n"
           "\\usepackage[backend=biber]{biblatex}\n"
           "\\addbibresource{/managed/reference.bib}\n"
           "\\begin{document}\n\\end{document}\n"))
         (org-roam-organize-mode t))
    (cl-letf (((symbol-function 'org-roam-organize--bibliography-files)
               (lambda () (list file))))
      (should
       (eq output
           (org-roam-organize-biblatex--filter-final-output
            output
            'latex
            (org-roam-organize-biblatex-test--info (list file))))))))

(ert-deftest org-roam-organize-biblatex-test-adds-only-missing-resources ()
  (let* ((first "/managed/first.bib")
         (second "/managed/second.bib")
         (output
          (concat
           "\\documentclass{article}\n"
           "\\usepackage{biblatex}\n"
           "\\addbibresource{/managed/first.bib}\n"
           "\\begin{document}\n\\end{document}\n"))
         (org-roam-organize-mode t))
    (cl-letf (((symbol-function 'org-roam-organize--bibliography-files)
               (lambda () (list first second))))
      (let ((result
             (org-roam-organize-biblatex--filter-final-output
              output
              'latex
              (org-roam-organize-biblatex-test--info
               (list first second)))))
        (should
         (= 1
            (org-roam-organize-biblatex-test--string-count
             "\\usepackage{biblatex}"
             result)))
        (should
         (= 1
            (org-roam-organize-biblatex-test--string-count
             "\\addbibresource{/managed/first.bib}"
             result)))
        (should
         (= 1
            (org-roam-organize-biblatex-test--string-count
             "\\addbibresource{/managed/second.bib}"
             result)))))))

(ert-deftest org-roam-organize-biblatex-test-obeys-integration-boundaries ()
  (let* ((managed "/managed/reference.bib")
         (local "/local/reference.bib")
         (output
          "\\documentclass{article}\n\\begin{document}\n\\end{document}\n"))
    (cl-letf (((symbol-function 'org-roam-organize--bibliography-files)
               (lambda () (list managed))))
      (let ((org-roam-organize-mode nil))
        (should
         (eq output
             (org-roam-organize-biblatex--filter-final-output
              output
              'latex
              (org-roam-organize-biblatex-test--info (list managed))))))
      (let ((org-roam-organize-mode t))
        (should
         (eq output
             (org-roam-organize-biblatex--filter-final-output
              output
              'ascii
              (org-roam-organize-biblatex-test--info (list managed)))))
        (should
         (eq output
             (org-roam-organize-biblatex--filter-final-output
              output
              'latex
              (org-roam-organize-biblatex-test--info
               (list managed)
               'basic))))
        (should
         (eq output
             (org-roam-organize-biblatex--filter-final-output
              output
              'latex
              (org-roam-organize-biblatex-test--info (list local)))))))))

(ert-deftest org-roam-organize-biblatex-test-body-only-output-is-unchanged ()
  (let ((file "/managed/reference.bib")
        (output "Text with \\autocite{key}.\n")
        (org-roam-organize-mode t))
    (cl-letf (((symbol-function 'org-roam-organize--bibliography-files)
               (lambda () (list file))))
      (should
       (eq output
           (org-roam-organize-biblatex--filter-final-output
            output
            'latex
            (org-roam-organize-biblatex-test--info (list file))))))))

(ert-deftest org-roam-organize-biblatex-test-setup-and-teardown-own-hook ()
  (let ((org-export-filter-final-output-functions nil))
    (unwind-protect
        (progn
          (should (org-roam-organize-biblatex--setup))
          (should (org-roam-organize-biblatex--setup))
          (should
           (memq #'org-roam-organize-biblatex--filter-final-output
                 org-export-filter-final-output-functions))
          (org-roam-organize-biblatex--teardown)
          (should-not
           (memq #'org-roam-organize-biblatex--filter-final-output
                 org-export-filter-final-output-functions)))
      (org-roam-organize-biblatex--teardown))))

(ert-deftest org-roam-organize-biblatex-test-runs-in-real-export-pipeline ()
  (let* ((bibliography (make-temp-file
                        "org-roam-organize-biblatex-test-"
                        nil
                        ".bib"))
         (org-roam-organize-mode t)
         (org-roam-organize-registry
          '((:name "literature"
             :tag "ref"
             :cite t
             :bibliography t)))
         (org-cite-export-processors '((latex biblatex)))
         (org-cite-global-bibliography nil)
         (org-export-filter-final-output-functions nil)
         (org-export-filter-parse-tree-functions nil)
         (uuid-to-citekey (make-hash-table :test 'equal)))
    (puthash org-roam-organize-biblatex-test--uuid
             "external-key"
             uuid-to-citekey)
    (unwind-protect
        (progn
          (with-temp-file bibliography
            (insert
             "@article{external-key,\n"
             "  author = {Example, Alice},\n"
             "  title = {Managed Reference},\n"
             "  year = {2026}\n"
             "}\n"))
          (cl-letf
              (((symbol-function 'org-roam-organize--bibliography-files)
                (lambda () (list bibliography)))
               ((symbol-function
                 'org-roam-organize--cite-export-reference-map-data-or-error)
                (lambda (keys)
                  (should
                   (equal keys
                          (list org-roam-organize-biblatex-test--uuid)))
                  (list :uuid-to-citekey uuid-to-citekey))))
            (org-roam-organize--setup-cite-integration)
            (let ((result
                   (org-export-string-as
                    (format "[cite:@%s]."
                            org-roam-organize-biblatex-test--uuid)
                    'latex)))
              (should (string-search "\\autocite{external-key}" result))
              (should
               (string-search
                (format "\\addbibresource{%s}" bibliography)
                result))
              (should (string-search "\\usepackage{biblatex}" result))
              (should-not (string-search "\\printbibliography" result)))))
      (org-roam-organize--teardown-cite-integration)
      (when (file-exists-p bibliography)
        (delete-file bibliography)))))

(provide 'org-roam-organize-biblatex-test)
;;; org-roam-organize-biblatex-test.el ends here
