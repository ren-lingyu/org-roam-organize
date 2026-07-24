;;; org-roam-organize.el --- Organize Org-roam node references -*- lexical-binding: t; -*-

;; Copyright (C) 2026 aRenCoco

;; Author: aRenCoco
;; Maintainer: aRenCoco
;; Version: 0.4.0
;; Package-Requires: ((emacs "30.1") (org "9.5") (org-roam "2.2.0"))
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
;; completing backlinks, and updating node statistics.
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
(defcustom org-roam-organize-root-directory
  org-roam-directory
  "org-roam-organize 根目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize-allow-outside-root
  nil
  "Bool 型变量, 是否允许在非 org-roam-organize 根目录下启动 org-roam-organize, 默认值为nil"
  :type 'boolean
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
  '((:name "maps"
     :tag "map"
     :moc t
     :basic t
     :directory "moc")
    (:name "fleeting"
     :tag "idea"
     :basic t
     :directory "fleeting")
    (:name "literature"
     :tag "ref"
     :basic t
     :directory "literature")
    (:name "permanent"
     :tag "zettel"
     :basic t
     :directory "permanent")
    (:name "note"
     :tag "note")
    (:name "blog"
     :tag "blog"))
  "Registry of MOC records managed by Org-roam Organize.

Each record is a plist.  `:name' and `:tag' are required strings.
`:moc' and `:basic' are optional booleans.  A basic record must have
a relative `:directory'.  `:moc-path' and `:moc-title' are optional
overrides resolved from the record name when absent."
  :type 'sexp
  :group 'org-roam-organize)

(defcustom org-roam-organize-moc-file-keywords
  '((author . nil)
    (date . nil)
    (description . nil))
  "Optional Org file keywords written when creating MOC files.

Missing keys are not written.  Keys whose value is nil are written with an
empty value.  String values are formatted according to
`org-roam-organize--moc-file-keyword-formatter-alist'."
  :type 'alist
  :group 'org-roam-organize)

;; ==============================
;; 常量定义
;; ==============================

(defconst org-roam-organize--variable-type-alist
  '((org-roam-organize-root-directory . directory)
    (org-roam-organize-moc-managed-tag-property . string)
    (org-roam-organize-moc-managed-node-count-property . string)
    (org-roam-organize-allow-outside-root . boolean)
    (org-roam-organize-registry . list)
    (org-roam-organize-moc-file-keywords . list)))

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
    (org-id-find . function)
    (org-element-at-point . function)
    (org-element-type . function)
    (org-element-property . function)
    (org-back-to-heading . function)
    (org-entry-put . function)
    (seq-filter . function))
  "Runtime capabilities required by Org-roam Organize.

The list maps symbols to capability types checked by
`org-roam-organize--check-capabilities'.")

(defconst org-roam-organize--record-name-regexp
  (rx string-start (+ (any "A-Za-z0-9_-")) string-end)
  "Regexp matching a safe Org-roam Organize registry record name.")

(defconst org-roam-organize--moc-capture-key "m"
  "Capture key used internally when creating MOC files.")

(defconst org-roam-organize--moc-file-keyword-formatter-alist
  '((author . identity)
    (date . format-time-string)
    (description . identity))
  "Allowed optional MOC file keywords and their formatters.")

;; ==============================
;; 内部函数
;; ==============================

;; 变量检查(不依赖 minor-mode 开启)
(defun org-roam-organize--check-variables (root_dir alist)
  "Check Org-roam Organize variables in ALIST under ROOT_DIR.

ALIST should map variable symbols to expected type symbols.  Directory
variables must be existing directories inside ROOT_DIR.  Return a cons cell
whose car is the boolean result and whose cdr is a human-readable report."
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
the running Emacs."
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
  "Check whether the Org-roam Organize root is inside `org-roam-directory'."
  (let* ((root org-roam-organize-root-directory)
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
      (format "- org-roam-organize-root-directory? %s\n" root)
      (format "- org-roam-directory? %s\n" roam-root)
      (format "  in org-roam-directory? %s (should be t)\n" inside-p)))))

(defun org-roam-organize--record-name (record)
  "Return RECORD's name."
  (plist-get record :name))

(defun org-roam-organize--record-name-p (name)
  "Return non-nil if NAME is a safe registry record name."
  (and (stringp name)
       (string-match-p org-roam-organize--record-name-regexp name)))

(defun org-roam-organize--record-tag (record)
  "Return RECORD's managed node tag."
  (plist-get record :tag))

