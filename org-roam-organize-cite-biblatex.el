;;; org-roam-organize-cite-biblatex.el --- BibLaTeX export compatibility for Org-roam Organize -*- lexical-binding: t; package-lint-main-file: "org-roam-organize.el"; -*-

;;; Commentary:

;; This bundled module preserves BibLaTeX bibliography metadata when an Org
;; Cite processor exports citations but does not finalize the LaTeX preamble.
;; It is loaded and managed by `org-roam-organize-mode'; it does not select an
;; export processor or insert a bibliography-printing command.

;;; Code:

(require 'rx)
(require 'org-roam-organize-core)
(require 'org-roam-organize-cite)

(defvar org-roam-organize-mode)

(declare-function org-cite-bibliography-style "oc" (info))
(declare-function org-cite-biblatex--package-options
                  "oc-biblatex" (initial style))
(declare-function org-export-derived-backend-p "ox" (backend &rest backends))

(defvar org-cite-biblatex-options)

(defconst org-roam-organize-cite-biblatex--package-regexp
  (rx "\\"
      (or "usepackage" "RequirePackage")
      (opt "[" (*? nonl) "]")
      (* blank)
      "{biblatex}")
  "The regexp matches a direct BibLaTeX package declaration.

Both LaTeX document declarations and package-level declarations are accepted.
Indirect loading through another class or package is intentionally not
inferred from the generated document.")

(defun org-roam-organize-cite-biblatex--export-p (backend info)
  "Return non-nil when BACKEND and INFO describe BibLaTeX export.

BACKEND is the backend passed to an Org final-output filter.  INFO is the
export communication channel.  Derived LaTeX backends are accepted, but the
selected citation export processor must be `biblatex'.

Implementation notes: Processor selection is read from INFO after Org Cite
has stored `:cite-export', so this predicate does not load or select a
processor.

Rationale: The compatibility behavior follows the document's export choice,
which is independent of the optional interactive citation backend configured
in the Org-roam Organize registry."
  (and (org-export-derived-backend-p backend 'latex)
       (eq (car-safe (plist-get info :cite-export)) 'biblatex)))

(defun org-roam-organize-cite-biblatex--managed-bibliography-present-p (files)
  "Return non-nil when FILES contains a managed bibliography.

FILES is the bibliography list stored in the Org export communication
channel.  This function queries the current managed bibliography paths and
does not read or validate any referenced file.

Implementation notes: Membership uses the normalized absolute paths produced
by `org-roam-organize--bibliography-files'.

Rationale: Org-roam Organize must not repair unrelated BibLaTeX exports merely
because its global minor mode is enabled."
  (let ((managed-files (org-roam-organize--bibliography-files)))
    (seq-some (lambda (file) (member file managed-files)) files)))

(defun org-roam-organize-cite-biblatex--package-declaration (info)
  "Return a BibLaTeX package declaration derived from INFO.

INFO is the Org export communication channel.  Preserve the configured
`org-cite-biblatex-options' and bibliography style.  Signal `user-error' when
the selected Org processor lacks the option-construction interface required
for a faithful fallback.

Implementation notes: The declaration delegates option merging to
`org-cite-biblatex--package-options', matching the processor that generated
the citation commands.

Rationale: Reimplementing BibLaTeX option and style precedence here would
silently diverge from Org Cite behavior."
  (unless (and (fboundp 'org-cite-bibliography-style)
               (fboundp 'org-cite-biblatex--package-options))
    (user-error
     "The selected BibLaTeX processor cannot construct export metadata"))
  (let ((options
         (org-cite-biblatex--package-options
          (and (boundp 'org-cite-biblatex-options)
               org-cite-biblatex-options)
          (org-cite-bibliography-style info))))
    (format "\\usepackage%s{biblatex}\n" (or options ""))))

(defun org-roam-organize-cite-biblatex--resource-declaration (file)
  "Return a BibLaTeX resource declaration for FILE.

FILE is inserted as received from Org Cite.  The function does not normalize,
escape, read, or validate the path."
  (format "\\addbibresource{%s}" file))

(defun org-roam-organize-cite-biblatex--filter-final-output
    (output backend info)
  "Add missing managed BibLaTeX metadata to OUTPUT.

BACKEND and INFO are supplied by `org-export-filter-final-output-functions'.
Return OUTPUT unchanged unless Org-roam Organize mode is enabled, BACKEND is
LaTeX-derived, the selected citation export processor is `biblatex', and at
least one bibliography in INFO is managed by Org-roam Organize.  Insert a
direct BibLaTeX package declaration when absent and add only resource
declarations missing from OUTPUT.  Do not insert `\\printbibliography'.  A
body-only export or other output without `\\begin{document}' is unchanged.

Implementation notes: This filter runs after Org Cite's export finalizer.  It
therefore detects successful upstream behavior from the resulting text rather
than relying on an Org version number or a private finalizer name.  Metadata is
inserted immediately before `\\begin{document}'.

Rationale: Some Org Cite versions export BibLaTeX citation commands while
registering no finalizer.  An output-based, idempotent fallback repairs that
narrow gap and automatically becomes a no-op when upstream emits the expected
metadata."
  (if (not (and org-roam-organize-mode
                (org-roam-organize-cite-biblatex--export-p backend info)))
      output
    (let ((files (plist-get info :bibliography)))
      (if (not (and files
                    (org-roam-organize-cite-biblatex--managed-bibliography-present-p
                     files)))
          output
        (let* ((missing-files
                (seq-filter
                 (lambda (file)
                   (not
                    (string-search
                     (org-roam-organize-cite-biblatex--resource-declaration file)
                     output)))
                 files))
               (document-position
                (and missing-files
                     (string-search "\\begin{document}" output))))
          (if (not document-position)
              output
            (let ((metadata
                   (concat
                    (unless
                        (string-match-p
                         org-roam-organize-cite-biblatex--package-regexp
                         output)
                      (org-roam-organize-cite-biblatex--package-declaration info))
                    (mapconcat
                     #'org-roam-organize-cite-biblatex--resource-declaration
                     missing-files
                     "\n")
                    "\n")))
              (concat (substring output 0 document-position)
                      metadata
                      (substring output document-position)))))))))

(defun org-roam-organize-cite-biblatex--setup ()
  "Install the BibLaTeX final-output compatibility filter.

Return non-nil after adding the global filter.  Repeated calls are idempotent.
The filter guards its behavior with `org-roam-organize-mode'.

Implementation notes: `org-roam-organize--setup-cite-integration' owns this
function's lifecycle and calls the matching teardown function during mode
disable or setup rollback."
  (add-hook 'org-export-filter-final-output-functions
            #'org-roam-organize-cite-biblatex--filter-final-output)
  t)

(defun org-roam-organize-cite-biblatex--teardown ()
  "Remove the BibLaTeX final-output compatibility filter.

Return nil.  Calling this function when the filter is absent is safe."
  (remove-hook 'org-export-filter-final-output-functions
               #'org-roam-organize-cite-biblatex--filter-final-output)
  nil)

(provide 'org-roam-organize-cite-biblatex)
;;; org-roam-organize-cite-biblatex.el ends here
