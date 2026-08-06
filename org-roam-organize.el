;;; org-roam-organize.el --- Organize Org-roam node references -*- lexical-binding: t; -*-

;; Copyright (C) 2026 aRenCoco

;; Author: aRenCoco
;; Maintainer: aRenCoco
;; Version: 0.7.0
;; Package-Requires: ((emacs "30.1") (org "9.5") (org-roam "2.3.1"))
;; Keywords: outlines, hypermedia
;; URL: https://github.com/ren-lingyu/org-roam-organize
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Org-roam-organize provides tools for organizing Org-roam nodes and their
;; references.  It includes commands for maintaining Map of Contents files,
;; creating managed nodes, syncing citing-node entries, and updating node
;; statistics.
;;
;; See README.org for configuration, keybindings, usage examples, and notes
;; about supported MOC operations.

;;; Code:

;; ==============================
;; 声明外部依赖
;; ==============================

(require 'cl-lib)
(require 'seq)
(require 'rx)
(require 'org)
(require 'org-element)
(require 'ox)
(require 'org-roam)

;; ==============================
;; 用户变量定义
;; ==============================

;;;###autoload
(defgroup org-roam-organize
  nil
  "org-roam-organize variables"
  :group 'org-roam)

;; Core configuration.
(defcustom org-roam-organize-directory
  org-roam-directory
  "org-roam-organize 根目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize-moc-managed-tag-property
  "MOC_MANAGED_TAG"
  "标记 MOC 所管理 FILETAG 的属性名"
  :type 'string
  :group 'org-roam-organize)

(defcustom org-roam-organize-moc-managed-node-count-property
  "MOC_MANAGED_NODE_COUNT"
  "标记 MOC 所管理的 nodes 总数的属性名"
  :type 'string
  :group 'org-roam-organize)

(defcustom org-roam-organize-registry
  (list (list :name "navigation"
              :tag "map"
              :moc t
              :basic t
              :directory "navigation"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
                                       (date . nil)
                                       (description . nil)
                                       (filetags . ("map"))))))
        (list :name "fleeting"
              :tag "idea"
              :basic t
              :directory "fleeting"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
                                       (date . nil)
                                       (description . nil)
                                       (filetags . ("idea"))))))
        (list :name "literature"
              :tag "ref"
              :basic t
              :cite t
              :directory "literature"
              :inbox "Inbox"
              :template '((path . "ref.org")
                           (keywords . ((author . nil)
                                        (date . nil)
                                        (description . nil)
                                        (filetags . ("ref"))))))
        (list :name "permanent"
              :tag "zettel"
              :basic t
              :directory "permanent"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
                                       (date . nil)
                                       (description . nil)
                                       (filetags . ("zettel"))))))
        (list :name "note"
              :tag "note"
              :basic nil
              :directory "permanent"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
                                       (date . nil)
                                       (description . nil)
                                       (filetags . ("zettel" "note"))))))
        (list :name "blog"
              :tag "blog"
              :basic nil
              :directory "permanent"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
                                       (date . nil)
                                       (description . nil)
                                       (filetags . ("zettel" "blog")))))))
  "Registry of MOC records managed by Org-roam Organize.

Each record is a plist.  `:name' and `:tag' are required strings.
`:moc', `:basic', and `:cite' are optional booleans.  A `:moc t' record must
also be `:basic t'.  At most one record may use `:cite t'; that record
identifies literature nodes for citation export, checking, and synchronization.
Citation database operations recognize level-0 nodes carrying that record's
`:tag'; a capture template that creates citation nodes is responsible for
including the tag in its `filetags' keyword.
Its optional `:backend' value selects additional interactive integration.  It
may be a backend name or a proper list whose car is the backend name and whose
cdr is an option plist.  `citar' installs the optional Citar adapter, while
nil, an absent key, or any other backend name installs no adapter.  A Citar
backend record must also use `:cite t'.  Unsupported non-nil backend names are
ignored with a warning when the mode is enabled.  A basic record must have a
relative `:directory';
non-basic records may also use `:directory' to create managed nodes in an
existing kind directory.
`:moc-path' and `:moc-title' are optional overrides resolved from the record
name when absent.  `:inbox' is an optional level-1 headline name used for
newly added generated entries and defaults to \"Inbox\".
`:template' is an optional structured alist for the generated capture
template.  Its `path' entry controls the ordinary managed node file path
inside the `${id}/' bundle directory and defaults to \"${slug}.org\".  `path'
is ignored by MOC capture and must not be declared by a `:moc t' record.  The
`properties' section is an ordered alist emitted
inside an Org property drawer.  The `keywords' section is an ordered alist
emitted as Org file keywords.  String values are written into the generated
Org-roam capture template, so Org capture escapes such as `%<...>' and
Org-roam placeholders such as `${field}' may be expanded by
`org-roam-capture-'.  Repeated keys are emitted repeatedly.  Nil values emit
empty property or keyword values.  The `filetags' keyword accepts a list of
strings and is formatted as Org file tags; other values are written with
`identity'.  `:provider' is an optional function used when creating ordinary
managed nodes.  It is called with the full record and should return nil to
cancel creation or a request plist containing `:title' and optional `:info'.
The provider does not control paths, targets, or capture templates."
  :type 'sexp
  :group 'org-roam-organize)

;; ==============================
;; 前置声明
;; ==============================

(defvar org-roam-organize-mode)
(defvar org-note-abort)
(defvar org-roam-organize--active-cite-backend nil
  "The value names the backend installed by the current mode lifecycle.

This records successful installation rather than the requested value in
the citation registry record, allowing optional backend failure to leave the
core mode active without claiming adapter ownership.")

(declare-function org-roam-organize-citar-setup "org-roam-organize-citar")
(declare-function org-roam-organize-citar-teardown "org-roam-organize-citar")

;; ==============================
;; 常量定义
;; ==============================

(defconst org-roam-organize--variable-type-alist
  '((org-roam-organize-directory . directory)
    (org-roam-organize-moc-managed-tag-property . string)
    (org-roam-organize-moc-managed-node-count-property . string)
    (org-roam-organize-registry . list)))

(defconst org-roam-organize--capability-alist
  '((org-roam-directory . variable)
    (org-roam-db . function)
    (org-roam-db-query . function)
    (org-roam-node-create . function)
    (org-roam-node-from-id . function)
    (org-roam-node-file . function)
    (org-roam-node-id . function)
    (org-roam-node-title . function)
    (org-roam-capture- . function)
    (org-roam-capture-preface-hook . variable)
    (org-roam-capture--get-target . function)
    (org-roam-capture--target-truepath . function)
    (org-capture-after-finalize-hook . variable)
    (org-mode . function)
    (org-element-parse-buffer . function)
    (org-element-map . function)
    (org-element-at-point . function)
    (org-element-type . function)
    (org-element-property . function)
    (org-element-put-property . function)
    (org-export-filter-parse-tree-functions . variable)
    (org-link-make-string . function)
    (seq-every-p . function)
    (seq-filter . function)
    (seq-find . function))
  "Runtime capabilities required by Org-roam Organize.

The list maps symbols to capability types checked by
`org-roam-organize--check-capabilities'.")

(defconst org-roam-organize--record-name-regexp
  (rx string-start (+ (any "A-Za-z0-9_-")) string-end)
  "Regexp matching a safe Org-roam Organize registry record name.")

(defconst org-roam-organize--moc-capture-key "m"
  "Capture key used internally when creating MOC files.")

(defconst org-roam-organize--node-capture-key "n"
  "Capture key used internally when creating managed node files.")

(defconst org-roam-organize--moc-default-inbox-headline "Inbox"
  "Default headline used for newly added generated entries.")

(defconst org-roam-organize--moc-node-keyword "ROAM_NODE"
  "Org keyword used for MOC node entries.")

(defconst org-roam-organize--cite-citing-node-keyword "ROAM_CITING_NODE"
  "Org keyword used for generated citing-node entries.")

(defconst org-roam-organize--report-buffer-name
  "*Org-roam Organize Report*"
  "Buffer name used for Org-roam Organize command reports.")

(defconst org-roam-organize--file-head-formatter-alist
  '((filetags . org-roam-organize--file-head-filetags-format))
  "Special file head formatter functions.

Formatter functions receive the template value and return the string written
after the Org property or keyword name.  They only serialize structured
values and do not perform dynamic value lookup.  Keys not listed here use
`identity'.")