(defun org-roam-organize--record-moc-p (record)
  "Return non-nil if RECORD manages MOC nodes."
  (eq (plist-get record :moc) t))

(defun org-roam-organize--record-basic-p (record)
  "Return non-nil if RECORD is a basic registry record."
  (eq (plist-get record :basic) t))

(defun org-roam-organize--record-directory (record)
  "Return RECORD's relative node directory."
  (plist-get record :directory))

(defun org-roam-organize--registry-moc-record ()
  "Return the registry record that manages MOC nodes."
  (seq-find #'org-roam-organize--record-moc-p
            (seq-filter #'org-roam-organize--plistp
                        org-roam-organize-registry)))

(defun org-roam-organize--registry-basic-records ()
  "Return basic records from `org-roam-organize-registry'."
  (seq-filter #'org-roam-organize--record-basic-p
              (seq-filter #'org-roam-organize--plistp
                          org-roam-organize-registry)))

(defun org-roam-organize--record-moc-title (record)
  "Return RECORD's MOC title."
  (let ((explicit-title (plist-get record :moc-title))
        (name (org-roam-organize--record-name record)))
    (cond
     ((stringp explicit-title) explicit-title)
     ((plist-member record :moc-title) nil)
     ((org-roam-organize--record-name-p name) (upcase-initials name))
     (t nil))))

(defun org-roam-organize--record-moc-path (record)
  "Return RECORD's relative MOC file path."
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
  "Return non-nil if relative PATH resolves inside root directory."
  (and (stringp path)
       (not (file-name-absolute-p path))
       (file-in-directory-p
        (expand-file-name path org-roam-organize-root-directory)
        (file-name-as-directory
         (expand-file-name org-roam-organize-root-directory)))))

(defun org-roam-organize--absolute-path-in-root (path)
  "Return normalized absolute PATH under root, or nil."
  (when (org-roam-organize--path-inside-root-p path)
    (expand-file-name path org-roam-organize-root-directory)))

(defun org-roam-organize--record-absolute-directory (record)
  "Return RECORD's absolute node directory."
  (let ((directory (org-roam-organize--record-directory record)))
    (org-roam-organize--absolute-path-in-root directory)))

(defun org-roam-organize--record-absolute-moc-path (record)
  "Return RECORD's absolute MOC file path."
  (let ((path (org-roam-organize--record-moc-path record)))
    (org-roam-organize--absolute-path-in-root path)))

(defun org-roam-organize--moc-file-keyword-name (key)
  "Return Org file keyword name for KEY."
  (upcase (symbol-name key)))

(defun org-roam-organize--moc-file-keyword-line (key)
  "Return optional Org file keyword line for KEY, or nil."
  (let ((entry (assoc key org-roam-organize-moc-file-keywords))
        (formatter
         (cdr (assoc key org-roam-organize--moc-file-keyword-formatter-alist))))
    (when entry
      (let ((value (cdr entry)))
        (cond
         ((null value)
          (format "#+%s:\n" (org-roam-organize--moc-file-keyword-name key)))
         ((and (stringp value) (functionp formatter))
          (format "#+%s: %s\n"
                  (org-roam-organize--moc-file-keyword-name key)
                  (funcall formatter value)))
         (t
          (message "[WARNING] Ignored invalid MOC file keyword value: %s" entry)
          nil))))))

(defun org-roam-organize--warn-unknown-moc-file-keywords ()
  "Warn about unknown keys in `org-roam-organize-moc-file-keywords'."
  (dolist (entry org-roam-organize-moc-file-keywords)
    (unless (assoc (car-safe entry)
                   org-roam-organize--moc-file-keyword-formatter-alist)
      (message "[WARNING] Ignored unknown MOC file keyword: %s" entry))))

