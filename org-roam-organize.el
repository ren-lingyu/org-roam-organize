;;; org-roam-organize.el --- Organize Org-roam node references -*- lexical-binding: t; -*-

;; Copyright (C) 2026 aRenCoco

;; Author: aRenCoco
;; Maintainer: aRenCoco
;; Version: 0.4.0
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
;; creating managed nodes, completing backlinks, and updating node statistics.
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
              :directory "literature"
              :inbox "Inbox"
              :template '((keywords . ((author . nil)
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
`:moc' and `:basic' are optional booleans.  A `:moc t' record must also be
`:basic t'.  A basic record must have a relative `:directory'; non-basic
records may also use `:directory' to create managed nodes in an existing
kind directory.  `:moc-path' and `:moc-title' are optional overrides resolved
from the record name when absent.  `:inbox' is an optional level-1 headline
name used for newly added MOC node entries and defaults to \"Inbox\".
`:template' is an optional structured alist for the generated file head.  Its
`properties' section is an ordered alist emitted inside an Org property
drawer.  Its `keywords' section is an ordered alist emitted as Org file
keywords.  String values are written into the generated Org-roam capture
template, so Org capture escapes such as `%<...>' and Org-roam placeholders
such as `${field}' may be expanded by `org-roam-capture-'.  Repeated keys are
emitted repeatedly.  Nil values emit empty property or keyword values.  The
`filetags' keyword accepts a list of strings and is formatted as Org file
tags; other values are written with `identity'.  `:provider' is an optional
function used when creating ordinary managed nodes.  It is called with the
full record and should return nil to cancel creation or a request plist
containing `:title' and optional `:info'.  The provider does not control
paths, targets, or capture templates."
  :type 'sexp
  :group 'org-roam-organize)

;; ==============================
;; 前置声明
;; ==============================

(defvar org-roam-organize-mode)

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
  "Default headline used for newly added MOC node entries.")

(defconst org-roam-organize--moc-node-keyword "ROAM_NODE"
  "Org keyword used for MOC node entries.")

