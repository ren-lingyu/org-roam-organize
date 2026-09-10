;;; org-roam-organize-core.el --- Shared core for Org-roam Organize -*- lexical-binding: t; package-lint-main-file: "org-roam-organize.el"; -*-

;;; Commentary:

;; This internal module defines shared configuration, registry, validation,
;; path, database-query, and reporting facilities.

;;; Code:

;; ==============================
;; 声明外部依赖
;; ==============================

(require 'cl-lib)
(require 'seq)
(require 'rx)
(require 'org)
(require 'oc)
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
`:moc', `:basic', `:cite', and `:bibliography' are optional booleans.  A
`:moc t' record must also be `:basic t'.  At most one record may use
`:cite t'; that record identifies literature nodes for citation export,
checking, and synchronization.  Citation database operations recognize
level-0 nodes carrying that record's `:tag'; a capture template that creates
citation nodes is responsible for including the tag in its `filetags' keyword.
Setting `:bibliography t' on the citation record exposes bibliography paths
declared by those nodes through Org Cite and enables managed BibLaTeX export
compatibility.  A missing or nil value leaves bibliography discovery and
export metadata to Org and user configuration.  Any record using
`:bibliography t' must also use `:cite t'.
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

;; ==============================
;; 常量定义
;; ==============================

(defconst org-roam-organize--bibliography-property "BIBLIOGRAPHY"
  "The Org property that names a citation node's bibliography file.

Its value is resolved relative to the Org file containing the managed
citation node.  Org-roam Organize treats the property as stored metadata and
does not insert it into capture templates or validate the referenced file.")

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
  "Core runtime capabilities required by Org-roam Organize.

The list maps symbols to capability types checked by
`org-roam-organize--check-capabilities'.")

(defconst org-roam-organize--bibliography-capability-alist
  '((org-cite-list-bibliography-files . function)
    (org-export-derived-backend-p . function)
    (org-export-filter-final-output-functions . variable))
  "Runtime capabilities required by managed bibliography integration.

The list is appended to `org-roam-organize--capability-alist' only when the
unique citation registry record sets `:bibliography t'.")

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

(defun org-roam-organize--record-bibliography-p (record)
  "Return non-nil if RECORD enables managed bibliography integration.

Implementation notes: Only literal `t' enables the integration.  Registry
validation separately requires the key to be boolean and limits an enabled
value to the unique `:cite t' record."
  (eq (plist-get record :bibliography) t))

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

(defun org-roam-organize--registry-cite-bibliography-p ()
  "Return non-nil when the citation record enables bibliography integration.

Return nil when no `:cite t' record exists or its `:bibliography' value is
missing or nil.  Registry validation guarantees at most one citation record
before mode setup calls this function.

Implementation notes: The citation record is selected with
`org-roam-organize--registry-cite-record' and tested through
`org-roam-organize--record-bibliography-p'.

Rationale: Bibliography source policy belongs to the unique managed citation
record rather than to the optional interactive backend."
  (when-let* ((record (org-roam-organize--registry-cite-record)))
    (org-roam-organize--record-bibliography-p record)))

(defun org-roam-organize--required-capabilities ()
  "Return runtime capabilities required by the current registry.

The result always includes `org-roam-organize--capability-alist'.  Append
`org-roam-organize--bibliography-capability-alist' only when the citation
record enables `:bibliography'.  The returned list may share cons cells with
the constants and must not be modified.

Rationale: An unused optional integration must not prevent the core mode from
starting on an Org version that lacks its interfaces."
  (append org-roam-organize--capability-alist
          (when (org-roam-organize--registry-cite-bibliography-p)
            org-roam-organize--bibliography-capability-alist)))

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
               (bibliography (when plistp
                               (plist-get record :bibliography)))
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
            (when (and bibliography (not (booleanp bibliography)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message
                            "  :bibliography boolean? nil (should be t)\n")))
            (when (org-roam-organize--record-moc-p record)
              (setq moc-count (1+ moc-count))
              (unless (org-roam-organize--record-basic-p record)
                (setq result_bool nil)
                (setq result_message
                      (concat result_message "  :moc t requires :basic t\n"))))
            (when (org-roam-organize--record-cite-p record)
              (setq cite-count (1+ cite-count)))
            (when (and (org-roam-organize--record-bibliography-p record)
                       (not (org-roam-organize--record-cite-p record)))
              (setq result_bool nil)
              (setq result_message
                    (concat result_message
                            "  :bibliography t requires :cite t\n")))
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
          (org-roam-organize--required-capabilities))))
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

(provide 'org-roam-organize-core)
;;; org-roam-organize-core.el ends here