(defun org-roam-organize--record-moc-head (record)
  "Return the Org file head for RECORD's MOC file."
  (let ((tag (org-roam-organize--record-tag record))
        (title (org-roam-organize--record-moc-title record))
        (moc-record (org-roam-organize--registry-moc-record)))
    (when (and (stringp tag)
               (stringp title)
               moc-record
               (stringp (org-roam-organize--record-tag moc-record)))
      (org-roam-organize--warn-unknown-moc-file-keywords)
      (concat
       (format ":PROPERTIES:\n:%s: %s\n:%s:\n:END:\n#+TITLE: %s\n"
               org-roam-organize-moc-managed-tag-property
               tag
               org-roam-organize-moc-managed-node-count-property
               title)
       (or (org-roam-organize--moc-file-keyword-line 'author) "")
       (or (org-roam-organize--moc-file-keyword-line 'date) "")
       (format "#+FILETAGS: :%s:\n"
               (org-roam-organize--record-tag moc-record))
       (or (org-roam-organize--moc-file-keyword-line 'description) "")))))

(defun org-roam-organize--proper-list-p (object)
  "Return non-nil if OBJECT is a proper list."
  (let ((tail object))
    (while (consp tail)
      (setq tail (cdr tail)))
    (null tail)))

(defun org-roam-organize--plistp (object)
  "Return non-nil if OBJECT is a plist-like proper list."
  (and (org-roam-organize--proper-list-p object)
       (= 0 (% (length object) 2))))

(defun org-roam-organize--validate-registry ()
  "Validate `org-roam-organize-registry'.

Return a cons cell whose car is the boolean result and whose cdr is a
human-readable report."
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
                      (concat result_message "  :basic t requires string :directory\n"))))
             (directory
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  non-basic record must not define :directory\n"))))
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
            (when (and absolute-directory (member absolute-directory directories))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :directory unique? nil (should be t)\n")))
            (when absolute-directory
              (push absolute-directory directories))
            (unless (stringp moc-title)
              (setq result_bool nil)
              (setq result_message
                    (concat result_message "  resolved :moc-title string? nil (should be t)\n"))))))
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
human-readable report."
  (let ((variable_check_result
         (org-roam-organize--check-variables
          org-roam-organize-root-directory
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
  "Return the level-0 Org-roam node id for absolute file PATH."
  (caar
   (org-roam-db-query
    [:select [n:id]
             :from (as nodes n)
             :where (and (= n:level 0) (= n:file $s1))]
    path)))

(defun org-roam-organize--registry-tag-id-alist ()
  "Return an alist of managed tag to MOC node id from registry records."
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

(defun org-roam-organize--record-capture-template (record)
  "Return a MOC capture template for RECORD."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (head (org-roam-organize--record-moc-head record)))
    (when (and (stringp path) (stringp head))
      (list org-roam-organize--moc-capture-key
            "map of contents"
            'plain
            "%?"
            :if-new
            (list 'file+head path head)))))

;; hash表转换为alist
(defun org-roam-organize--hash-table-to-alist (hash_table)
  (when org-roam-organize-mode
    (let (result)
      (maphash
       (lambda
         (key value)
         (push (cons key value) result))
       hash_table)
      (nreverse result))))  ;; nreverse to reverse the list back to original order

;; alist转换为hash表
(defun org-roam-organize--alist-to-hash-table (alist)
  (when org-roam-organize-mode
    (let ((ht (make-hash-table :test 'equal)))
      (dolist (row alist)
        (puthash
         (car row)
         (append (gethash (car row) ht) (list (cdr row)))
         ht))
      ht)))

;; 替换tag
(defun org-roam-organize--update-filetag (file source_tag target_tag)
  "In FILE, replace SOURCE_TAG with TARGET_TAG in #+FILETAGS: line only. If no #+FILETAGS: line exists, do nothing."
  (when org-roam-organize-mode
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+FILETAGS:[ \t]*\\(.*\\)$" nil t)
          (let* ((old (match-string 1))
                 ;; 保留所有原有 tag，只替换 source_tag
                 (new (replace-regexp-in-string (concat ":" source_tag ":") (concat ":" target_tag ":") old)))
            (unless (string= old new)
              ;; 用 new 覆盖 old
              (replace-match new nil nil nil 1)
              (save-buffer)
              (message "Updated FILETAGS in %s: %s → %s" file source_tag target_tag)))
        (message "No #+FILETAGS: found in %s; skipping tag update" file)))))

;; 从光标获取headline中通过id的引用指向的node的信息
(defun org-roam-organize--get-node-info-from-cite-in-headline (&optional pos)
  (when org-roam-organize-mode
    (let* ((pos (or pos (point)))
           (el (save-excursion (goto-char pos) (org-element-at-point)))
           (title (org-element-property :raw-value el))
           id node file)
      ;; 检查 headline 类型
      (unless (eq (org-element-type el) 'headline)
        (user-error "Not on a headline"))
      ;; 提取 id
      (setq id
            (if (string-match "\\[\\[id:\\([^]]+\\)\\]\\[" title)
                (match-string 1 title)
              (user-error "No [[id:...]] link found in this headline")))
      ;; 获取 org-roam node
      (setq node
            (or
             (org-roam-node-from-id id)
             (user-error "No org-roam node with id %s" id)))
      ;; 返回 plist
      (list :id id :node node))))

;; 对给定tag列表, 查出数据库中表nodes内level=0的node数量
(defun org-roam-organize--count-nodes-with-given-tag-list (tag_list &optional hash_to_alist)
  "Return an alist of (TAG . COUNT) for level=0 nodes, given a list of TAGS. Includes all tags in TAG_LIST, assigning zero to those not present in DB. The input parameter must be a 1-dim' list or vector. "
  (when org-roam-organize-mode
    (let* ((tag_count (make-hash-table :test 'equal))
           (result
            (org-roam-db-query
             [:select [t:tag (funcall count t:tag)]
                      :from (as tags t)
                      :join (as nodes n)
                      :on (and (= n:level 0) (= n:id t:node_id))
                      :where (in t:tag $v1)
                      :group-by t:tag]
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

;; 检查需要却没有被插入link于给定node的node的id
(defun org-roam-organize--check-file-node-no-linked-headline (tag_id table col)
  "Given TAG_ID (alist of TAG . ID), return an alist of (source_id . dest_id_list) where dest_id_list contains level=0 node ids for TAG not already linked from source_id."
  (when org-roam-organize-mode
    (let* ((tag_list
            (mapcar (lambda (e) (format "%s" (car e))) tag_id))
           (id_list
            (mapcar (lambda (e) (format "%s" (cdr e))) tag_id))
           (result_tag_all_id
            (mapcar
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query
              (vector
               :select (vector (intern (concat "t:" col)) (intern "t:node_id"))
               :from (list 'as (intern (concat table)) 't)
               :join '(as nodes n) :on '(and (= n:level 0) (= n:id t:node_id))
               :where (list 'in (intern (concat "t:" col)) '$v1))
              (vconcat tag_list))))
           (result_id_linked_id
            (mapcar
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query
              [:select [l:source l:dest]
                       :from (as links l)
                       :join (as nodes n) :on (and (= n:level 0) (= n:id l:dest))
                       :where (and (= l:type "id") (in l:source $v1))]
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

;; 在给定id的node中插入指定形式的id型link
(defun org-roam-organize--insert-id-type-link-headline (pair)
  "Insert org entries for level0 nodes given SOURCE_DEST_ALIST. PAIR is a cons cell of (source_id . dest_id_list), where source_id is a string and dest_id_list is a list of node IDs (may be empty)."
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
  "Check Org-roam Organize configuration variables."
  (interactive)
  (let ((check_result (org-roam-organize--check-variables org-roam-organize-root-directory org-roam-organize--variable-type-alist)))
    (message "%s" (if (consp check_result)
                      (cdr check_result)
                    check_result))))

;;;###autoload
(defun org-roam-organize-check-setup ()
  "Check whether Org-roam Organize can be enabled.

This command reports both variable validation and runtime capability
validation."
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
  (interactive)
  (let ((dir_list
         (cons
          org-roam-organize-root-directory
          (mapcar #'org-roam-organize--record-absolute-directory
                  (org-roam-organize--registry-basic-records)))))
    (dolist (dir dir_list)
      (unless (or (not dir) (file-exists-p dir))
        (make-directory dir t)))))

;; ==============================
;; 可调用功能函数
;; ==============================

;; 打开顶层moc
;;;###autoload
(defun org-roam-organize-moc-open-index ()
  "Open the top-level Map of Contents file using its file path."
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
  "Create missing MOC files declared in `org-roam-organize-registry'."
  (interactive)
  (if org-roam-organize-mode
      (let ((debug-on-error t)
            (created-count 0)
            (skipped-count 0)
            (failed-count 0))
        (dolist (record org-roam-organize-registry)
          (let* ((path (org-roam-organize--record-absolute-moc-path record))
                 (template (org-roam-organize--record-capture-template record))
                 (key (car template))
                 (tag (org-roam-organize--record-tag record))
                 (title (org-roam-organize--record-moc-title record)))
            (cond
             ((not (and path template key tag title))
              (setq failed-count (1+ failed-count))
              (message "[WARNING] Cannot create MOC for registry record: %s" record))
             ((file-exists-p path)
              (setq skipped-count (1+ skipped-count))
              (message "[INFO] MOC already exists, skipped: %s" path))
             (t
              (org-roam-capture- :node (org-roam-node-create :title title)
                                 :keys key
                                 :info `(:moc_managed_tag ,tag)
                                 :props '(:immediate-finish t)
                                 :templates (list template))
              (setq created-count (1+ created-count))))))
        (message "[INFO] Create missing MOCs: %s created, %s skipped, %s failed."
                 created-count skipped-count failed-count))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 更新moc
;;;###autoload
(defun org-roam-organize-moc-update ()
  "Update Org-roam nodes with tag count information. For each tag in `tag-id-alist`, count how many nodes have that tag, and write the count into the corresponding node's property field."
  (interactive)
  (if org-roam-organize-mode
      (let* ((moc_count_prop org-roam-organize-moc-managed-node-count-property)
             (tag_id_result (org-roam-organize--registry-tag-id-alist))
             (tag_id (car tag_id_result))
             (missing_records (cdr tag_id_result))
             (sth_unexpected nil))
        ;; 开始提示
        (message "[INFO] Begin Check and Update. ")
        (org-roam-db)
        (when missing_records
          (setq sth_unexpected t)
          (message "[WARNING] Some registry records do not resolve to level-0 MOC nodes: %s"
                   missing_records))
        (cond
         ((not tag_id)
          (progn
            (setq sth_unexpected t)
            (message "[WARNING] No tag-id map found. ")))
         (t
          (let* ((inhibit-message t)
                 (tag_list (mapcar (lambda (e) (format "%s" (car e))) tag_id))
                 (tag_count_hash (org-roam-organize--count-nodes-with-given-tag-list tag_list))
                 (source_dest_alist (org-roam-organize--check-file-node-no-linked-headline tag_id "tags" "tag")))
            (dolist (entry tag_id)
              (let* ((tag (car entry))
                     (id (cdr entry))
                     (count (gethash tag tag_count_hash))
                     (marker (org-id-find id 'marker)))
                (if (and marker
                         count)
                    (progn
                      (with-current-buffer (marker-buffer marker)
                        (goto-char marker)
                        (let ((field (format "%s" (upcase moc_count_prop))))
                          (org-entry-put (point) field (number-to-string count))
                          (save-buffer))))
                  (progn
                    (setq sth_unexpected t)
                    (message "[WARNING] SQL query failed or ID input is invalid. ")))))
            (dolist (pair source_dest_alist)
              (org-roam-organize--insert-id-type-link-headline pair)))))
        (if sth_unexpected
            (message "[WARNING] End, but something UNEXPECTED happened, please check *Message*. ")
          (message "[INFO] Update Successful. ")))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 文献节点反链补全
;;;###autoload
(defun org-roam-organize-ref-complete-backlinks ()
  (interactive)
  (if org-roam-organize-mode
      (progn
        (message "[INFO] Begin Check and Insert. ")
        (org-roam-db)
        (let* ((ref_id (mapcar
                        (lambda (x) (cons (nth 0 x) (nth 1 x)))
                        (org-roam-db-query
                         [:select [r:ref r:node_id]
                                  :from (as refs r)
                                  :join (as nodes n) :on (and (= level 0) (= n:id r:node_id))
                                  :where (= r:type "cite")])))
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

;; defination
;;;###autoload
(define-minor-mode org-roam-organize-mode
  "org-roam-organize mode"
  :lighter " Organize"
  ;; :group nil
  :global t
  :init-value nil)

;; hook
(add-hook 'org-roam-organize-mode-hook
          (lambda ()
            (when org-roam-organize-mode
              (let* ((root_dir
                      (when (boundp 'org-roam-organize-root-directory)
                        org-roam-organize-root-directory))
                     (check_result
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
                 ((not (or
                        org-roam-organize-allow-outside-root
                        (file-in-directory-p
                         (expand-file-name default-directory)
                         (expand-file-name root_dir))))
                  (setq org-roam-organize-mode nil)
                  (message "%s" (concat (format
                                         "[WARNING] Not startup Emacs under %s. "
                                         root_dir)
                                        "Org Roam Organize Mode setup failed. ")))
                 (t
                  (unless (featurep 'org) (require 'org))
                  (unless (featurep 'org-element) (require 'org-element))
                  (unless (featurep 'org-roam) (require 'org-roam))
                  (unless (featurep 'cl-lib) (require 'cl-lib))))))))

(provide 'org-roam-organize)
;;; org-roam-organize.el ends here