(defconst org-roam-organize--file-head-formatter-alist
  '((filetags . org-roam-organize--file-head-filetags-format))
  "Special file head formatter functions.

Formatter functions receive the template value and return the string written
after the Org property or keyword name.  They only serialize structured
values and do not perform dynamic value lookup.  Keys not listed here use
`identity'.")

(defconst org-roam-organize--node-relative-path-template
  "${id}/${slug}.org"
  "Relative path template inside a managed node kind directory.

The standard node layout is ${id}/${slug}.org under kind directory,
where `${id}' and `${slug}' are left for Org-roam capture expansion.")

(defvar org-roam-organize--capture-created-directory nil
  "Directory created for the active managed node capture.")

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
  "Return RECORD's structured file head template.

Implementation notes: this accessor returns the raw `:template' plist value.
Formatting, ordering, and warning behavior are handled by the section-specific
file head functions."
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
under RECORD's directory inside `org-roam-organize-directory'.
This function only provides the target path template; UUID parent directory
creation is left to the Org-roam capture and Emacs save workflow.

Implementation notes: the template is generated only when RECORD has a
string directory that resolves inside the root.  `${id}' and `${slug}' are
left for Org-roam capture expansion."
  (let ((directory (org-roam-organize--record-directory record)))
    (when (and (stringp directory)
               (org-roam-organize--path-inside-root-p directory))
      (expand-file-name
       (concat (file-name-as-directory directory) org-roam-organize--node-relative-path-template)
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

(defun org-roam-organize--delete-empty-directory (directory)
  "Delete DIRECTORY when it is empty and inside `org-roam-organize-directory'.

Implementation notes: deletion is intentionally narrow: DIRECTORY must be a
string, resolve inside the organize root, and still be empty.  This is used
only to clean a capture-created UUID directory that was not populated."
  (when (and (stringp directory)
             (org-roam-organize--path-inside-root-p
              (file-relative-name directory org-roam-organize-directory))
             (org-roam-organize--empty-directory-p directory))
    (delete-directory directory)))

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

(defun org-roam-organize--capture-create-parent-directory ()
  "Create the parent directory for the active Org-roam capture target.

Return nil so `org-roam-capture-preface-hook' continues with Org-roam's
normal target setup.

Implementation notes: this hook runs after Org-roam has enough capture state
to expand `${id}' and `${slug}'.  It creates only the resolved parent
directory, records it in a dynamically bound variable, and lets the caller
clean it later if capture leaves it empty."
  (let* ((file (org-roam-organize--capture-target-file))
         (directory (and file (file-name-directory file))))
    (when (and directory
               (org-roam-organize--path-inside-root-p
                (file-relative-name directory org-roam-organize-directory))
               (not (file-directory-p directory)))
      (make-directory directory t)
      (setq org-roam-organize--capture-created-directory directory)))
  nil)

(defun org-roam-organize--capture-node (title template &optional info props manage-directory)
  "Capture an Org-roam node with TITLE and TEMPLATE.

INFO and PROPS are passed through to `org-roam-capture-'.  When
MANAGE-DIRECTORY is non-nil, create the expanded capture target's parent
directory during Org-roam's capture preface phase and remove that directory
after capture only if it remains empty.

Implementation notes: this helper centralizes the capture call boundary used
by managed ordinary nodes and MOC nodes.  Future provider support can prepare
TITLE and INFO before this function while keeping path, target, template, and
directory lifecycle under Org-roam Organize control."
  (let ((key (car-safe template)))
    (unless (and (stringp title)
                 (not (org-roam-organize--blank-string-p title)))
      (user-error "Node title cannot be empty"))
    (unless (and template key)
      (user-error "Cannot capture node without a valid template"))
    (let ((node (org-roam-node-create :title title)))
      (if manage-directory
          (let ((org-roam-organize--capture-created-directory nil))
            (cl-labels
                ((cleanup ()
                   (when org-roam-organize--capture-created-directory
                     (run-at-time
                      0 nil
                      #'org-roam-organize--delete-empty-directory
                      org-roam-organize--capture-created-directory))))
              (let ((org-roam-capture-preface-hook
                     (cons #'org-roam-organize--capture-create-parent-directory
                           org-roam-capture-preface-hook))
                    (org-capture-after-finalize-hook
                     (append org-capture-after-finalize-hook
                             (list #'cleanup))))
                (condition-case err
                    (org-roam-capture- :node node
                                       :keys key
                                       :info info
                                       :props props
                                       :templates (list template))
                  (error
                   (when org-roam-organize--capture-created-directory
                     (org-roam-organize--delete-empty-directory
                      org-roam-organize--capture-created-directory))
                   (signal (car err) (cdr err)))))))
        (org-roam-capture- :node node
                           :keys key
                           :info info
                           :props props
                           :templates (list template))))))

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
        names tags paths directories)
    (if (not (org-roam-organize--proper-list-p org-roam-organize-registry))
        (cons nil "`org-roam-organize-registry' must be a proper list.")
      (dolist (record org-roam-organize-registry)
        (let* ((plistp (org-roam-organize--plistp record))
               (name (when plistp (org-roam-organize--record-name record)))
               (tag (when plistp (org-roam-organize--record-tag record)))
               (moc (when plistp (plist-get record :moc)))
               (basic (when plistp (plist-get record :basic)))
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
            (when (org-roam-organize--record-moc-p record)
              (setq moc-count (1+ moc-count))
              (unless (org-roam-organize--record-basic-p record)
                (setq result_bool nil)
                (setq result_message
                      (concat result_message "  :moc t requires :basic t\n"))))
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
                          (not (memq (car-safe section) '(properties keywords))))
                        template))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  :template section keys? nil (should be properties or keywords)\n")))
            (when (and (org-roam-organize--proper-list-p template)
                       (seq-find
                        (lambda (section)
                          (not (org-roam-organize--proper-list-p (cdr-safe section))))
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

(defun org-roam-organize--moc-node-entry-line (id title &optional delete)
  "Return a MOC node entry line for ID, TITLE, and DELETE flag.

Implementation notes: `org-link-make-string' constructs the id link so link
descriptions are escaped according to Org syntax.  The optional delete marker
is appended as keyword suffix data and otherwise left uninterpreted here."
  (format "#+%s: %s%s\n"
          org-roam-organize--moc-node-keyword
          (org-link-make-string (concat "id:" id) title)
          (if delete " :delete t" "")))

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

(defun org-roam-organize--moc-parse-node-entry-value (value)
  "Parse a MOC node entry keyword VALUE.

Return a plist with `:id', `:title', and `:delete', or nil when VALUE does
not contain a valid id link at the beginning.

Implementation notes: VALUE is parsed in a temporary Org buffer so link
syntax is handled by Org Element rather than regular expressions.  Only the
first id link with no non-whitespace prefix is accepted; text after the link
is passed to the delete-marker parser."
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
                        (list
                         :id (org-element-property :path link)
                         :title description
                         :delete
                         (org-roam-organize--moc-node-entry-delete-p
                          suffix)))))))))
      link-result)))

(defun org-roam-organize--moc-parse-node-entries ()
  "Parse MOC node entries in the current buffer.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:delete', `:begin', and `:end'.

Implementation notes: the current buffer is parsed with Org Element and only
real `#+ROAM_NODE' keyword elements outside COMMENT context are considered.
Malformed lines are retained as strings for reporting, while legal entries
carry buffer positions so sync can replace or remove them later."
  (let (entries malformed)
    (org-element-map (org-element-parse-buffer) 'keyword
      (lambda (keyword)
        (when (and (string= (org-element-property :key keyword)
                            org-roam-organize--moc-node-keyword)
                   (not
                    (org-roam-organize--element-commented-p keyword)))
          (let* ((begin (org-element-property :begin keyword))
                 (end (org-element-property :end keyword))
                 (value (org-element-property :value keyword))
                 (parsed
                  (org-roam-organize--moc-parse-node-entry-value value)))
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

(defun org-roam-organize--moc-inbox-headline (name)
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

(defun org-roam-organize--moc-first-child-headline-begin (headline)
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

(defun org-roam-organize--moc-inbox-insertion-point (name)
  "Return the insertion point for new MOC node entries.

Create the level-1 Inbox headline named NAME when it is missing.

Implementation notes: existing inboxes receive new entries before their first
child headline, preserving manual subsection structure.  Missing inboxes are
appended as a level-1 headline at the end of the file."
  (let ((inbox (org-roam-organize--moc-inbox-headline name)))
    (if inbox
        (let ((child-begin
               (org-roam-organize--moc-first-child-headline-begin inbox))
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

(defun org-roam-organize--moc-sync-node-entries (record nodes)
  "Sync MOC node entries for RECORD from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: NODES are indexed by id in a hash table.  Existing
entries are parsed with Org Element, duplicates are detected with a second
hash table, and replacements/removals run from the end of the buffer toward
the beginning so saved positions remain valid.  Missing nodes are appended
after existing edits have completed."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (node-table (make-hash-table :test 'equal))
        (seen-table (make-hash-table :test 'equal))
        duplicate-ids removed-ids malformed-lines)
    (dolist (node nodes)
      (puthash (plist-get node :id) node node-table))
    (if (not (and path (file-exists-p path)))
        (list :status 'failed
              :record record
              :reason "MOC file does not exist")
      (with-current-buffer (find-file-noselect path)
        (let* ((parse-result (org-roam-organize--moc-parse-node-entries))
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
                     (org-roam-organize--moc-node-entry-line
                      id
                      (plist-get node :title)
                      (plist-get entry :delete))))
                (push id removed-ids)
                (delete-region (plist-get entry :begin)
                               (plist-get entry :end)))))
          (let (missing-nodes)
            (dolist (node nodes)
              (unless (gethash (plist-get node :id) seen-table)
                (push node missing-nodes)))
            (when missing-nodes
              (org-roam-organize--moc-inbox-insertion-point
               (org-roam-organize--record-inbox record))
              (dolist (node (nreverse missing-nodes))
                (insert
                 (org-roam-organize--moc-node-entry-line
                  (plist-get node :id)
                  (plist-get node :title)))))))
        (save-buffer)
        (list :status 'ok
              :record record
              :duplicates (nreverse duplicate-ids)
              :removed (nreverse removed-ids)
              :malformed malformed-lines)))))

;; hash 表转换为 alist
(defun org-roam-organize--hash-table-to-alist (hash_table)
  "Return HASH_TABLE as an alist when organize mode is enabled.

Implementation notes: the function walks HASH_TABLE with `maphash', pushes
each key/value cons to a list, and reverses the result to compensate for push
order.  It is kept small because callers decide whether alist ordering
matters."
  (when org-roam-organize-mode
    (let (result)
      (maphash
       (lambda
         (key value)
         (push (cons key value) result))
       hash_table)
      (nreverse result))))  ;; Reverse the list back to original order.

;; alist 转换为 hash 表
(defun org-roam-organize--alist-to-hash-table (alist)
  "Return ALIST grouped into a hash table when organize mode is enabled.

Implementation notes: duplicate keys are preserved by appending each cdr to
the existing value list.  This is used for database rows where one source key
can refer to many destination node ids."
  (when org-roam-organize-mode
    (let ((ht (make-hash-table :test 'equal)))
      (dolist (row alist)
        (puthash
         (car row)
         (append (gethash (car row) ht) (list (cdr row)))
         ht))
      ht)))

;; 替换 tag
(defun org-roam-organize--update-filetag (file source_tag target_tag)
  "In FILE, replace SOURCE_TAG with TARGET_TAG in #+FILETAGS.

If no #+FILETAGS line exists, do nothing.

Implementation notes: this legacy helper opens FILE without selecting it,
searches for the first FILETAGS line, and performs a narrow textual
replacement of `:SOURCE_TAG:' with `:TARGET_TAG:'.  It intentionally does not
create FILETAGS or reinterpret unrelated tag text."
  (when org-roam-organize-mode
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+FILETAGS:[ \t]*\\(.*\\)$" nil t)
          (let* ((old (match-string 1))
                 ;; 保留所有原有 tag, 只替换 source_tag.
                 (new (replace-regexp-in-string (concat ":" source_tag ":") (concat ":" target_tag ":") old)))
            (unless (string= old new)
              ;; 用 new 覆盖 old.
              (replace-match new nil nil nil 1)
              (save-buffer)
              (message "Updated FILETAGS in %s: %s → %s" file source_tag target_tag)))
        (message "No #+FILETAGS: found in %s; skipping tag update" file)))))

;; 从光标获取 headline 中通过 id 引用指向的 node 信息
(defun org-roam-organize--get-node-info-from-cite-in-headline (&optional pos)
  "Return id and Org-roam node referenced by the headline at POS.

Implementation notes: the function inspects the Org element at POS, requires
it to be a headline, extracts the first `[[id:...]]' link from the raw
headline title with a simple compatibility regexp, and resolves that id with
`org-roam-node-from-id'."
  (when org-roam-organize-mode
    (let* ((pos (or pos (point)))
           (el (save-excursion (goto-char pos) (org-element-at-point)))
           (title (org-element-property :raw-value el))
           id node)
      ;; 检查 headline 类型.
      (unless (eq (org-element-type el) 'headline)
        (user-error "Not on a headline"))
      ;; 提取 id.
      (setq id
            (if (string-match "\\[\\[id:\\([^]]+\\)\\]\\[" title)
                (match-string 1 title)
              (user-error "No [[id:...]] link found in this headline")))
      ;; 获取 org-roam node.
      (setq node
            (or
             (org-roam-node-from-id id)
             (user-error "No org-roam node with id %s" id)))
      ;; 返回 plist.
      (list :id id :node node))))

;; 对给定 tag 列表, 查出数据库中 nodes 表内 level=0 的 node 数量
(defun org-roam-organize--count-nodes-with-given-tag-list (tag_list &optional hash_to_alist)
  "Return tag counts for level-0 nodes in TAG_LIST.

When HASH_TO_ALIST is non-nil, return an alist.  Otherwise return a hash
table.  Tags not present in the Org-roam database are assigned zero.

Implementation notes: the result hash is prefilled with zero for every input
tag, then updated from a grouped Org-roam DB query.  The query joins `tags'
to level-0 `nodes' so headline tags do not affect file-node counts."
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
          (org-roam-organize--hash-table-to-alist tag_count)
        tag_count))))

;; 检查需要却没有被插入 link 于给定 node 的 node id
(defun org-roam-organize--check-file-node-no-linked-headline (tag_id table col)
  "Return missing linked headline targets for TAG_ID.

TAG_ID is an alist of TAG . ID.  TABLE and COL select the Org-roam database
table and column used to find candidate nodes.  Return an alist of source node
id to destination node id list.

Implementation notes: the first query dynamically selects all candidate node
ids from TABLE/COL for each tag-like key.  The second query reads existing id
links from each source node.  Both row sets are grouped into hash tables, then
set difference produces the missing destination ids per source."
  (when org-roam-organize-mode
    (let* ((tag_list
            (mapcar (lambda (e) (format "%s" (car e))) tag_id))
           (id_list
            (mapcar (lambda (e) (format "%s" (cdr e))) tag_id))
           (result_tag_all_id
            (mapcar
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query
              (vector :select (vector (intern (concat "t:" col)) (intern "t:node_id"))
                      :from (list 'as (intern (concat table)) 't)
                      :join '(as nodes n) :on '(and (= n:level 0) (= n:id t:node_id))
                      :where (list 'in (intern (concat "t:" col)) '$v1))
              (vconcat tag_list))))
           (result_id_linked_id
            (mapcar
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query
              (vector :select (vector 'l:source 'l:dest)
                      :from '(as links l)
                      :join '(as nodes n) :on '(and (= n:level 0) (= n:id l:dest))
                      :where '(and (= l:type "id") (in l:source $v1)))
              (vconcat id_list))))
           (tag_to_nodes (org-roam-organize--alist-to-hash-table result_tag_all_id))
           (source_to_linked (org-roam-organize--alist-to-hash-table result_id_linked_id)))
      (cl-loop
       for pair in tag_id
       for tag    = (car pair)
       for source = (cdr pair)
       for all_nodes   = (gethash tag tag_to_nodes)
       for linked_nodes = (gethash source source_to_linked)
       collect
       (cons
        source
        (let ((linked-ht (make-hash-table :test 'equal)))
          (dolist (x linked_nodes)
            (puthash x t linked-ht))
          (seq-filter
           (lambda (x) (not (gethash x linked-ht)))
           all_nodes)))))))

;; 在给定 id 的 node 中插入指定形式的 id 型 link
(defun org-roam-organize--insert-id-type-link-headline (pair)
  "Insert Org entries for level-0 nodes in PAIR.

PAIR is a cons cell of source node id to destination node id list.

Implementation notes: source and destination ids are resolved back to
Org-roam nodes.  For each resolvable destination, a second-level id-link
headline is appended to the source node's file and the buffer is saved."
  (when org-roam-organize-mode
    (let* ((source_id (car pair))
           (dest_ids (cdr pair)))
      (when dest_ids
        (dolist (id dest_ids)
          (let* ((node (org-roam-node-from-id id))
                 (source-node (org-roam-node-from-id source_id)))
            (when (and node source-node)
              (let* ((content
                      (format "** [[id:%s][%s]]\n"
                              (org-roam-node-id node)
                              (org-roam-node-title node))))
                (with-current-buffer (find-file-noselect (org-roam-node-file source-node))
                  (goto-char (point-max))
                  (insert content)
                  (save-buffer))
                (message "%s" content)))))))))

;; ==============================
;; 可调用结构函数
;; ==============================

;; 变量检查
;;;###autoload
(defun org-roam-organize-check-variables ()
  "Check Org-roam Organize configuration variables.

Implementation notes: this interactive wrapper delegates to
`org-roam-organize--check-variables' with the package's declared variable
type table, then displays the generated report in the echo area."
  (interactive)
  (let ((check_result (org-roam-organize--check-variables org-roam-organize-directory org-roam-organize--variable-type-alist)))
    (message "%s" (if (consp check_result)
                      (cdr check_result)
                    check_result))))

;;;###autoload
(defun org-roam-organize-check-setup ()
  "Check whether Org-roam Organize can be enabled.

This command reports both variable validation and runtime capability
validation.

Implementation notes: the command is a user-facing wrapper around
`org-roam-organize--check-setup'.  It adds a short success prefix when all
subchecks pass and otherwise relays the detailed failure report unchanged."
  (interactive)
  (let ((check_result (org-roam-organize--check-setup)))
    (message "%s"
             (if (and (consp check_result)
                      (car check_result))
                 (concat
                  "Org-roam Organize setup checks passed.\n"
                  (cdr check_result))
               (if (consp check_result)
                   (cdr check_result)
                 check_result)))))

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
as failed, and missing files are created through `org-roam-capture-' with a
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
                 (title (org-roam-organize--record-moc-title record)))
            (cond
             ((not (and path template tag title))
              (setq failed-count (1+ failed-count))
              (message "[WARNING] Cannot create MOC for registry record: %s" record))
             ((file-exists-p path)
              (setq skipped-count (1+ skipped-count))
              (message "[INFO] MOC already exists, skipped: %s" path))
             (t
              (org-roam-organize--capture-node
               title
               template
               `(:moc_managed_tag ,tag)
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
<directory>/${id}/${slug}.org under `org-roam-organize-directory'.
If the record declares `:provider', that provider supplies the node title and
optional capture info; otherwise the built-in default provider reads a title.
Org-roam Organize creates the UUID parent directory during Org-roam's capture
preface phase and removes it after capture only when it remains empty.

Implementation notes: the command reads a registry record, obtains its
provider with `org-roam-organize--record-provider', calls the provider to get
a node creation request, builds a temporary one-entry capture template, and
delegates the capture call to `org-roam-organize--capture-node'.  That helper
installs a dynamically scoped preface hook to create the expanded parent
directory after Org-roam has assigned capture placeholders and an
after-finalize hook to remove only that directory if it stayed empty."
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
               t))))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 同步 MOC
;;;###autoload
(defun org-roam-organize-moc-sync ()
  "Sync managed MOC files from Org-roam node tags.

Implementation notes: the command refreshes access to the Org-roam database,
then walks registry records.  For each tag, matching level-0 nodes are loaded
from the DB, node entries are synchronized in the corresponding MOC file, and
derived managed properties are updated only after a successful entry sync."
  (interactive)
  (if org-roam-organize-mode
      (let ((synced-count 0)
            (failed-count 0)
            (duplicate-count 0)
            (removed-count 0)
            (malformed-count 0))
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
              (message "[WARNING] Cannot sync MOC for registry record: %s" record))
             ((eq (plist-get result :status) 'failed)
              (setq failed-count (1+ failed-count))
              (message "[WARNING] Cannot sync MOC for registry record: %s (%s)"
                       record
                       (plist-get result :reason)))
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
        (message
         "[INFO] Sync MOCs: %s synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries."
         synced-count failed-count duplicate-count removed-count malformed-count))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 文献节点反链补全
;;;###autoload
(defun org-roam-organize-ref-complete-backlinks ()
  "Append missing literature backlinks from citation data.

Implementation notes: cite refs are read from the Org-roam `refs' table,
then `org-roam-organize--check-file-node-no-linked-headline' compares them
with citation rows and existing id links.  Missing destinations are appended
as second-level id-link headlines in the literature node files."
  (interactive)
  (if org-roam-organize-mode
      (progn
        (message "[INFO] Begin Check and Insert. ")
        (org-roam-db)
        (let* ((ref_id (mapcar
                        (lambda (x) (cons (nth 0 x) (nth 1 x)))
                        (org-roam-db-query
                         (vector :select (vector 'r:ref 'r:node_id)
                                 :from '(as refs r)
                                 :join '(as nodes n) :on '(and (= n:level 0) (= n:id r:node_id))
                                 :where '(= r:type "cite")))))
               (source_dest_alist (org-roam-organize--check-file-node-no-linked-headline ref_id "citations" "cite_key")))
          (message "[INFO] Check Complete. Insert backlinks Start up. ")
          (dolist
              (pair source_dest_alist)
            (org-roam-organize--insert-id-type-link-headline pair))
          (message "[INFO] Insert Complete. ")))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; ==============================
;; Minor-Mode
;; ==============================

;; Definition.
;;;###autoload
(define-minor-mode org-roam-organize-mode
  "org-roam-organize mode"
  :lighter " Organize"
  ;; :group nil
  :global t
  :init-value nil)

;; Hook.
(add-hook 'org-roam-organize-mode-hook
          (lambda ()
            (when org-roam-organize-mode
              (let* ((check_result
                      (when (and (boundp 'org-roam-organize--variable-type-alist)
                                 (boundp 'org-roam-organize--capability-alist))
                        (org-roam-organize--check-setup))))
                (cond
                 ((not (car check_result))
                  (setq org-roam-organize-mode nil)
                  (message "%s" (concat
                                 "[WARNING] Org Roam Organize setup checks failed. "
                                 "Org Roam Organize Mode setup failed.\n"
                                 (format "%s\n" (car check_result))
                                 (cdr check_result))))
                 (t
                  (unless (featurep 'org) (require 'org))
                  (unless (featurep 'org-element) (require 'org-element))
                  (unless (featurep 'org-roam) (require 'org-roam))
                  (unless (featurep 'cl-lib) (require 'cl-lib))))))))

(provide 'org-roam-organize)
;;; org-roam-organize.el ends here