(defconst org-roam-organize--node-relative-path-template
  "${id}/"
  "Relative directory template inside a managed node kind directory.

The standard node layout is `${id}/' plus a registry-derived path under a kind
directory.  `${id}' is left for Org-roam capture expansion.")

(defconst org-roam-organize--node-default-path-template
  "${slug}.org"
  "Default managed node path template inside the `${id}/' directory.")

;; ==============================
;; 内部函数
;; ==============================

;; 变量检查 (不依赖 minor-mode 开启)
(defun org-roam-organize--check-variables (root_dir alist)
  "Check Org-roam Organize variables in ALIST under ROOT_DIR.

ALIST should map variable symbols to expected type symbols.  Directory
variables must be existing directories inside ROOT_DIR.  Return a cons cell
whose car is the boolean result and whose cdr is a human-readable report.

Implementation notes: this is a report builder, not a signaling validator.
It walks the variable/type alist once, reads each bound variable by symbol,
checks only the small set of supported type tags, and accumulates both a
boolean result and diagnostic lines so callers can show all configuration
problems at once."
  (if (listp alist)
      (let* ((result_bool t)
             (result_message
              (concat "All org-roam-organize variables are as follow.\n"))
             (add_to_result_message_
              (lambda (var_name var_value var_expected_type)
                (setq result_message
                      (concat
                       result_message
                       (format "- %s? %s \n" var_name var_value)
                       (cond
                        ((or (and (eq var_value nil) (eq var_expected_type 'directory))
                             (and (eq var_value nil) (eq var_expected_type 'file)))
                         (format "  %s? %s (should be t)\n" var_expected_type nil))
                        ((eq var_expected_type 'directory)
                         (concat
                          (format "  %s? %s (should be t)\n"
                                  var_expected_type
                                  (and (stringp var_value)
                                       (when (stringp var_value)
                                         (funcall 'file-directory-p var_value))))
                          (when (stringp var_value)
                            (when (file-directory-p var_value)
                              (format
                               "  in org-roam-organize root directory? %s (should be t)\n"
                               (file-in-directory-p
                                (expand-file-name var_value)
                                (expand-file-name root_dir)))))))
                        ((eq var_expected_type 'file)
                         (format "  %s? %s (should be t)\n"
                                 var_expected_type
                                 (and (stringp var_value)
                                      (when (stringp var_value)
                                        (funcall 'file-exists-p var_value)))))
                        ((eq var_expected_type 'string)
                         (format "  %s? %s (should be t)\n"
                                 var_expected_type
                                 (stringp var_value)))
                        ((eq var_expected_type 'list)
                         (format "  %s? %s (should be t)\n" var_expected_type
                                 (funcall 'listp var_value)))
                        ((eq var_expected_type 'boolean)
                         (format "  %s? %s (should be t)\n" var_expected_type
                                 (funcall 'booleanp var_value)))
                        (t (format "  the type of variable is not acceptable\n"))))))))
        (dolist (pair alist)
          (let* ((var_name (car pair))
                 (var_value (when (boundp var_name) (symbol-value var_name)))
                 (var_expected_type (cdr pair))
                 (add_to_result_message_short_
                  (lambda () (funcall add_to_result_message_ var_name var_value var_expected_type))))
            (cond
             ((and (eq var_value nil) (not (eq var_expected_type 'boolean)))
              (funcall add_to_result_message_short_)
              (setq result_bool nil))
             ((eq var_expected_type 'list)
              (funcall add_to_result_message_short_)
              (unless (and (listp var_value))
                (setq result_bool nil)))
             ((eq var_expected_type 'string)
              (funcall add_to_result_message_short_)
              (unless (stringp var_value)
                (setq result_bool nil)))
             ((eq var_expected_type 'directory)
              (funcall add_to_result_message_short_)
              (unless (and
                       (stringp var_value)
                       (file-directory-p var_value)
                       (file-in-directory-p
                        (expand-file-name var_value)
                        (expand-file-name root_dir)))
                (setq result_bool nil)))
             ((eq var_expected_type 'file)
              (funcall add_to_result_message_short_)
              (unless (and
                       (stringp var_value)
                       (file-exists-p var_value))
                (setq result_bool nil)))
             ((eq var_expected_type 'boolean)
              (funcall add_to_result_message_short_)
              (unless
                  (and (booleanp var_value))
                (setq result_bool nil)))
             (t
              (funcall add_to_result_message_short_)
              (setq result_bool nil)))))
        (cons result_bool result_message))
    (cons nil "Inner Constant org-roam-organize--variable-type-alist is NOT defined properly. ")))

(defun org-roam-organize--check-capabilities (alist)
  "Check Org-roam Organize runtime capabilities in ALIST.

ALIST should map capability symbols to expected capability type symbols.
Return a cons cell whose car is the boolean result and whose cdr is a
human-readable report.  This check is capability-based rather than
version-based so package startup depends on interfaces actually available in
the running Emacs.

Implementation notes: each capability is checked with `fboundp' or `boundp'
according to its declared type.  The function mirrors
`org-roam-organize--check-variables' by collecting a full report instead of
stopping at the first missing interface."
  (if (listp alist)
      (let ((result_bool t)
            (result_message
             "All org-roam-organize runtime capabilities are as follow.\n"))
        (dolist (pair alist)
          (let* ((capability_name (car pair))
                 (capability_expected_type (cdr pair))
                 (capability_exists_p
                  (cond
                   ((eq capability_expected_type 'function)
                    (fboundp capability_name))
                   ((eq capability_expected_type 'variable)
                    (boundp capability_name))
                   (t
                    nil))))
            (setq result_message
                  (concat
                   result_message
                   (format "- %s? %s \n" capability_name capability_exists_p)
                   (format "  %s? %s (should be t)\n"
                           capability_expected_type
                           capability_exists_p)))
            (unless capability_exists_p
              (setq result_bool nil))))
        (cons result_bool result_message))
    (cons nil "Inner Constant org-roam-organize--capability-alist is NOT defined properly. ")))

(defun org-roam-organize--check-root-directory ()
  "Check whether the Org-roam Organize root is inside `org-roam-directory'.

Implementation notes: both directories are normalized with
`expand-file-name', then checked with `file-in-directory-p'.  Returning a
report cons keeps this check composable with the other setup checks."
  (let* ((root org-roam-organize-directory)
         (roam-root org-roam-directory)
         (inside-p
          (and (stringp root)
               (stringp roam-root)
               (file-in-directory-p
                (expand-file-name root)
                (file-name-as-directory (expand-file-name roam-root))))))
    (cons
     inside-p
     (concat
      "Org-roam Organize root directory is as follow.\n"
      (format "- org-roam-organize-directory? %s\n" root)
      (format "- org-roam-directory? %s\n" roam-root)
      (format "  in org-roam-directory? %s (should be t)\n" inside-p)))))

(defun org-roam-organize--record-name (record)
  "Return RECORD's name.

Implementation notes: this accessor centralizes the `:name' key so callers do
not directly depend on registry plist layout."
  (plist-get record :name))

(defun org-roam-organize--record-name-p (name)
  "Return non-nil if NAME is a safe registry record name.

Implementation notes: NAME must be a string matching the conservative record
name regexp.  That allows later path derivation to use simple concatenation
without slugifying or escaping."
  (and (stringp name)
       (string-match-p org-roam-organize--record-name-regexp name)))

(defun org-roam-organize--record-tag (record)
  "Return RECORD's managed node tag.

Implementation notes: this is a thin registry accessor; validation decides
whether the returned value is acceptable."
  (plist-get record :tag))

(defun org-roam-organize--record-moc-p (record)
  "Return non-nil if RECORD manages MOC nodes.

Implementation notes: only literal `t' enables MOC status, keeping absent and
nil equivalent and avoiding extra type semantics."
  (eq (plist-get record :moc) t))

(defun org-roam-organize--record-basic-p (record)
  "Return non-nil if RECORD is a basic registry record.

Implementation notes: only literal `t' marks a basic record.  The basic flag
is later used to decide which directories should be created and validated as
base kind directories."
  (eq (plist-get record :basic) t))

(defun org-roam-organize--record-cite-p (record)
  "Return non-nil if RECORD manages citation reference nodes.

Implementation notes: only literal `t' enables citation-reference status.
The flag is optional and is checked separately from tag, directory, and MOC
status so setups that do not use citing-node entry synchronization remain
valid."
  (eq (plist-get record :cite) t))

(defun org-roam-organize--record-backend-specification (record)
  "Return RECORD's optional interactive backend specification.

RECORD is a registry plist.  Return its `:backend' value without validating or
normalizing it; a missing key therefore returns nil.  A specification may be
a backend name or a proper list beginning with a backend name and followed by
an option plist.  This function does not load an adapter or modify RECORD.

Rationale: Adapter-specific option consumers need the original tagged value,
while lifecycle dispatch should use `org-roam-organize--record-backend'."
  (plist-get record :backend))

(defun org-roam-organize--record-backend (record)
  "Return the optional interactive backend name for RECORD.

Return the car of a cons backend specification and otherwise return its raw
value.  Registry validation is responsible for rejecting malformed tagged
specifications.  This function does not load an adapter or modify RECORD.

Implementation notes: Registry validation constrains the recognized `citar'
value to a `:cite t' record.  Runtime setup decides whether other values are
ignored and reported.

Rationale: Keeping backend access behind the registry accessor boundary avoids
coupling mode lifecycle code to the record's plist representation."
  (let ((backend
         (org-roam-organize--record-backend-specification record)))
    (if (consp backend) (car backend) backend)))

(defun org-roam-organize--record-backend-options (record)
  "Return the option plist from RECORD's tagged backend specification.

Return nil for a backend symbol, a missing backend, or a tagged specification
without options.  Registry validation is responsible for ensuring that a
non-nil return value is a proper plist.  The returned list is shared with
RECORD and must not be modified."
  (let ((backend
         (org-roam-organize--record-backend-specification record)))
    (when (consp backend) (cdr backend))))

(defun org-roam-organize--record-directory (record)
  "Return RECORD's relative node directory.

Implementation notes: this returns the raw plist value.  Path safety and
normalization are intentionally handled by the path helper functions."
  (plist-get record :directory))

(defun org-roam-organize--record-inbox (record)
  "Return RECORD's Inbox headline name.

Implementation notes: an absent `:inbox' key falls back to the package
default, while an explicitly non-string value returns nil so registry
validation can report it."
  (let ((inbox (plist-get record :inbox)))
    (cond
     ((stringp inbox) inbox)
     ((plist-member record :inbox) nil)
     (t org-roam-organize--moc-default-inbox-headline))))

(defun org-roam-organize--record-template (record)
  "Return RECORD's structured capture template spec.

Implementation notes: this accessor returns the raw `:template' plist value.
Formatting, ordering, and warning behavior are handled by the section-specific
file head and path helper functions."
  (plist-get record :template))

(defun org-roam-organize--record-template-section (record section)
  "Return RECORD's template SECTION alist, or nil.

Implementation notes: `:template' is a structured alist.  Only proper
top-level template lists are inspected.  Missing sections and malformed
section values both return nil here; validation reports malformed values
separately."
  (let ((template (org-roam-organize--record-template record)))
    (when (org-roam-organize--proper-list-p template)
      (let ((entry (assoc section template)))
        (when (org-roam-organize--proper-list-p (cdr-safe entry))
          (cdr entry))))))

(defun org-roam-organize--node-path-template-p (path)
  "Return non-nil when PATH is a safe managed node path template.

Implementation notes: ordinary managed nodes live at
`<directory>/${id}/<path>'.  This static check rejects only obviously unsafe
or non-Org paths before Org-roam placeholder expansion.  Runtime capture
checks validate the expanded target against the concrete bundle root."
  (and (stringp path)
       (not (org-roam-organize--blank-string-p path))
       (not (file-name-absolute-p path))
       (not (member path '("." "..")))
       (string-suffix-p ".org" path)))

(defun org-roam-organize--record-node-path-template-in-bundle (record)
  "Return RECORD's ordinary managed node path template inside `${id}/'.

Implementation notes: the optional `(path . VALUE)' entry in `:template' only
affects ordinary managed node capture.  MOC capture continues to use the
record's MOC path.  Missing path entries fall back to
`org-roam-organize--node-default-path-template'; invalid explicit values
return nil so callers can decline to build a target."
  (let* ((template (org-roam-organize--record-template record))
         (entry (when (org-roam-organize--proper-list-p template)
                  (assoc 'path template)))
         (path (if entry
                   (cdr entry)
                 org-roam-organize--node-default-path-template)))
    (when (org-roam-organize--node-path-template-p path)
      path)))

(defun org-roam-organize--record-provider (record)
  "Return RECORD's managed node provider.

Implementation notes: a missing or nil `:provider' value falls back to
`org-roam-organize--default-node-provider'.  Validation is responsible for
reporting non-nil provider values that cannot be called."
  (or (plist-get record :provider)
      #'org-roam-organize--default-node-provider))

(defun org-roam-organize--record-template-filetags-entry (record)
  "Return RECORD's template filetags entry, or nil.

Implementation notes: only the `keywords' section participates in Org
FILETAGS generation.  Registry validation uses the first `filetags' entry in
that section to check the core tag/filetags invariant, while template
generation still preserves repeated keyword entries."
  (assoc 'filetags
         (org-roam-organize--record-template-section record 'keywords)))

(defun org-roam-organize--registry-moc-record ()
  "Return the registry record that manages MOC nodes.

Implementation notes: malformed registry entries are filtered out before
`seq-find'.  The separate validator enforces that exactly one such record
exists."
  (seq-find #'org-roam-organize--record-moc-p
            (seq-filter #'org-roam-organize--plistp
                        org-roam-organize-registry)))

(defun org-roam-organize--registry-basic-records ()
  "Return basic records from `org-roam-organize-registry'.

Implementation notes: this filters malformed entries first, then selects
records whose `:basic' value is literal `t'.  Directory creation uses this
list as its source of truth."
  (seq-filter #'org-roam-organize--record-basic-p
              (seq-filter #'org-roam-organize--plistp
                          org-roam-organize-registry)))

(defun org-roam-organize--registry-cite-record ()
  "Return the single registry record marked with `:cite t', or nil.

Implementation notes: malformed registry entries are ignored.  Validation
ensures there is at most one citation record, while
`org-roam-organize-cite-sync' requires one at command time."
  (seq-find #'org-roam-organize--record-cite-p
            (seq-filter #'org-roam-organize--plistp
                        org-roam-organize-registry)))

(defun org-roam-organize--registry-cite-backend ()
  "Return the backend value of the configured citation registry record.

Return nil when no `:cite t' record exists or when that record has no backend.
Registry validation guarantees at most one citation record before mode setup
calls this function.  The function does not validate, load, or install the
returned backend.

Implementation notes: The citation record is selected with
`org-roam-organize--registry-cite-record' and read through
`org-roam-organize--record-backend'.

Rationale: Backend selection belongs to the unique managed citation record,
while adapter dispatch remains a separate mode-lifecycle responsibility."
  (when-let* ((record (org-roam-organize--registry-cite-record)))
    (org-roam-organize--record-backend record)))

(defun org-roam-organize--registry-cite-records ()
  "Return registry records marked with `:cite t'.

Implementation notes: malformed registry entries are ignored.  This helper is
used by the citation sync command to enforce command-time existence and
uniqueness without making citation support mandatory for setup validation."
  (seq-filter #'org-roam-organize--record-cite-p
              (seq-filter #'org-roam-organize--plistp
                          org-roam-organize-registry)))

(defun org-roam-organize--registry-node-records ()
  "Return records that can create managed non-MOC nodes.

Implementation notes: records marked as MOC are excluded, and only records
with a string `:directory' are offered.  This keeps interactive node creation
limited to records that can produce a concrete path template."
  (seq-filter
   (lambda (record)
     (and (not (org-roam-organize--record-moc-p record))
          (stringp (org-roam-organize--record-directory record))))
   (seq-filter #'org-roam-organize--plistp
               org-roam-organize-registry)))

(defun org-roam-organize--read-node-record ()
  "Read and return a registry record for managed node creation.

Implementation notes: selectable records are converted to a display alist
using their name and tag.  `completing-read' returns the display string, which
is mapped back to the original registry plist."
  (let* ((records (org-roam-organize--registry-node-records))
         (alist
          (mapcar
           (lambda (record)
             (cons (format "%s (%s)"
                           (org-roam-organize--record-name record)
                           (org-roam-organize--record-tag record))
                   record))
           records)))
    (when alist
      (let ((choice (completing-read "Node kind: " alist nil t)))
        (cdr (assoc choice alist))))))

(defun org-roam-organize--record-moc-title (record)
  "Return RECORD's MOC title.

Implementation notes: explicit `:moc-title' wins.  If the key is present but
not a string, nil is returned so validation can report it.  Otherwise a safe
record name is converted with `upcase-initials'."
  (let ((explicit-title (plist-get record :moc-title))
        (name (org-roam-organize--record-name record)))
    (cond
     ((stringp explicit-title) explicit-title)
     ((plist-member record :moc-title) nil)
     ((org-roam-organize--record-name-p name) (upcase-initials name))
     (t nil))))

(defun org-roam-organize--record-moc-path (record)
  "Return RECORD's relative MOC file path.

Implementation notes: explicit `:moc-path' wins unless it is explicitly
non-string.  Without an override, the path is derived from the single MOC
record's directory plus RECORD's safe name and `.org' suffix."
  (let ((explicit-path (plist-get record :moc-path))
        (name (org-roam-organize--record-name record)))
    (cond
     ((stringp explicit-path) explicit-path)
     ((plist-member record :moc-path) nil)
     (t
      (let* ((moc-record (org-roam-organize--registry-moc-record))
             (directory (when moc-record
                          (org-roam-organize--record-directory moc-record))))
        (when (and (org-roam-organize--record-name-p name)
                   (stringp directory))
          (concat
           (file-name-as-directory directory)
           name
           ".org")))))))

(defun org-roam-organize--path-inside-root-p (path)
  "Return non-nil if relative PATH resolves inside root directory.

Implementation notes: absolute paths are rejected first.  The relative path
is then expanded under `org-roam-organize-directory' and checked with
`file-in-directory-p' so `..' components cannot escape the root."
  (and (stringp path)
       (not (file-name-absolute-p path))
       (file-in-directory-p
        (expand-file-name path org-roam-organize-directory)
        (file-name-as-directory
         (expand-file-name org-roam-organize-directory)))))

(defun org-roam-organize--absolute-path-in-root (path)
  "Return normalized absolute PATH under root, or nil.

Implementation notes: this is the single conversion point from registry
relative paths to absolute paths.  It returns nil unless the safety predicate
accepts PATH."
  (when (org-roam-organize--path-inside-root-p path)
    (expand-file-name path org-roam-organize-directory)))

(defun org-roam-organize--absolute-path-inside-directory-p (path directory)
  "Return non-nil if absolute PATH is lexically inside DIRECTORY.

Implementation notes: unlike `file-in-directory-p', this predicate does not
require DIRECTORY to already exist.  It is used while preparing capture
targets whose UUID bundle directory may need to be created after validation."
  (when (and (stringp path)
             (stringp directory)
             (file-name-absolute-p path)
             (file-name-absolute-p directory))
    (let ((target (expand-file-name path))
          (base (file-name-as-directory
                 (expand-file-name directory))))
      (string-prefix-p base target))))

(defun org-roam-organize--record-absolute-directory (record)
  "Return RECORD's absolute node directory.

Implementation notes: the raw `:directory' value is resolved through
`org-roam-organize--absolute-path-in-root', so callers get nil for unsafe or
missing directories."
  (let ((directory (org-roam-organize--record-directory record)))
    (org-roam-organize--absolute-path-in-root directory)))

(defun org-roam-organize--record-absolute-moc-path (record)
  "Return RECORD's absolute MOC file path.

Implementation notes: the derived or explicit MOC path is resolved through
the shared root-safe path helper before any file operation sees it."
  (let ((path (org-roam-organize--record-moc-path record)))
    (org-roam-organize--absolute-path-in-root path)))

(defun org-roam-organize--record-node-path-template (record)
  "Return RECORD's managed node path template.

The standard node layout uses `org-roam-organize--node-relative-path-template'
and RECORD's bundle-relative path template under RECORD's directory inside
`org-roam-organize-directory'.
This function only builds the target path template.  Directory creation happens
later in the Org-roam capture preface hook after `${id}', `${slug}', and
provider `:info' placeholders have been expanded.

Implementation notes: the template is generated only when RECORD has a
string directory that resolves inside the root and a safe path template.
`${id}', `${slug}', and provider `:info' placeholders are left for Org-roam
capture expansion."
  (let ((directory (org-roam-organize--record-directory record))
        (path (org-roam-organize--record-node-path-template-in-bundle record)))
    (when (and (stringp directory)
               (stringp path)
               (org-roam-organize--path-inside-root-p directory))
      (expand-file-name
       (concat (file-name-as-directory directory)
               org-roam-organize--node-relative-path-template
               path)
       org-roam-organize-directory))))

(defun org-roam-organize--file-head-name (key)
  "Return Org file head name for KEY.

Implementation notes: registry template keys are symbols, so the function
uses `symbol-name' and `upcase' to map `author' to AUTHOR-style Org file
keyword or property names."
  (upcase (symbol-name key)))

(defun org-roam-organize--file-head-filetags-format (tags)
  "Return Org FILETAGS value from TAGS.

TAGS must be a list of strings.

Implementation notes: this formatter is deliberately stricter than generic
keyword formatting because FILETAGS has structured Org syntax.  Invalid input
returns nil so the caller can warn and skip the line."
  (when (and (listp tags)
             (seq-every-p #'stringp tags))
    (format ":%s:" (mapconcat #'identity tags ":"))))

(defun org-roam-organize--file-head-entry-value (entry)
  "Return formatted file head value for ENTRY, or nil.

Implementation notes: ENTRY is read as an alist cell.  Special keys use
`org-roam-organize--file-head-formatter-alist'; all other keys use
`identity'.  String values are preserved as capture-template text and may
contain Org capture escapes or Org-roam placeholders.  Nil intentionally
returns the empty string so callers can emit empty property or keyword values,
while non-string formatted results are ignored with a warning."
  (let* ((key (car-safe entry))
         (value (cdr-safe entry))
         (formatter
          (or (cdr (assoc key org-roam-organize--file-head-formatter-alist))
              #'identity)))
    (cond
     ((not (symbolp key))
      (message "[WARNING] Ignored invalid file head template entry: %s" entry)
      nil)
     ((null value)
      "")
     ((functionp formatter)
      (let ((formatted (funcall formatter value)))
        (if (stringp formatted) formatted
          (message "[WARNING] Ignored invalid file head template value: %s" entry)
          nil)))
     (t
      (message "[WARNING] Ignored invalid file head template value: %s" entry)
      nil))))

(defun org-roam-organize--file-head-keyword-line (entry)
  "Return Org file keyword line for ENTRY, or nil.

Implementation notes: this formats one `keywords' section entry by delegating
value serialization to `org-roam-organize--file-head-entry-value', then adds
the Org `#+KEYWORD:' syntax."
  (let ((key (car-safe entry))
        (value (org-roam-organize--file-head-entry-value entry)))
    (when (and (symbolp key) (stringp value))
      (if (string= value "")
          (format "#+%s:\n" (org-roam-organize--file-head-name key))
        (format "#+%s: %s\n"
                (org-roam-organize--file-head-name key)
                value)))))

(defun org-roam-organize--file-head-property-line (entry)
  "Return Org property drawer line for ENTRY, or nil.

Implementation notes: this formats one `properties' section entry by
delegating value serialization to
`org-roam-organize--file-head-entry-value', then adds Org drawer property
syntax."
  (let ((key (car-safe entry))
        (value (org-roam-organize--file-head-entry-value entry)))
    (when (and (symbolp key) (stringp value))
      (if (string= value "")
          (format ":%s:\n" (org-roam-organize--file-head-name key))
        (format ":%s: %s\n"
                (org-roam-organize--file-head-name key)
                value)))))

(defun org-roam-organize--record-file-keyword-lines (record)
  "Return optional Org file keyword lines for RECORD.

Implementation notes: only the `keywords' section is emitted here.  Each
entry is formatted independently and pushed into a temporary list, then
reversed so repeated keys and user-specified ordering are preserved."
  (let ((keywords (org-roam-organize--record-template-section record 'keywords))
        lines)
    (dolist (entry keywords)
      (let ((line (org-roam-organize--file-head-keyword-line entry)))
        (when line
          (push line lines))))
    (apply #'concat (nreverse lines))))

(defun org-roam-organize--record-file-property-lines (record)
  "Return optional Org property drawer lines for RECORD.

Implementation notes: only the `properties' section is emitted here.  The
returned string contains property lines without the surrounding drawer markers
so callers can merge package-managed properties and user-declared properties
into one drawer."
  (let ((properties (org-roam-organize--record-template-section record 'properties))
        lines)
    (dolist (entry properties)
      (let ((line (org-roam-organize--file-head-property-line entry)))
        (when line
          (push line lines))))
    (apply #'concat (nreverse lines))))

(defun org-roam-organize--record-file-property-drawer (record)
  "Return optional Org property drawer for RECORD.

Implementation notes: ordinary managed nodes only get a property drawer when
the record declares a non-empty `properties' section.  MOC heads use
`org-roam-organize--record-file-property-lines' directly to merge custom
properties with package-managed MOC metadata."
  (let ((properties (org-roam-organize--record-file-property-lines record)))
    (if (string= properties "")
        ""
      (concat ":PROPERTIES:\n" properties ":END:\n"))))

(defun org-roam-organize--record-node-head (record)
  "Return the Org file head for RECORD's managed node file.

Implementation notes: node heads include any user-declared property drawer,
then Org-roam's `${title}' placeholder, followed by user-declared file
keywords.  ID writing is left to Org-roam capture."
  (let ((tag (org-roam-organize--record-tag record)))
    (when (stringp tag)
      (concat
       (org-roam-organize--record-file-property-drawer record)
       "#+TITLE: ${title}\n"
       (org-roam-organize--record-file-keyword-lines record)))))

(defun org-roam-organize--record-moc-head (record)
  "Return the Org file head for RECORD's MOC file.

Implementation notes: MOC files get a leading property drawer that merges
package-managed MOC metadata with user-declared template properties, followed
by a title and user-declared file keywords."
  (let ((tag (org-roam-organize--record-tag record))
        (title (org-roam-organize--record-moc-title record)))
    (when (and (stringp tag)
               (stringp title))
      (concat
       (format ":PROPERTIES:\n:%s: %s\n:%s:\n"
               org-roam-organize-moc-managed-tag-property
               tag
               org-roam-organize-moc-managed-node-count-property)
       (org-roam-organize--record-file-property-lines record)
       ":END:\n"
       (format "#+TITLE: %s\n" title)
       (org-roam-organize--record-file-keyword-lines record)))))

(defun org-roam-organize--empty-directory-p (directory)
  "Return non-nil if DIRECTORY is an empty directory.

Implementation notes: the check delegates existence/type handling to
`file-directory-p' and uses `directory-files-no-dot-files-regexp' so `.' and
`..' do not count as contents."
  (and (file-directory-p directory)
       (null (directory-files directory nil directory-files-no-dot-files-regexp))))

(defun org-roam-organize--capture-delete-directory (directory aborted)
  "Clean capture-created DIRECTORY.

If DIRECTORY is empty, delete it automatically.  If ABORTED is non-nil and
DIRECTORY is non-empty, ask before deleting it recursively in interactive
sessions.

Implementation notes: DIRECTORY is always expected to be the managed node
bundle root, not the final target file's parent.  Recursive deletion is
guarded by `yes-or-no-p' and is never attempted in noninteractive sessions."
  (when (and (stringp directory)
             (org-roam-organize--path-inside-root-p
              (file-relative-name directory org-roam-organize-directory))
             (file-directory-p directory))
    (cond
     ((org-roam-organize--empty-directory-p directory)
      (delete-directory directory))
     ((and aborted
           (not noninteractive)
           (yes-or-no-p
            (format "Delete non-empty aborted capture bundle %s? " directory)))
      (delete-directory directory t)))))

(defun org-roam-organize--capture-target-file ()
  "Return the active Org-roam capture file target, or nil.

Implementation notes: the function mirrors Org-roam's file-like target
variants and resolves each target path through
`org-roam-capture--target-truepath'.  Non-file targets return nil because
there is no parent directory to prepare."
  (pcase (org-roam-capture--get-target)
    (`(file ,path)
     (org-roam-capture--target-truepath path))
    (`(file+head ,path ,_head)
     (org-roam-capture--target-truepath path))
    (`(file+olp ,path ,_olp)
     (org-roam-capture--target-truepath path))
    (`(file+head+olp ,path ,_head ,_olp)
     (org-roam-capture--target-truepath path))
    (`(file+datetree ,path ,_tree-type)
     (org-roam-capture--target-truepath path))
    (_ nil)))

(defun org-roam-organize--capture-target-bundle-directory (record target-file)
  "Return RECORD's expanded bundle directory for TARGET-FILE.

Implementation notes: TARGET-FILE must be an expanded Org file target inside
RECORD's absolute directory with at least one bundle-id component below that
directory.  The returned directory is `<directory>/<id>/'.  This function
does not require the path inside the bundle to be flat."
  (let* ((base-directory (org-roam-organize--record-absolute-directory record))
         (target (and (stringp target-file)
                      (expand-file-name target-file)))
         (base (and base-directory
                    (file-name-as-directory
                     (expand-file-name base-directory)))))
    (when (and target
               base
               (string-suffix-p ".org" target)
               (org-roam-organize--absolute-path-inside-directory-p
                target
                base))
      (let* ((relative (file-relative-name target base))
             (components (split-string relative "/" t))
             (bundle-id (car components))
             (bundle-directory
              (and bundle-id
                   (expand-file-name
                    (file-name-as-directory bundle-id)
                    base))))
        (when (and (>= (length components) 2)
                   (not (org-roam-organize--blank-string-p bundle-id))
                   (not (member bundle-id '("." "..")))
                   bundle-directory
                   (not (file-symlink-p bundle-directory))
                   (org-roam-organize--absolute-path-inside-directory-p
                    target
                    bundle-directory))
          bundle-directory)))))

(defun org-roam-organize--capture-create-target-directory (record)
  "Create target parent directory for active managed node capture RECORD.

Return nil so `org-roam-capture-preface-hook' continues with Org-roam's
normal target setup when no directory is created.

Implementation notes: this hook runs after Org-roam has enough capture state
to expand `${id}', `${slug}', and provider `:info' placeholders.  It returns
the managed bundle root so the caller can clean that root later."
  (let* ((file (org-roam-organize--capture-target-file))
         (bundle-directory
          (org-roam-organize--capture-target-bundle-directory record file))
         (target-directory (and file (file-name-directory file))))
    (unless bundle-directory
      (user-error "Managed node capture target escaped its bundle: %s" file))
    (unless (file-directory-p bundle-directory)
      (make-directory bundle-directory t))
    (when (and target-directory
               (org-roam-organize--absolute-path-inside-directory-p
                target-directory
                bundle-directory)
               (not (file-directory-p target-directory)))
      (make-directory target-directory t))
    bundle-directory))

(defun org-roam-organize--capture-aborted-p ()
  "Return non-nil when the current Org capture is being aborted.

Implementation notes: Org binds `org-note-abort' while running capture
finalization hooks.  `bound-and-true-p' keeps this helper safe outside that
dynamic context."
  (bound-and-true-p org-note-abort))

(defun org-roam-organize--capture-node
    (title template &optional info props managed-record on-success)
  "Capture an Org-roam node with TITLE and TEMPLATE.

INFO and PROPS are passed through to `org-roam-capture-'.  When MANAGED-RECORD
is non-nil, create the expanded target's parent directory during Org-roam's
capture preface phase and clean the managed bundle root after capture.  When
ON-SUCCESS is non-nil, it must be a function of no arguments; call it once in
the capture buffer after successful finalization, but not when capture is
aborted.  Signal `user-error' before starting capture when ON-SUCCESS is
neither nil nor a function.

Implementation notes: this helper centralizes the capture call boundary used
by managed ordinary nodes and MOC nodes.  Ordinary nodes pass their registry
record so the bundle root can be computed after Org-roam expands capture
placeholders.  An `org-capture-after-finalize-hook' closure owns both
ON-SUCCESS dispatch and managed-directory cleanup.  It removes itself before
invoking caller code and uses `unwind-protect' so callback errors do not skip
cleanup scheduling.

Rationale: integrations may need to commit buffer-local metadata only after a
capture succeeds.  Keeping that transaction boundary here avoids treating an
interactive `org-roam-capture-' return as proof of successful finalization."
  (let ((key (car-safe template)))
    (unless (and (stringp title)
                 (not (org-roam-organize--blank-string-p title)))
      (user-error "Node title cannot be empty"))
    (unless (and template key)
      (user-error "Cannot capture node without a valid template"))
    (unless (or (null on-success) (functionp on-success))
      (user-error "Capture success callback must be a function"))
    (let ((node (org-roam-node-create :title title)))
      (let (created-directory finalize-hook)
        (cl-labels
            ((finalize ()
               (remove-hook 'org-capture-after-finalize-hook finalize-hook)
               (let ((aborted (org-roam-organize--capture-aborted-p)))
                 (unwind-protect
                     (when (and on-success (not aborted))
                       (funcall on-success))
                   (when created-directory
                     (run-at-time
                      0 nil
                      #'org-roam-organize--capture-delete-directory
                      created-directory
                      aborted)))))
             (create-parent-directory ()
               (setq created-directory
                     (org-roam-organize--capture-create-target-directory
                      managed-record))
               nil))
          (setq finalize-hook #'finalize)
          (when (or managed-record on-success)
            (add-hook 'org-capture-after-finalize-hook finalize-hook t))
          (let ((org-roam-capture-preface-hook
                 (if managed-record
                     (cons #'create-parent-directory
                           org-roam-capture-preface-hook)
                   org-roam-capture-preface-hook)))
            (condition-case err
                (org-roam-capture- :node node
                                   :keys key
                                   :info info
                                   :props props
                                   :templates (list template))
              (error
               (remove-hook 'org-capture-after-finalize-hook finalize-hook)
               (when created-directory
                 (org-roam-organize--capture-delete-directory
                  created-directory
                  t))
               (signal (car err) (cdr err))))))))))

(defun org-roam-organize--default-node-provider (_record)
  "Return the default managed node creation request.

The return value is nil when creation is canceled, otherwise a plist with
`:title' and optional `:info'.

Implementation notes: this provider reads only a title and leaves dynamic
capture info empty.  It ignores the registry record argument because default
ordinary node creation only needs a title.  Path, target, template, and
capture lifecycle remain outside the provider request."
  (let ((title (read-string "Node title: ")))
    (unless (org-roam-organize--blank-string-p title)
      (list :title title))))

(defun org-roam-organize--moc-node-provider (record)
  "Return RECORD's MOC node creation request.

The return value is nil when RECORD cannot produce a MOC title, otherwise a
plist with `:title' and optional `:info'.

Implementation notes: MOC creation uses the same provider request protocol as
ordinary managed node creation, but the provider is selected internally by the
MOC creation command instead of being read from the registry.  The title is
derived from `org-roam-organize--record-moc-title'.  The capture info keeps
the existing `:moc_managed_tag' field so templates that still reference it
continue to receive the same dynamic value."
  (let ((title (org-roam-organize--record-moc-title record))
        (tag (org-roam-organize--record-tag record)))
    (when (stringp title)
      (list :title title
            :info `(:moc_managed_tag ,tag)))))

(defun org-roam-organize--node-request-valid-p (request)
  "Return non-nil if REQUEST can create a managed node.

Implementation notes: a request must be a proper plist with a non-empty
string `:title'.  `:info' is optional, but when present it must also be a
proper plist because it is passed through to `org-roam-capture-'.  Extra
request keys are ignored by callers so the provider protocol can grow
without breaking existing providers."
  (and (org-roam-organize--plistp request)
       (let ((title (plist-get request :title))
             (info (plist-get request :info)))
         (and (stringp title)
              (not (org-roam-organize--blank-string-p title))
              (or (null info)
                  (org-roam-organize--plistp info))))))

(defun org-roam-organize--proper-list-p (object)
  "Return non-nil if OBJECT is a proper list.

Implementation notes: the cdr chain is walked manually instead of using
`length' so dotted lists return nil instead of signaling an error."
  (let ((tail object))
    (while (consp tail)
      (setq tail (cdr tail)))
    (null tail)))

(defun org-roam-organize--plistp (object)
  "Return non-nil if OBJECT is a plist-like proper list.

Implementation notes: a plist-like value must first be a proper list and then
have an even number of elements.  Key/value semantics are validated
elsewhere."
  (and (org-roam-organize--proper-list-p object)
       (= 0 (% (length object) 2))))

(defun org-roam-organize--validate-registry ()
  "Validate `org-roam-organize-registry'.

Return a cons cell whose car is the boolean result and whose cdr is a
human-readable report.

Implementation notes: validation is deliberately report-oriented.  It first
rejects an improper top-level registry, then walks records once, guarding all
derived values behind plist checks so malformed records are reported instead
of crashing.  It also checks uniqueness using normalized absolute paths and
keeps template validation focused on the structured file head shape and the
tag/filetags invariant.  Provider validation is intentionally shallow: a
non-nil `:provider' must be callable, while provider return values are
checked when node creation calls the provider."
  (let ((result_bool t)
        (result_message "Org-roam Organize registry records are as follow.\n")
        (moc-count 0)
        (cite-count 0)
        names tags paths directories)
    (if (not (org-roam-organize--proper-list-p org-roam-organize-registry))
        (cons nil "`org-roam-organize-registry' must be a proper list.")
      (dolist (record org-roam-organize-registry)
        (let* ((plistp (org-roam-organize--plistp record))
               (name (when plistp (org-roam-organize--record-name record)))
               (tag (when plistp (org-roam-organize--record-tag record)))
               (moc (when plistp (plist-get record :moc)))
               (basic (when plistp (plist-get record :basic)))
               (cite (when plistp (plist-get record :cite)))
               (backend-specification
                (when plistp
                  (org-roam-organize--record-backend-specification record)))
               (backend (when plistp
                          (org-roam-organize--record-backend record)))
               (backend-options
                (when plistp
                  (org-roam-organize--record-backend-options record)))
               (directory (when plistp (org-roam-organize--record-directory record)))
               (inbox (when plistp (org-roam-organize--record-inbox record)))
               (provider (when plistp (plist-get record :provider)))
               (template (when plistp (plist-get record :template)))
               (filetags-entry (when plistp
                                 (org-roam-organize--record-template-filetags-entry record)))
               (filetags (cdr-safe filetags-entry))
               (moc-path (when plistp (org-roam-organize--record-moc-path record)))
               (moc-title (when plistp (org-roam-organize--record-moc-title record)))
               (absolute-directory
                (when (and plistp (stringp directory))
                  (org-roam-organize--record-absolute-directory record)))
               (absolute-moc-path
                (when (and plistp (stringp moc-path))
                  (org-roam-organize--record-absolute-moc-path record))))
          (setq result_message
                (concat result_message
                        (format "- %s\n" (if plistp record "<invalid record>"))))
          (unless plistp
            (setq result_bool nil)
            (setq result_message
                  (concat result_message "  plist? nil (should be t)\n")))
          (when plistp
            (unless (org-roam-organize--record-name-p name)
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :name safe string? nil (should match [A-Za-z0-9_-]+)\n")))
            (unless (stringp tag)
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :tag string? nil (should be t)\n")))
            (when (and moc (not (booleanp moc)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :moc boolean? nil (should be t)\n")))
            (when (and basic (not (booleanp basic)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :basic boolean? nil (should be t)\n")))
            (when (and cite (not (booleanp cite)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :cite boolean? nil (should be t)\n")))
            (when (org-roam-organize--record-moc-p record)
              (setq moc-count (1+ moc-count))
              (unless (org-roam-organize--record-basic-p record)
                (setq result_bool nil)
                (setq result_message
                      (concat result_message "  :moc t requires :basic t\n"))))
            (when (org-roam-organize--record-cite-p record)
              (setq cite-count (1+ cite-count)))
            (when (and (eq backend 'citar)
                       (not (org-roam-organize--record-cite-p record)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message
                            "  :backend citar requires :cite t\n")))
            (when (and (consp backend-specification)
                       (or (not
                            (org-roam-organize--proper-list-p
                             backend-specification))
                           (not (symbolp backend))
                           (not (org-roam-organize--plistp
                                 backend-options))))
              (setq result_bool nil)
              (setq result_message
                    (concat
                     result_message
                     "  tagged :backend must be (BACKEND OPTION VALUE...)\n")))
            (cond
             ((org-roam-organize--record-basic-p record)
              (unless (stringp directory)
                (setq result_bool nil)
                (setq result_message
                      (concat result_message "  :basic t requires string :directory\n")))))
            (when (and (plist-member record :moc-path)
                       (not (stringp (plist-get record :moc-path))))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :moc-path string? nil (should be t)\n")))
            (when (and (plist-member record :moc-title)
                       (not (stringp (plist-get record :moc-title))))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :moc-title string? nil (should be t)\n")))
            (when (and (plist-member record :inbox)
                       (not (stringp (plist-get record :inbox))))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :inbox string? nil (should be t)\n")))
            (when (and provider (not (functionp provider)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :provider function? nil (should be t)\n")))
            (when (and (plist-member record :template)
                       (not (org-roam-organize--proper-list-p
                             template)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template proper list? nil (should be t)\n")))
            (when (and (org-roam-organize--proper-list-p template)
                       (seq-find
                        (lambda (section)
                          (not (memq (car-safe section) '(path properties keywords))))
                        template))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template section keys? nil (should be path, properties, or keywords)\n")))
            (when (and (org-roam-organize--proper-list-p template)
                       (org-roam-organize--record-moc-p record)
                       (assoc 'path template))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :moc t cannot use :template path\n")))
            (when (and (org-roam-organize--proper-list-p template)
                       (assoc 'path template)
                       (not (org-roam-organize--node-path-template-p
                             (cdr (assoc 'path template)))))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template path safe org file? nil (should be relative .org path)\n")))
            (when (and (org-roam-organize--proper-list-p template)
                       (seq-find
                        (lambda (section)
                          (and (memq (car-safe section) '(properties keywords))
                               (not (org-roam-organize--proper-list-p (cdr-safe section)))))
                        template))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template sections proper list? nil (should be t)\n")))
            (when (and filetags-entry
                       (not (and (org-roam-organize--proper-list-p filetags)
                                 (seq-every-p #'stringp filetags))))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template filetags string list? nil (should be t)\n")))
            (when (and (stringp tag)
                       filetags-entry
                       (and (org-roam-organize--proper-list-p filetags)
                            (seq-every-p #'stringp filetags))
                       (not (member tag filetags)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template filetags include :tag? nil (should be t)\n")))
            (when (and (plist-member record :moc-path)
                       (stringp (plist-get record :moc-path))
                       (file-name-absolute-p (plist-get record :moc-path)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :moc-path relative? nil (should be t)\n")))
            (when (and (stringp moc-path)
                       (not (org-roam-organize--path-inside-root-p moc-path)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :moc-path inside root? nil (should be t)\n")))
            (when (and (stringp directory) (file-name-absolute-p directory))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :directory relative? nil (should be t)\n")))
            (when (and (stringp directory)
                       (not (org-roam-organize--path-inside-root-p directory)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :directory inside root? nil (should be t)\n")))
            (when (and (org-roam-organize--record-name-p name) (member name names))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :name unique? nil (should be t)\n")))
            (when (org-roam-organize--record-name-p name)
              (push name names))
            (when (and (stringp tag) (member tag tags))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :tag unique? nil (should be t)\n")))
            (when (stringp tag)
              (push tag tags))
            (when (and absolute-moc-path (member absolute-moc-path paths))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :moc-path unique? nil (should be t)\n")))
            (when absolute-moc-path
              (push absolute-moc-path paths))
            (when (and (org-roam-organize--record-basic-p record)
                       absolute-directory
                       (member absolute-directory directories))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved basic :directory unique? nil (should be t)\n")))
            (when (and (org-roam-organize--record-basic-p record)
                       absolute-directory)
              (push absolute-directory directories))
            (unless (stringp moc-title)
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :moc-title string? nil (should be t)\n")))
            (unless (stringp inbox)
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :inbox string? nil (should be t)\n"))))))
      (unless (= moc-count 1)
        (setq result_bool nil)
        (setq result_message
              (concat result_message
                      (format "Exactly one :moc t record? %s (should be 1)\n"
                              moc-count))))
      (when (> cite-count 1)
        (setq result_bool nil)
        (setq result_message
              (concat result_message
                      (format "At most one :cite t record? %s (should be 0 or 1)\n"
                              cite-count))))
      (cons result_bool result_message))))

(defun org-roam-organize--check-setup ()
  "Check whether Org-roam Organize can be enabled.

Return a cons cell whose car is the boolean result and whose cdr is a
human-readable report.

Implementation notes: setup is the conjunction of variable checks, root
checks, registry validation, and runtime capability checks.  Each subcheck
still contributes its full diagnostic text so the user can fix multiple
problems in one pass."
  (let ((variable_check_result
         (org-roam-organize--check-variables
          org-roam-organize-directory
          org-roam-organize--variable-type-alist))
        (root_check_result
         (org-roam-organize--check-root-directory))
        (registry_check_result
         (org-roam-organize--validate-registry))
        (capability_check_result
         (org-roam-organize--check-capabilities
          org-roam-organize--capability-alist)))
    (cons
     (and (car variable_check_result)
          (car root_check_result)
          (car registry_check_result)
          (car capability_check_result))
     (concat
      (format "Variable validation result: %s\n"
              (if (car variable_check_result) "passed" "failed"))
      (cdr variable_check_result)
      (format "Root directory validation result: %s\n"
              (if (car root_check_result) "passed" "failed"))
      (cdr root_check_result)
      (format "Registry validation result: %s\n"
              (if (car registry_check_result) "passed" "failed"))
      (cdr registry_check_result)
      (format "Runtime capability validation result: %s\n"
              (if (car capability_check_result) "passed" "failed"))
      (cdr capability_check_result)))))

;; 根据 registry 和 org-roam 数据库获得 tag 和 MOC id 的对应关系
(defun org-roam-organize--moc-node-id-by-path (path)
  "Return the level-0 Org-roam node id for absolute file PATH.

Implementation notes: the query looks up the `nodes' table by exact absolute
file path and requires level 0 so headline nodes do not masquerade as MOC
file nodes.  The SQL form is built with `vector' syntax for consistency with
dynamic EmacSQL query construction."
  (caar
   (org-roam-db-query
    (vector :select (vector 'n:id)
            :from '(as nodes n)
            :where '(and (= n:level 0) (= n:file $s1)))
    path)))

(defun org-roam-organize--registry-tag-id-alist ()
  "Return an alist of managed tag to MOC node id from registry records.

Implementation notes: each registry record is resolved to its MOC path, then
looked up in the Org-roam database.  The result cons keeps successful
TAG . ID pairs in the car and unresolved records in the cdr so callers can
distinguish partial failure from an empty registry."
  (let (output missing-records)
    (dolist (record org-roam-organize-registry)
      (let* ((tag (org-roam-organize--record-tag record))
             (path (org-roam-organize--record-absolute-moc-path record))
             (id (when path
                   (org-roam-organize--moc-node-id-by-path path))))
        (if (and tag id)
            (push (cons tag id) output)
          (push record missing-records))))
    (cons (nreverse output) (nreverse missing-records))))

(defun org-roam-organize--record-node-capture-template (record)
  "Return a managed node capture template for RECORD.

Implementation notes: this builds a one-template Org-roam capture list using
the registry-derived node path template and file head.  It does not register
the template globally; callers pass it directly to `org-roam-capture-'."
  (let ((path (org-roam-organize--record-node-path-template record))
        (head (org-roam-organize--record-node-head record)))
    (when (and (stringp path) (stringp head))
      (list org-roam-organize--node-capture-key
            (format "%s node" (org-roam-organize--record-name record))
            'plain
            "%?"
            :target
            (list 'file+head path head)
            :unnarrowed t))))

(defun org-roam-organize--record-moc-capture-template (record)
  "Return a MOC capture template for RECORD.

Implementation notes: MOC creation uses the same capture protocol as normal
node creation, but targets a fixed absolute MOC path instead of the managed
node relative path template."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (head (org-roam-organize--record-moc-head record)))
    (when (and (stringp path) (stringp head))
      (list org-roam-organize--moc-capture-key
            "map of contents"
            'plain
            "%?"
            :target
            (list 'file+head path head)
            :unnarrowed t))))

(defun org-roam-organize--nodes-with-tag (tag)
  "Return level-0 Org-roam nodes with TAG.

The return value is a list of plists containing `:id' and `:title'.

Implementation notes: the query joins `tags' to level-0 `nodes' and maps
database rows to small plists used by MOC sync.  Membership is derived from
Org-roam's database, which itself is derived from Org files."
  (when org-roam-organize-mode
    (mapcar
     (lambda (row)
       (list :id (nth 0 row)
             :title (nth 1 row)))
     (org-roam-db-query
      (vector :select (vector 'n:id 'n:title)
              :from '(as tags t)
              :join '(as nodes n)
              :on '(and (= n:level 0) (= n:id t:node_id))
              :where '(= t:tag $s1))
      tag))))

(defun org-roam-organize--nodes-with-tag-and-file (tag)
  "Return level-0 Org-roam nodes with TAG, including file paths.

The return value is a list of plists containing `:id', `:title', and `:file'.

Implementation notes: this is used by cite synchronization, which needs
to update each literature node file even when that node currently has no
incoming citing-node entries.  The query uses the same tag-membership source
as MOC sync and extends the selected node fields with `nodes.file'."
  (when org-roam-organize-mode
    (mapcar
     (lambda (row)
       (list :id (nth 0 row)
             :title (nth 1 row)
             :file (nth 2 row)))
     (org-roam-db-query
      (vector :select (vector 'n:id 'n:title 'n:file)
              :from '(as tags t)
              :join '(as nodes n)
              :on '(and (= n:level 0) (= n:id t:node_id))
              :where '(= t:tag $s1))
      tag))))

(defun org-roam-organize--id-link-keyword-entry-line
    (keyword id title &optional suffix)
  "Return an Org KEYWORD entry line linking to ID with TITLE.

Implementation notes: `org-link-make-string' constructs the id link so link
descriptions are escaped according to Org syntax.  Optional SUFFIX text is
appended after the link and otherwise left uninterpreted here so specialized
callers can preserve their own keyword metadata."
  (format "#+%s: %s%s\n"
          keyword
          (org-link-make-string (concat "id:" id) title)
          (or suffix "")))

(defun org-roam-organize--moc-node-entry-line (id title &optional delete)
  "Return a MOC node entry line for ID, TITLE, and DELETE flag.

Implementation notes: this is the MOC-specific wrapper around
`org-roam-organize--id-link-keyword-entry-line'.  It fixes the keyword name
to `org-roam-organize--moc-node-keyword' and serializes the existing
`:delete t' marker when requested."
  (org-roam-organize--id-link-keyword-entry-line
   org-roam-organize--moc-node-keyword
   id
   title
   (when delete " :delete t")))

(defun org-roam-organize--moc-node-entry-delete-p (suffix)
  "Return non-nil if MOC node entry SUFFIX contains `:delete t'.

Implementation notes: the suffix is read as Lisp data into a plist-like list,
then queried with `plist-get'.  Read errors are caught and treated as a
non-delete marker so malformed suffixes do not break MOC parsing."
  (when (stringp suffix)
    (condition-case nil
        (let ((start 0)
              values)
          (while (< start (length suffix))
            (let ((result (read-from-string suffix start)))
              (push (car result) values)
              (setq start (cdr result))))
          (eq (plist-get (nreverse values) :delete) t))
      (error nil))))

(defun org-roam-organize--blank-string-p (string)
  "Return non-nil if STRING contains only whitespace.

Implementation notes: this intentionally checks a small whitespace character
set directly.  It is used while parsing keyword values where an empty prefix
before the first Org link is required."
  (cl-every (lambda (char)
              (memq char '(?\s ?\t ?\n ?\r)))
            string))

(defun org-roam-organize--report-lines-message (lines)
  "Return a message string built from report LINES.

Implementation notes: commands collect diagnostics as plain line strings and
only join them at the display boundary.  This keeps newline handling localized
and makes later report-buffer rendering a small change."
  (mapconcat #'identity (seq-filter #'identity lines) "\n"))

(defun org-roam-organize--report-content (content)
  "Return report CONTENT as a string.

Implementation notes: callers may already have a full report string, or they
may have collected report lines.  This helper keeps that conversion in one
place so command code does not duplicate newline handling."
  (cond
   ((stringp content) content)
   ((listp content) (org-roam-organize--report-lines-message content))
   (t (format "%s" content))))

(defun org-roam-organize--display-report (title content)
  "Display a read-only report buffer for TITLE and CONTENT.

Implementation notes: the report buffer is intentionally overwritten on each
call.  It uses `special-mode' so the buffer behaves like a normal Emacs
read-only information buffer.  History and append-style logging are left out so
each interactive command owns one final report."
  (let ((buffer (get-buffer-create org-roam-organize--report-buffer-name))
        (body (org-roam-organize--report-content content)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert title "\n"
                (make-string (length title) ?=)
                "\n\n"
                body)
        (unless (string-suffix-p "\n" body)
          (insert "\n"))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(defun org-roam-organize--report-notice (level summary)
  "Return a minibuffer notice for report LEVEL and SUMMARY.

LEVEL is a symbol such as `info', `warning', or `error'.  SUMMARY is a short
one-line string.  The returned text points users to
`org-roam-organize--report-buffer-name' for details."
  (format "[%s] %s See %s for details."
          (upcase (symbol-name level))
          summary
          org-roam-organize--report-buffer-name))

(defun org-roam-organize--element-in-comment-subtree-p (element)
  "Return non-nil if ELEMENT belongs to a COMMENT subtree.

Implementation notes: Org Element nodes have parent links, so the
implementation walks ancestors until it finds a commented headline or reaches
the root."
  (let ((parent (org-element-property :parent element))
        found)
    (while (and parent (not found))
      (when (and (eq (org-element-type parent) 'headline)
                 (org-element-property :commentedp parent))
        (setq found t))
      (setq parent (org-element-property :parent parent)))
    found))

(defun org-roam-organize--element-commented-p (element)
  "Return non-nil if ELEMENT is in COMMENT context.

Implementation notes: a value is considered commented when it is itself a
commented headline or when any ancestor headline is commented.  This keeps
MOC parsing from touching COMMENT subtrees."
  (or (and (eq (org-element-type element) 'headline)
           (org-element-property :commentedp element))
      (org-roam-organize--element-in-comment-subtree-p element)))

(defun org-roam-organize--parse-id-link-keyword-entry-value
    (value &optional suffix-parser)
  "Parse an id-link keyword VALUE.

Return a plist with `:id' and `:title', plus any plist returned by
SUFFIX-PARSER.  Return nil when VALUE does not contain a valid id link at the
beginning.

Implementation notes: VALUE is parsed in a temporary Org buffer so link
syntax is handled by Org Element rather than regular expressions.  Only the
first id link with no non-whitespace prefix is accepted; text after the link
is passed to SUFFIX-PARSER when provided."
  (with-temp-buffer
    (insert value)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           link-result)
      (org-element-map ast 'link
        (lambda (link)
          (unless link-result
            (let ((prefix (buffer-substring-no-properties
                           (point-min)
                           (org-element-property :begin link))))
              (when (and (org-roam-organize--blank-string-p prefix)
                         (string= (org-element-property :type link) "id")
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link))
                (let* ((description
                        (buffer-substring-no-properties
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link)))
                       (suffix
                        (buffer-substring-no-properties
                         (org-element-property :end link)
                         (point-max))))
                  (setq link-result
                        (append
                         (list
                          :id (org-element-property :path link)
                          :title description)
                         (when suffix-parser
                           (funcall suffix-parser suffix))))))))))
      link-result)))

(defun org-roam-organize--moc-parse-node-entry-value (value)
  "Parse a MOC node entry keyword VALUE.

Return a plist with `:id', `:title', and `:delete', or nil when VALUE does
not contain a valid id link at the beginning.

Implementation notes: this MOC-specific wrapper delegates id-link parsing to
`org-roam-organize--parse-id-link-keyword-entry-value' and only adds parsing
of the MOC `:delete t' suffix."
  (org-roam-organize--parse-id-link-keyword-entry-value
   value
   (lambda (suffix)
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))))

(defun org-roam-organize--parse-id-link-keyword-entries
    (keyword-name &optional suffix-parser)
  "Parse id-link entries for KEYWORD-NAME in the current buffer.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:begin', and `:end', plus any data supplied by
SUFFIX-PARSER.

Implementation notes: the current buffer is parsed with Org Element and only
real keyword elements matching KEYWORD-NAME outside COMMENT context are
considered.  Malformed lines are retained as strings for reporting, while
legal entries carry buffer positions so sync can replace or remove them
later."
  (let (entries malformed)
    (org-element-map (org-element-parse-buffer) 'keyword
      (lambda (keyword)
        (when (and (string= (org-element-property :key keyword)
                            keyword-name)
                   (not
                    (org-roam-organize--element-commented-p keyword)))
          (let* ((begin (org-element-property :begin keyword))
                 (end (org-element-property :end keyword))
                 (value (org-element-property :value keyword))
                 (parsed
                  (org-roam-organize--parse-id-link-keyword-entry-value
                   value
                   suffix-parser)))
            (if parsed
                (push (append parsed
                              (list :begin begin
                                    :end end))
                      entries)
              (push (buffer-substring-no-properties
                     begin
                     (save-excursion
                       (goto-char begin)
                       (line-end-position)))
                    malformed))))))
    (list :entries (nreverse entries)
          :malformed (nreverse malformed))))

(defun org-roam-organize--moc-parse-node-entries ()
  "Parse MOC node entries in the current buffer.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:delete', `:begin', and `:end'.

Implementation notes: this MOC-specific wrapper parses real
`#+ROAM_NODE' keyword elements by delegating to
`org-roam-organize--parse-id-link-keyword-entries' and adding MOC delete
suffix parsing."
  (org-roam-organize--parse-id-link-keyword-entries
   org-roam-organize--moc-node-keyword
   (lambda (suffix)
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))))

(defun org-roam-organize--inbox-headline (name)
  "Return the top-level Inbox headline element named NAME in the current buffer.

Implementation notes: this scans headline elements and accepts only the first
non-commented level-1 headline whose raw title equals NAME.  Regex matching
is avoided so source blocks, COMMENT subtrees, and nested headlines do not
become false inboxes."
  (let (inbox)
    (org-element-map (org-element-parse-buffer) 'headline
      (lambda (headline)
        (when (and (not inbox)
                   (= (or (org-element-property :level headline) 0) 1)
                   (string= (org-element-property :raw-value headline)
                            name)
                   (not
                    (org-roam-organize--element-commented-p headline)))
          (setq inbox headline))))
    inbox))

(defun org-roam-organize--first-child-headline-begin (headline)
  "Return the beginning position of HEADLINE's first child headline.

Implementation notes: the child search is constrained to HEADLINE's parsed
element tree.  The returned position lets insertion happen inside the Inbox
section before nested child headings."
  (let ((contents-begin (org-element-property :contents-begin headline))
        (end (org-element-property :end headline))
        child-begin)
    (when contents-begin
      (org-element-map headline 'headline
        (lambda (child)
          (when (and (not child-begin)
                     (> (org-element-property :begin child)
                        (org-element-property :begin headline)))
            (setq child-begin (org-element-property :begin child))))
        nil nil nil)
      (when (and child-begin
                 end
                 (< child-begin end))
        child-begin))))

(defun org-roam-organize--inbox-insertion-point (name)
  "Return the insertion point for new generated entries.

Create the level-1 Inbox headline named NAME when it is missing.

Implementation notes: existing inboxes receive new entries before their first
child headline, preserving manual subsection structure.  Missing inboxes are
appended as a level-1 headline at the end of the file."
  (let ((inbox (org-roam-organize--inbox-headline name)))
    (if inbox
        (let ((child-begin
               (org-roam-organize--first-child-headline-begin inbox))
              (contents-begin (org-element-property :contents-begin inbox))
              (end (org-element-property :end inbox)))
          (goto-char (or child-begin contents-begin end))
          (unless (bolp)
            (insert "\n"))
          (point))
      (goto-char (point-max))
      (unless (or (bobp) (bolp))
        (insert "\n"))
      (insert "* " name "\n")
      (point))))

(defun org-roam-organize--moc-managed-property-put (property value)
  "Set top-level MOC PROPERTY to VALUE in the current buffer.

Implementation notes: the function works only at the file top.  It creates a
property drawer if necessary, updates an existing property line inside the
drawer when found, or inserts a new property before `:END:'."
  (let ((property (upcase property))
        (value (format "%s" value)))
    (save-excursion
      (goto-char (point-min))
      (unless (looking-at-p ":PROPERTIES:")
        (insert ":PROPERTIES:\n:END:\n"))
      (goto-char (point-min))
      (let ((drawer-end
             (save-excursion
               (when (re-search-forward "^:END:[ \t]*$" nil t)
                 (line-beginning-position)))))
        (if (not drawer-end)
            (progn
              (goto-char (point-min))
              (insert ":PROPERTIES:\n:END:\n")
              (org-roam-organize--moc-managed-property-put property value))
          (if (re-search-forward
               (format "^:%s:[ \t]*.*$" (regexp-quote property))
               drawer-end t)
              (replace-match (format ":%s: %s" property value) t t)
            (goto-char drawer-end)
            (insert (format ":%s: %s\n" property value))))))))

(defun org-roam-organize--moc-update-managed-information (record nodes)
  "Update managed information in RECORD's MOC file for NODES.

Implementation notes: derived metadata is written after a successful sync.
The MOC file is opened non-interactively, the managed tag and node count
properties are updated through the drawer helper, then the buffer is saved."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (tag (org-roam-organize--record-tag record)))
    (when (and path tag (file-exists-p path))
      (with-current-buffer (find-file-noselect path)
        (org-roam-organize--moc-managed-property-put
         org-roam-organize-moc-managed-tag-property
         tag)
        (org-roam-organize--moc-managed-property-put
         org-roam-organize-moc-managed-node-count-property
         (length nodes))
        (save-buffer)))))

(defun org-roam-organize--sync-id-link-keyword-entries
    (keyword-name path nodes inbox-name
                  &optional suffix-parser suffix-builder record missing-reason)
  "Sync id-link KEYWORD-NAME entries at PATH from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: NODES are indexed by id in a hash table.  Existing
entries are parsed with Org Element, using SUFFIX-PARSER for
keyword-specific metadata.  Duplicates are detected with a second hash table,
and replacements/removals run from the end of the buffer toward the beginning
so saved positions remain valid.  Missing nodes are appended after existing
edits have completed.  SUFFIX-BUILDER receives an existing parsed entry and
returns text to preserve after the regenerated id link.  MISSING-REASON lets
callers keep domain-specific failure messages while sharing the same sync
implementation."
  (let ((node-table (make-hash-table :test 'equal))
        (seen-table (make-hash-table :test 'equal))
        duplicate-ids removed-ids malformed-lines)
    (dolist (node nodes)
      (puthash (plist-get node :id) node node-table))
    (if (not (and path (file-exists-p path)))
        (list :status 'failed
              :record record
              :reason (or missing-reason "Target file does not exist"))
      (with-current-buffer (find-file-noselect path)
        (let* ((parse-result
                (org-roam-organize--parse-id-link-keyword-entries
                 keyword-name
                 suffix-parser))
               (entries (plist-get parse-result :entries)))
          (setq malformed-lines (plist-get parse-result :malformed))
          (dolist (entry entries)
            (let ((id (plist-get entry :id)))
              (if (gethash id seen-table)
                  (cl-pushnew id duplicate-ids :test #'equal)
                (puthash id t seen-table))))
          (dolist (entry (reverse entries))
            (let* ((id (plist-get entry :id))
                   (node (gethash id node-table)))
              (goto-char (plist-get entry :begin))
              (if node
                  (progn
                    (delete-region (plist-get entry :begin)
                                   (plist-get entry :end))
                    (insert
                     (org-roam-organize--id-link-keyword-entry-line
                      keyword-name
                      id
                      (plist-get node :title)
                      (when suffix-builder
                        (funcall suffix-builder entry)))))
                (push id removed-ids)
                (delete-region (plist-get entry :begin)
                               (plist-get entry :end)))))
          (let (missing-nodes)
            (dolist (node nodes)
              (unless (gethash (plist-get node :id) seen-table)
                (push node missing-nodes)))
            (when missing-nodes
              (org-roam-organize--inbox-insertion-point inbox-name)
              (dolist (node (nreverse missing-nodes))
                (insert
                 (org-roam-organize--id-link-keyword-entry-line
                  keyword-name
                  (plist-get node :id)
                  (plist-get node :title)))))))
        (save-buffer)
        (list :status 'ok
              :record record
              :duplicates (nreverse duplicate-ids)
              :removed (nreverse removed-ids)
              :malformed malformed-lines)))))

(defun org-roam-organize--moc-sync-node-entries (record nodes)
  "Sync MOC node entries for RECORD from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: this MOC-specific wrapper delegates the shared
id-link-keyword synchronization work to
`org-roam-organize--sync-id-link-keyword-entries'.  It supplies the
`#+ROAM_NODE' keyword, the record's MOC file path, the record's inbox
headline name, and MOC suffix handlers that preserve the existing
`:delete t' marker."
  (org-roam-organize--sync-id-link-keyword-entries
   org-roam-organize--moc-node-keyword
   (org-roam-organize--record-absolute-moc-path record)
   nodes
   (org-roam-organize--record-inbox record)
   (lambda (suffix)
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))
   (lambda (entry)
     (when (plist-get entry :delete)
       " :delete t"))
   record
   "MOC file does not exist"))

(defun org-roam-organize--cite-citing-node-data (ref-node-ids)
  "Return citing-node data for citation reference node ids REF-NODE-IDS.

The return value is a plist with `:alist'.  `:alist' maps a reference node id
to a list of citing node plists containing `:id' and `:title'.

Implementation notes: UUID citation mode treats `citations.cite_key' as the
managed literature node UUID, so the query joins Org-roam `refs' and
`citations' on `refs.node_id = citations.cite_key' while requiring
`refs.type = \"cite\"'.  Only level-0 citing nodes are selected.  Duplicate
citation occurrences from the same citing node are collapsed by a
per-reference hash table."
  (let* ((rows
          (when ref-node-ids
            (org-roam-db-query
             (vector :select (vector 'r:node_id 'r:ref 'c:node_id 'n:title)
                     :from '(as refs r)
                     :join '(as citations c)
                     :on '(= r:node_id c:cite_key)
                     :join '(as nodes n)
                     :on '(and (= n:level 0) (= n:id c:node_id))
                     :where '(and (= r:type "cite")
                                  (in r:node_id $v1)))
             (vconcat ref-node-ids))))
         (ref-to-citing-table (make-hash-table :test 'equal))
         (ref-to-citing-list (make-hash-table :test 'equal))
         alist)
    (dolist (row rows)
      (let ((ref-id (nth 0 row))
            (citing-id (nth 2 row))
            (citing-title (nth 3 row)))
        (let ((citing-table
               (or (gethash ref-id ref-to-citing-table)
                   (let ((table (make-hash-table :test 'equal)))
                     (puthash ref-id table ref-to-citing-table)
                     table))))
          (unless (gethash citing-id citing-table)
            (puthash citing-id
                     (list :id citing-id
                           :title citing-title)
                     citing-table)
            (puthash ref-id
                     (cons (list :id citing-id
                                 :title citing-title)
                           (gethash ref-id ref-to-citing-list))
                     ref-to-citing-list)))))
    (maphash
     (lambda (ref-id citing-list)
       (push (cons ref-id (nreverse citing-list)) alist))
     ref-to-citing-list)
    (list :alist (nreverse alist))))

(defun org-roam-organize--cite-reference-map-data (ref-nodes)
  "Return cite reference mapping data for REF-NODES.

The return value is a plist containing `:uuid-to-citekey',
`:citekey-to-uuids', `:missing', `:multiple', and `:duplicate-citekeys'.
`:uuid-to-citekey' maps managed literature node UUIDs to their external
bibliography citekeys.  `:citekey-to-uuids' maps each external citekey to the
managed UUID list that declares it.  `:missing' contains reference nodes with
no `refs.type = \"cite\"' row.  `:multiple' contains reference nodes extended
with a `:refs' list when more than one cite ref row is attached to that node.
`:duplicate-citekeys' reports external citekeys used by more than one managed
node.  Callers decide whether that diagnostic is blocking for their operation.

Implementation notes: the function queries Org-roam's `refs' table once for
all managed reference node ids and then builds hash tables in memory.  Missing
and multiple cite refs are blocking because they make UUID citation mapping
ambiguous.  Duplicate external citekeys are reported separately so global
consistency checks can require a bijection without preventing UUID-based
citation operations from applying a narrower policy."
  (let* ((ref-node-ids (mapcar (lambda (node)
                                 (plist-get node :id))
                               ref-nodes))
         (rows
          (when ref-node-ids
            (org-roam-db-query
             (vector :select (vector 'r:node_id 'r:ref)
                     :from '(as refs r)
                     :where '(and (= r:type "cite")
                                  (in r:node_id $v1)))
             (vconcat ref-node-ids))))
         (node-ref-table (make-hash-table :test 'equal))
         (uuid-to-citekey (make-hash-table :test 'equal))
         (citekey-to-uuids (make-hash-table :test 'equal))
         missing
         multiple
         duplicate-citekeys)
    (dolist (row rows)
      (let ((node-id (nth 0 row))
            (ref (nth 1 row)))
        (puthash node-id
                 (cons ref (gethash node-id node-ref-table))
                 node-ref-table)))
    (dolist (node ref-nodes)
      (let* ((node-id (plist-get node :id))
             (refs (nreverse (gethash node-id node-ref-table))))
        (cond
         ((null refs)
          (push node missing))
         ((> (length refs) 1)
          (push (append node (list :refs refs)) multiple))
         (t
          (let ((citekey (car refs)))
            (puthash node-id citekey uuid-to-citekey)
            (puthash citekey
                     (cons node-id (gethash citekey citekey-to-uuids))
                     citekey-to-uuids))))))
    (maphash
     (lambda (citekey uuids)
       (when (> (length uuids) 1)
         (push (list :citekey citekey
                     :uuids (reverse uuids))
               duplicate-citekeys)))
     citekey-to-uuids)
    (list :missing (nreverse missing)
          :multiple (nreverse multiple)
          :duplicate-citekeys (nreverse duplicate-citekeys)
          :uuid-to-citekey uuid-to-citekey
          :citekey-to-uuids citekey-to-uuids)))

(defun org-roam-organize--cite-reference-refs-valid-p (result)
  "Return non-nil when cite reference refs in RESULT are valid.

Implementation notes: RESULT is the plist returned by
`org-roam-organize--cite-reference-map-data'.  Valid means that no
managed reference node is missing a `refs.type = \"cite\"' row and none has
more than one such row."
  (and (null (plist-get result :missing))
       (null (plist-get result :multiple))))

(defun org-roam-organize--cite-reference-map-bijective-p (map-data)
  "Return non-nil when MAP-DATA describes a bijective citation mapping.

MAP-DATA must be a plist returned by
`org-roam-organize--cite-reference-map-data' or
`org-roam-organize--cite-global-reference-map-data'.  Return non-nil when
every managed reference node has exactly one citekey and every declared
citekey belongs to exactly one managed node.  This function does not access
the database or modify MAP-DATA.

Implementation notes: UUID-to-citekey totality and uniqueness are delegated
to `org-roam-organize--cite-reference-refs-valid-p'.  Citekey-to-UUID
uniqueness is represented by an empty `:duplicate-citekeys' diagnostic list.

Rationale: Global consistency checks require a true bijection, while export
and citation synchronization can continue using the weaker UUID-to-citekey
validation appropriate to their direction of lookup."
  (and (org-roam-organize--cite-reference-refs-valid-p map-data)
       (null (plist-get map-data :duplicate-citekeys))))

(defun org-roam-organize--cite-global-reference-map-data ()
  "Return global cite reference mapping data, or nil when cite is unconfigured.

Implementation notes: the function requires at most one `:cite t' registry
record, loads all level-0 nodes for that record's tag, and delegates ref table
loading to `org-roam-organize--cite-reference-map-data'.  The returned plist
therefore contains both the managed literature node list and the mapping
diagnostics derived from Org-roam's DB tables.  Citation sync, global cite
checks, and export conversion can share this loader while keeping their own
policy decisions."
  (let ((records (org-roam-organize--registry-cite-records)))
    (cond
     ((not records)
      nil)
     ((> (length records) 1)
      (user-error "Multiple :cite t registry records are configured"))
     (t
      (let* ((record (car records))
             (tag (org-roam-organize--record-tag record))
             (ref-nodes
              (and (stringp tag)
                   (org-roam-organize--nodes-with-tag tag)))
             (map-data
              (org-roam-organize--cite-reference-map-data
               ref-nodes)))
        (plist-put map-data :nodes ref-nodes))))))

(defun org-roam-organize--cite-reference-keys-in-parse-tree (parse-tree)
  "Return unique citation reference keys from PARSE-TREE.

Implementation notes: the function walks Org Element `citation-reference'
nodes and collects their `:key' properties in parse order.  A hash table is
used to avoid duplicate DB work when the same key appears more than once in
the exported document."
  (let ((seen (make-hash-table :test 'equal))
        keys)
    (org-element-map parse-tree 'citation-reference
      (lambda (reference)
        (let ((key (org-element-property :key reference)))
          (when (and (stringp key)
                     (not (gethash key seen)))
            (puthash key t seen)
            (push key keys)))))
    (nreverse keys)))

(defun org-roam-organize--cite-empty-reference-map-data ()
  "Return an empty cite reference mapping data plist.

Implementation notes: export conversion uses this value when the current
parse tree does not reference any managed literature node.  Keeping the same
plist shape as `org-roam-organize--cite-reference-map-data' lets callers use
the same hash-table lookup path without special branching."
  (list :missing nil
        :multiple nil
        :duplicate-citekeys nil
        :uuid-to-citekey (make-hash-table :test 'equal)
        :citekey-to-uuids (make-hash-table :test 'equal)
        :nodes nil))

(defun org-roam-organize--cite-export-reference-map-data-or-error (keys)
  "Return valid cite reference mapping data for managed citation KEYS.

Signal a user error when any managed literature node referenced by KEYS has
missing or multiple cite refs.  Return nil when no `:cite t' record is
configured.

Implementation notes: this export-specific policy intentionally validates
only the intersection of the current export's citation keys and the managed
literature node UUID set.  It still reuses
`org-roam-organize--cite-reference-map-data' and
`org-roam-organize--cite-reference-refs-valid-p' for table loading and
blocking validation.  Citation keys that do not match managed literature node
UUIDs are ignored so ordinary external citekeys remain exportable."
  (if (not keys)
      (org-roam-organize--cite-empty-reference-map-data)
    (let ((records (org-roam-organize--registry-cite-records)))
      (cond
       ((not records)
        nil)
       ((> (length records) 1)
        (user-error "Multiple :cite t registry records are configured"))
       (t
        (let* ((record (car records))
               (tag (org-roam-organize--record-tag record))
               (key-table (make-hash-table :test 'equal))
               selected-nodes)
          (dolist (key keys)
            (puthash key t key-table))
          (dolist (node (and (stringp tag)
                             (org-roam-organize--nodes-with-tag tag)))
            (when (gethash (plist-get node :id) key-table)
              (push node selected-nodes)))
          (let ((map-data
                 (if selected-nodes
                     (org-roam-organize--cite-reference-map-data
                      (nreverse selected-nodes))
                   (org-roam-organize--cite-empty-reference-map-data))))
            (unless (org-roam-organize--cite-reference-refs-valid-p map-data)
              (user-error
               "Cite reference validation failed for exported citations: %s missing cite refs, %s multiple cite refs"
               (length (plist-get map-data :missing))
               (length (plist-get map-data :multiple))))
            map-data)))))))

(defun org-roam-organize--cite-report-reference-map-data (map-data)
  "Return cite reference diagnostics for MAP-DATA.

Return a plist with `:valid-p' and `:lines'.  `:valid-p' is non-nil when
blocking validation passed.  `:lines' contains human-readable diagnostics.

Implementation notes: MAP-DATA is produced by
`org-roam-organize--cite-reference-map-data' or
`org-roam-organize--cite-global-reference-map-data'.  The reporting policy is
shared by `org-roam-organize-cite-check' and `org-roam-organize-cite-sync' for
missing and multiple cite refs.  Duplicate external citekeys are emitted as
separate diagnostic lines so each caller can decide whether they are blocking.
The function builds report lines instead of calling `message' so callers can
display a single final report."
  (let ((missing (plist-get map-data :missing))
        (multiple (plist-get map-data :multiple))
        (duplicate-citekeys (plist-get map-data :duplicate-citekeys))
        lines)
    (dolist (entry duplicate-citekeys)
      (push
       (format
        "[WARNING] External citekey belongs to multiple literature nodes: %s (%s)"
        (plist-get entry :citekey)
        (mapconcat #'identity
                   (plist-get entry :uuids)
                   ", "))
       lines))
    (if (not (org-roam-organize--cite-reference-refs-valid-p map-data))
        (progn
          (push
           (format
            "[WARNING] Cite reference validation failed: %s missing cite refs, %s multiple cite refs."
            (length missing)
            (length multiple))
           lines)
          (dolist (node missing)
            (push
             (format
              "[WARNING] Cite reference node has no cite ref: %s (%s)"
              (plist-get node :title)
              (plist-get node :id))
             lines))
          (dolist (node multiple)
            (push
             (format
              "[WARNING] Cite reference node has multiple cite refs: %s (%s): %s"
              (plist-get node :title)
              (plist-get node :id)
              (mapconcat #'identity
                         (plist-get node :refs)
                         ", "))
             lines))
          (list :valid-p nil :lines (nreverse lines)))
      (list :valid-p t :lines (nreverse lines)))))

(defun org-roam-organize--cite-export-filter (parse-tree _backend _info)
  "Replace managed UUID citation keys in PARSE-TREE before export.

Return the modified PARSE-TREE.  Only citation references whose `:key'
matches a managed literature node UUID are rewritten; other citation keys are
left unchanged.

Implementation notes: Org export parse-tree filters receive the complete Org
Element tree before backend rendering.  This function first collects citation
keys from the current parse tree, validates and loads cite refs only for
managed literature UUIDs that appear in that key set, then walks
`citation-reference' elements and mutates only the `:key' property with
`org-element-put-property'.  The source buffer is not edited.  The function
keeps an explicit `org-roam-organize-mode' guard because export hook variables
are global."
  (when org-roam-organize-mode
    (let* ((keys
            (org-roam-organize--cite-reference-keys-in-parse-tree
             parse-tree))
           (map-data
            (org-roam-organize--cite-export-reference-map-data-or-error
             keys))
           (uuid-to-citekey
            (plist-get map-data :uuid-to-citekey)))
      (when uuid-to-citekey
        (org-element-map parse-tree 'citation-reference
          (lambda (reference)
            (let* ((key (org-element-property :key reference))
                   (citekey (and (stringp key)
                                 (gethash key uuid-to-citekey))))
              (when citekey
                (org-element-put-property reference :key citekey))))))))
  parse-tree)

(defun org-roam-organize--cite-sync-citing-node-entries (record path nodes)
  "Sync citing-node entries for citation RECORD at PATH from NODES.

Implementation notes: this cite-specific wrapper delegates the shared
id-link-keyword synchronization work to
`org-roam-organize--sync-id-link-keyword-entries'.  It supplies the
`#+ROAM_CITING_NODE' keyword and the record's inbox headline name.  Citation
entries do not currently use suffix metadata."
  (org-roam-organize--sync-id-link-keyword-entries
   org-roam-organize--cite-citing-node-keyword
   path
   nodes
   (org-roam-organize--record-inbox record)
   nil
   nil
   record
   "Reference file does not exist"))

;; 对给定 tag 列表, 查出数据库中 nodes 表内 level=0 的 node 数量
(defun org-roam-organize--count-nodes-with-given-tag-list (tag_list &optional hash_to_alist)
  "Return tag counts for level-0 nodes in TAG_LIST.

When HASH_TO_ALIST is non-nil, return an alist.  Otherwise return a hash
table.  Tags not present in the Org-roam database are assigned zero.

Implementation notes: the result hash is prefilled with zero for every input
tag, then updated from a grouped Org-roam DB query.  The query joins `tags'
to level-0 `nodes' so headline tags do not affect file-node counts.  When an
alist is requested, it is derived directly from TAG_LIST so the return order
matches the input order."
  (when org-roam-organize-mode
    (let* ((tag_count (make-hash-table :test 'equal))
           (result
            (org-roam-db-query
             (vector :select (vector 't:tag '(funcall count t:tag))
                     :from '(as tags t)
                     :join '(as nodes n)
                     :on '(and (= n:level 0) (= n:id t:node_id))
                     :where '(in t:tag $v1)
                     :group-by 't:tag)
             (vconcat tag_list))))
      (dolist (tag tag_list)
        (puthash tag 0 tag_count))
      (dolist (item result)
        (let ((tag (nth 0 item))
              (count (nth 1 item)))
          (puthash tag count tag_count)))
      (if hash_to_alist
          (mapcar (lambda (tag)
                    (cons tag (gethash tag tag_count)))
                  tag_list)
        tag_count))))

(defun org-roam-organize--setup-cite-backend (backend)
  "Install the optional citation adapter selected by BACKEND.

BACKEND installs the Citar adapter when it is `citar'.  A nil value selects no
adapter.  Any other value is ignored with a warning.  Signal `user-error' when
`org-roam-organize-mode' is disabled or when the selected Citar adapter cannot
be loaded or validated.  Return the installed backend symbol, or nil when no
adapter is installed.  Failure does not itself disable Org-roam Organize mode;
the mode lifecycle decides whether an adapter error is fatal.

Implementation notes: The recognized backend maps to a separate adapter
feature and setup function.  The active backend is recorded only after setup
succeeds so mode teardown does not claim ownership of a partial installation.
Unsupported values never load optional packages or claim active ownership.

Rationale: Adapter installation belongs to the mode lifecycle because advice
and third-party customization changes must have a matching teardown boundary.
Keeping failure policy in the caller lets optional integration degrade without
blocking core behavior."
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  (pcase backend
    ('nil
     (setq org-roam-organize--active-cite-backend nil))
    ('citar
     (unless (require 'org-roam-organize-citar nil t)
       (user-error
        "Citar backend is configured, but its adapter or Citar is unavailable"))
     (org-roam-organize-citar-setup)
     (setq org-roam-organize--active-cite-backend 'citar))
    (_
     (setq org-roam-organize--active-cite-backend nil)
     (message
      "[WARNING] Citation backend is not supported and was ignored: %S"
      backend)
     nil)))

(defun org-roam-organize--teardown-cite-backend ()
  "Remove the citation adapter installed by Org-roam Organize mode.

Return nil after clearing `org-roam-organize--active-cite-backend'.  This
function is valid while the mode is being disabled and therefore does not
require `org-roam-organize-mode' to be non-nil.

Implementation notes: Teardown dispatches on the recorded active backend
rather than the current customization value, which may have changed since mode
setup.

Rationale: Advice and third-party variable changes must be removed by the
component that installed them."
  (pcase org-roam-organize--active-cite-backend
    ('citar
     (when (featurep 'org-roam-organize-citar)
       (org-roam-organize-citar-teardown))))
  (setq org-roam-organize--active-cite-backend nil))

;; ==============================
;; 可调用结构函数
;; ==============================

;; 变量检查
;;;###autoload
(defun org-roam-organize-check-variables ()
  "Check Org-roam Organize configuration variables.

Implementation notes: this interactive wrapper delegates to
`org-roam-organize--check-variables' with the package's declared variable
type table.  Passing checks produce a short echo-area message.  Failing checks
display the generated report in the report buffer and leave a short notice in
the echo area."
  (interactive)
  (let ((check_result
         (org-roam-organize--check-variables
          org-roam-organize-directory
          org-roam-organize--variable-type-alist)))
    (cond
     ((and (consp check_result)
           (car check_result))
      (message "[INFO] Org-roam Organize variable checks passed."))
     ((consp check_result)
      (org-roam-organize--display-report
       "Org-roam Organize Variable Check"
       (cdr check_result))
      (message "%s"
               (org-roam-organize--report-notice
                'warning
                "Org-roam Organize variable checks failed.")))
     (t
      (org-roam-organize--display-report
       "Org-roam Organize Variable Check"
       check_result)
      (message "%s"
               (org-roam-organize--report-notice
                'warning
                "Org-roam Organize variable checks failed."))))))

;;;###autoload
(defun org-roam-organize-check-setup ()
  "Check whether Org-roam Organize can be enabled.

This command reports both variable validation and runtime capability
validation.

Implementation notes: the command is a user-facing wrapper around
`org-roam-organize--check-setup'.  It prints a short success message when all
subchecks pass.  On failure it displays the detailed report in the report buffer
and leaves only a short notice in the echo area."
  (interactive)
  (let ((check_result (org-roam-organize--check-setup)))
    (cond
     ((and (consp check_result)
           (car check_result))
      (message "[INFO] Org-roam Organize setup checks passed."))
     ((consp check_result)
      (org-roam-organize--display-report
       "Org-roam Organize Setup Check"
       (cdr check_result))
      (message "%s"
               (org-roam-organize--report-notice
                'warning
                "Org-roam Organize setup checks failed.")))
     (t
      (org-roam-organize--display-report
       "Org-roam Organize Setup Check"
       check_result)
      (message "%s"
               (org-roam-organize--report-notice
                'warning
                "Org-roam Organize setup checks failed."))))))

;; 创建目录
;;;###autoload
(defun org-roam-organize-create-directories ()
  "Create the root and basic registry directories when missing.

Implementation notes: the directory list is built from
`org-roam-organize-directory' plus absolute directories derived from
`:basic t' registry records.  Existing directories and nil entries are
skipped; missing directories are created recursively."
  (interactive)
  (let ((dir_list
         (cons
          org-roam-organize-directory
          (mapcar #'org-roam-organize--record-absolute-directory
                  (org-roam-organize--registry-basic-records)))))
    (dolist (dir dir_list)
      (unless (or (not dir) (file-exists-p dir))
        (make-directory dir t)))))

;; ==============================
;; 可调用功能函数
;; ==============================

;; 打开顶层 MOC
;;;###autoload
(defun org-roam-organize-moc-open-index ()
  "Open the top-level Map of Contents file using its file path.

Implementation notes: the top-level MOC is the single `:moc t' registry
record.  Its path is resolved through the registry helpers; the command only
opens the file when the resolved path exists and otherwise reports the
configuration or filesystem problem."
  (interactive)
  (if org-roam-organize-mode
      (let ((file_path
             (org-roam-organize--record-absolute-moc-path
              (org-roam-organize--registry-moc-record))))
        (cond
         ((not file_path)
          (message "Top MOC file path is not defined. Please check your configuration."))
         ((not (file-exists-p file_path))
          (message "Top MOC file not found at path: %s" file_path))
         (t
          (find-file file_path)
          ;; Optional enhancements (kept commented as in original)
          ;; (display-line-numbers-mode 1)
          ;; (font-lock-mode 1)
          ;; (font-lock-fontify-buffer)
          (message "[INFO] Opened Top MOC: %s" (file-name-nondirectory file_path)))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 创建缺失的 MOC 对应的 org-roam node
;;;###autoload
(defun org-roam-organize-moc-create ()
  "Create missing MOC files declared in `org-roam-organize-registry'.

Implementation notes: every registry record gets a derived MOC path and
capture template.  Existing files are skipped, malformed records are counted
as failed, and missing files are created through the same provider request
protocol used by ordinary managed node creation.  The provider is the
internal `org-roam-organize--moc-node-provider', and the capture still uses a
single immediate-finish template generated from the registry."
  (interactive)
  (if org-roam-organize-mode
      (let ((debug-on-error t)
            (created-count 0)
            (skipped-count 0)
            (failed-count 0))
        (dolist (record org-roam-organize-registry)
          (let* ((path (org-roam-organize--record-absolute-moc-path record))
                 (template (org-roam-organize--record-moc-capture-template record))
                 (tag (org-roam-organize--record-tag record))
                 (request (org-roam-organize--moc-node-provider record)))
            (cond
             ((not (and path
                        template
                        tag
                        (org-roam-organize--node-request-valid-p request)))
              (setq failed-count (1+ failed-count))
              (message "[WARNING] Cannot create MOC for registry record: %s" record))
             ((file-exists-p path)
              (setq skipped-count (1+ skipped-count))
              (message "[INFO] MOC already exists, skipped: %s" path))
             (t
              (org-roam-organize--capture-node
               (plist-get request :title)
               template
               (plist-get request :info)
               '(:immediate-finish t))
              (setq created-count (1+ created-count))))))
        (message "[INFO] Create missing MOCs: %s created, %s skipped, %s failed."
                 created-count skipped-count failed-count))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 创建受管理的普通 org-roam node
;;;###autoload
(defun org-roam-organize-node-create ()
  "Create a managed Org-roam node using `org-roam-organize-registry'.

The selected registry record must define a relative `:directory'.  The
created node uses the standard path layout
<directory>/${id}/${path} under `org-roam-organize-directory'.
If the record declares `:provider', that provider supplies the node title and
optional capture info; otherwise the built-in default provider reads a title.
Org-roam Organize creates the expanded target parent directory during
Org-roam's capture preface phase and cleans the managed bundle root after
capture.

Implementation notes: the command reads a registry record, obtains its
provider with `org-roam-organize--record-provider', calls the provider to get
a node creation request, builds a temporary one-entry capture template, and
delegates the capture call to `org-roam-organize--capture-node'.  That helper
installs a preface hook to compute the expanded bundle root and create the
target parent directory after Org-roam has assigned capture placeholders, plus
an after-finalize hook to clean only that bundle root."
  (interactive)
  (if org-roam-organize-mode
      (let ((record (org-roam-organize--read-node-record)))
        (if (not record)
            (message "[WARNING] No registry record can create managed nodes.")
          (let* ((provider (org-roam-organize--record-provider record))
                 (request (when (functionp provider)
                            (funcall provider record)))
                 (template (org-roam-organize--record-node-capture-template record))
                 (key (car-safe template)))
            (cond
             ((not (functionp provider))
              (message "[WARNING] Invalid node provider for registry record: %s" record))
             ((null request)
              (message "[INFO] Node creation canceled."))
             ((not (org-roam-organize--node-request-valid-p request))
              (message "[WARNING] Invalid node creation request: %s" request))
             ((not (and template key))
              (message "[WARNING] Cannot create node for registry record: %s" record))
             (t
              (org-roam-organize--capture-node
               (plist-get request :title)
               template
               (plist-get request :info)
               nil
               record))))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 同步 MOC
;;;###autoload
(defun org-roam-organize-moc-sync ()
  "Sync managed MOC files from Org-roam node tags.

Implementation notes: the command refreshes access to the Org-roam database,
then walks registry records.  For each tag, matching level-0 nodes are loaded
from the DB, node entries are synchronized in the corresponding MOC file, and
derived managed properties are updated only after a successful entry sync.
Per-record failure diagnostics are collected and displayed in the report buffer;
clean runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((synced-count 0)
            (failed-count 0)
            (duplicate-count 0)
            (removed-count 0)
            (malformed-count 0)
            report-lines)
        (org-roam-db)
        (dolist (record org-roam-organize-registry)
          (let* ((tag (org-roam-organize--record-tag record))
                 (nodes (and (stringp tag)
                             (org-roam-organize--nodes-with-tag tag)))
                 (result (when (stringp tag)
                           (org-roam-organize--moc-sync-node-entries
                            record
                            (or nodes nil)))))
            (cond
             ((not (and (stringp tag) result))
              (setq failed-count (1+ failed-count))
              (push
               (format "[WARNING] Cannot sync MOC for registry record: %s"
                       record)
               report-lines))
             ((eq (plist-get result :status) 'failed)
              (setq failed-count (1+ failed-count))
              (push
               (format "[WARNING] Cannot sync MOC for registry record: %s (%s)"
                       record
                       (plist-get result :reason))
               report-lines))
             (t
              (org-roam-organize--moc-update-managed-information record nodes)
              (setq synced-count (1+ synced-count))
              (setq duplicate-count
                    (+ duplicate-count
                       (length (plist-get result :duplicates))))
              (setq removed-count
                    (+ removed-count
                       (length (plist-get result :removed))))
              (setq malformed-count
                    (+ malformed-count
                       (length (plist-get result :malformed))))))))
        (let ((summary
               (format
                "[INFO] Sync MOCs: %s synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries."
                synced-count failed-count duplicate-count removed-count malformed-count)))
          (if report-lines
              (progn
                (org-roam-organize--display-report
                 "Org-roam Organize MOC Sync"
                 (append (nreverse report-lines) (list summary)))
                (message "%s"
                         (org-roam-organize--report-notice
                          'warning
                          summary)))
            (message "%s" summary))))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 文献引用节点条目同步
;;;###autoload
(defun org-roam-organize-cite-check ()
  "Check global managed citation reference consistency.

Implementation notes: the command refreshes the Org-roam database, loads the
single `:cite t' registry record through
`org-roam-organize--cite-global-reference-map-data', and collects the same
mapping diagnostics used by `org-roam-organize-cite-sync'.  It does not modify
Org files.  Missing or multiple cite refs and duplicate external citekeys are
all blocking validation failures because this command requires a bijection.
Detailed diagnostics are displayed in the report buffer when present; clean
runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((records (org-roam-organize--registry-cite-records)))
        (cond
         ((not records)
          (message "[WARNING] No :cite t registry record is configured."))
         ((> (length records) 1)
          (message "[WARNING] Multiple :cite t registry records are configured."))
         (t
          (org-roam-db)
          (let* ((map-data
                  (org-roam-organize--cite-global-reference-map-data))
                 (node-count (length (plist-get map-data :nodes)))
                 (duplicate-citekey-count
                  (length (plist-get map-data :duplicate-citekeys)))
                 (report
                  (org-roam-organize--cite-report-reference-map-data
                   map-data))
                 (bijective-p
                  (org-roam-organize--cite-reference-map-bijective-p
                   map-data))
                 (summary
                  (format
                   "[INFO] Check cite references: %s checked, %s missing cite refs, %s multiple cite refs, %s duplicate cite keys, status %s."
                   node-count
                   (length (plist-get map-data :missing))
                   (length (plist-get map-data :multiple))
                   duplicate-citekey-count
                   (if bijective-p "passed" "failed"))))
            (if (plist-get report :lines)
                (progn
                  (org-roam-organize--display-report
                   "Org-roam Organize Cite Check"
                   (append (plist-get report :lines) (list summary)))
                  (message "%s"
                           (org-roam-organize--report-notice
                            (if bijective-p 'warning 'error)
                            summary)))
              (message "%s" summary))))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 文献引用节点条目同步
;;;###autoload
(defun org-roam-organize-cite-sync ()
  "Sync citing-node entries for managed citation reference nodes.

Implementation notes: the command requires exactly one registry record marked
with `:cite t'.  It refreshes the Org-roam database, reads every level-0 node
with that record's tag, validates that each reference node has exactly one
`refs.type = \"cite\"' row, reports duplicate external citekeys as
non-blocking data quality warnings through the shared cite reference reporter,
computes citing-node relationships from `refs' and `citations', and
synchronizes `#+ROAM_CITING_NODE' keyword entries in each reference node's
configured Inbox headline.  The sync is intentionally global so stale entries
can be removed from reference nodes that no longer have incoming citations.
Detailed citation and per-node sync diagnostics are displayed in the report
buffer when present; clean runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((records (org-roam-organize--registry-cite-records)))
        (cond
         ((not records)
          (message "[WARNING] No :cite t registry record is configured."))
         ((> (length records) 1)
          (message "[WARNING] Multiple :cite t registry records are configured."))
         (t
          (let ((record (car records))
                (synced-count 0)
                (failed-count 0)
                (duplicate-count 0)
                (removed-count 0)
                (malformed-count 0)
                (duplicate-citekey-count 0)
                cite-report-lines
                sync-report-lines)
            (org-roam-db)
            (let* ((tag (org-roam-organize--record-tag record))
                   (ref-nodes
                    (and (stringp tag)
                         (org-roam-organize--nodes-with-tag-and-file tag)))
                   (ref-node-ids (mapcar (lambda (node)
                                           (plist-get node :id))
                                         ref-nodes))
                   (map-data
                    (org-roam-organize--cite-reference-map-data
                     ref-nodes))
                   (report
                    (org-roam-organize--cite-report-reference-map-data
                     map-data))
                   (cite-data
                    (when (plist-get report :valid-p)
                      (org-roam-organize--cite-citing-node-data ref-node-ids)))
                   (citing-alist (plist-get cite-data :alist)))
              (setq cite-report-lines (plist-get report :lines))
              (setq duplicate-citekey-count
                    (length (plist-get map-data :duplicate-citekeys)))
              (if (not (plist-get report :valid-p))
                  (progn
                    (setq failed-count
                          (+ (length (plist-get map-data :missing))
                             (length (plist-get map-data :multiple)))))
                (dolist (ref-node ref-nodes)
                  (let* ((path (plist-get ref-node :file))
                         (citing-nodes
                          (or (cdr (assoc (plist-get ref-node :id)
                                          citing-alist))
                              nil))
                         (result
                          (org-roam-organize--cite-sync-citing-node-entries
                           record
                           path
                           citing-nodes)))
                    (cond
                     ((or (not result)
                          (eq (plist-get result :status) 'failed))
                      (setq failed-count (1+ failed-count))
                      (push
                       (format
                        "[WARNING] Cannot sync citing-node entries for node: %s (%s)"
                        ref-node
                        (plist-get result :reason))
                       sync-report-lines))
                     (t
                      (setq synced-count (1+ synced-count))
                      (setq duplicate-count
                            (+ duplicate-count
                               (length (plist-get result :duplicates))))
                      (setq removed-count
                            (+ removed-count
                               (length (plist-get result :removed))))
                      (setq malformed-count
                            (+ malformed-count
                               (length (plist-get result :malformed))))))))))
            (let ((summary
                   (format
                    "[INFO] Sync citing-node entries: %s synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries, %s duplicate cite keys."
                    synced-count failed-count duplicate-count removed-count malformed-count duplicate-citekey-count)))
              (if (or cite-report-lines sync-report-lines)
                  (progn
                    (org-roam-organize--display-report
                     "Org-roam Organize Cite Sync"
                     (append cite-report-lines
                             (nreverse sync-report-lines)
                             (list summary)))
                    (message "%s"
                             (org-roam-organize--report-notice
                              (if (> failed-count 0) 'error 'warning)
                              summary)))
                (message "%s" summary)))))))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; ==============================
;; Minor-Mode
;; ==============================

;; Definition.
;;;###autoload
(define-minor-mode org-roam-organize-mode
  "Toggle Org-roam Organize mode.

When enabled, the mode validates setup, registers the export-time citation
filter, installs the configured interactive citation adapter, and keeps command
behavior available globally.  Disabling the mode removes the filter and
adapter.  Core setup failure disables the mode again.  Optional citation
adapter failure leaves the mode enabled and reports a warning.  User-facing
check and sync commands display detailed diagnostics in
`org-roam-organize--report-buffer-name' when needed."
  :lighter " Organize"
  ;; :group nil
  :global t
  :init-value nil)

;; Hook.
(add-hook 'org-roam-organize-mode-hook
          (lambda ()
            (if org-roam-organize-mode
                (let* ((check_result
                        (when (and (boundp 'org-roam-organize--variable-type-alist)
                                   (boundp 'org-roam-organize--capability-alist))
                          (org-roam-organize--check-setup))))
                  (cond
                   ((not (car check_result))
                    (setq org-roam-organize-mode nil)
                    (org-roam-organize--teardown-cite-backend)
                    (remove-hook
                     'org-export-filter-parse-tree-functions
                     #'org-roam-organize--cite-export-filter)
                    (message "%s" (concat
                                   "[WARNING] Org Roam Organize setup checks failed. "
                                   "Org Roam Organize Mode setup failed.\n"
                                   (format "%s\n" (car check_result))
                                   (cdr check_result))))
                   (t
                    (condition-case err
                        (progn
                          (unless (featurep 'org) (require 'org))
                          (unless (featurep 'org-element) (require 'org-element))
                          (unless (featurep 'ox) (require 'ox))
                          (unless (featurep 'org-roam) (require 'org-roam))
                          (unless (featurep 'cl-lib) (require 'cl-lib))
                          (add-hook
                           'org-export-filter-parse-tree-functions
                           #'org-roam-organize--cite-export-filter)
                          ;; The citation backend is optional.  Its setup
                          ;; failure must not undo successful core mode setup or
                          ;; remove the export filter installed above.
                          (condition-case backend-err
                              (org-roam-organize--setup-cite-backend
                               (org-roam-organize--registry-cite-backend))
                            (error
                             (org-roam-organize--teardown-cite-backend)
                             (message
                              (concat
                               "[WARNING] Citation backend was not installed: "
                               "%s")
                              (error-message-string backend-err)))))
                      (error
                       (org-roam-organize--teardown-cite-backend)
                       (setq org-roam-organize-mode nil)
                       (remove-hook
                        'org-export-filter-parse-tree-functions
                        #'org-roam-organize--cite-export-filter)
                       (message
                        "[WARNING] Org Roam Organize Mode setup failed: %s"
                        (error-message-string err)))))))
              (org-roam-organize--teardown-cite-backend)
              (remove-hook
               'org-export-filter-parse-tree-functions
               #'org-roam-organize--cite-export-filter))))

(provide 'org-roam-organize)
;;; org-roam-organize.el ends here
