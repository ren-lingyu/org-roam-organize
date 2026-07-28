;;; org-roam-organize-test.el --- Tests for org-roam-organize -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for registry configuration and compatibility behavior.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ox)
(require 'ox-ascii)
(require 'org-roam)
(require 'org-roam-organize)

(defun org-roam-organize-test--temporary-root ()
  "Return a temporary root directory with default registry directories."
  (let ((root (file-name-as-directory
               (make-temp-file "org-roam-organize-test-" t))))
    (dolist (dir '("moc" "fleeting" "literature" "permanent"))
      (make-directory (expand-file-name dir root) t))
    root))

(ert-deftest org-roam-organize-test-registry-defaults-resolve-title-and-path ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "permanent" :tag "zettel" :basic t :directory "permanent"))))
    (let ((record (cadr org-roam-organize-registry)))
      (should (equal (org-roam-organize--record-moc-title record)
                     "Permanent"))
      (should (equal (org-roam-organize--record-moc-path record)
                     "moc/permanent.org"))
      (should (equal (org-roam-organize--record-absolute-moc-path record)
                     (expand-file-name "moc/permanent.org" root))))))

(ert-deftest org-roam-organize-test-registry-rejects-unsafe-name ()
  (let ((org-roam-organize-registry
         '((:name "map node" :tag "map" :moc t :basic t :directory "moc"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":name safe string" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-paths-outside-root ()
  (let ((org-roam-organize-directory "/test/root/")
        (org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "escape" :tag "escape" :moc-path "../escape.org"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "inside root" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-improper-list-record ()
  (let ((org-roam-organize-registry
         (list (cons :name "maps"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "plist\\?" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-malformed-record-does-not-break-default-moc-path ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          (list '(:name "maps" :tag "map" :moc t :basic t :directory "moc")
                (cons :name "broken")
                '(:name "idea" :tag "idea"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "plist\\?" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-improper-top-level-list ()
  (let ((org-roam-organize-registry
         (cons '(:name "maps" :tag "map" :moc t :basic t :directory "moc")
               :invalid-tail)))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "proper list" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-requires-one-moc-record ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "other-maps" :tag "other-map" :moc t :basic t :directory "other-moc"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "Exactly one :moc t record" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-allows-zero-or-one-cite-record ()
  (let ((org-roam-organize-directory
         (org-roam-organize-test--temporary-root)))
    (let ((org-roam-organize-registry
           '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
             (:name "literature" :tag "ref" :basic t :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should (car result))))
    (let ((org-roam-organize-registry
           '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
             (:name "literature" :tag "ref" :cite t :basic t :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should (car result))))))

(ert-deftest org-roam-organize-test-registry-rejects-multiple-cite-records ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :cite t :basic t :directory "literature")
           (:name "papers" :tag "paper" :cite t :basic t :directory "papers"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "At most one :cite t record" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-invalid-cite-value ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :cite "yes" :basic t :directory "literature"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":cite boolean" (cdr result))))))

(ert-deftest org-roam-organize-test-create-directories-uses-basic-registry-directories ()
  (let* ((root (file-name-as-directory
                (make-temp-file "org-roam-organize-test-" t)))
         (org-roam-organize-directory root)
         (moc-directory (expand-file-name "moc" root))
         (permanent-directory (expand-file-name "permanent" root))
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "note" :tag "note")
            (:name "permanent" :tag "zettel" :basic t :directory "permanent"))))
    (should-not (file-exists-p moc-directory))
    (should-not (file-exists-p permanent-directory))
    (org-roam-organize-create-directories)
    (should (file-directory-p moc-directory))
    (should (file-directory-p permanent-directory))))

(ert-deftest org-roam-organize-test-record-moc-capture-template-uses-registry-path-and-head ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-moc-managed-tag-property "MANAGED_TAG")
         (org-roam-organize-moc-managed-node-count-property "NODE_COUNT")
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea"
             :tag "idea"
             :template ((keywords . ((author . nil)
                                      (date . nil)
                                      (description . nil)
                                      (filetags . ("idea")))))))))
    (let* ((record (cadr org-roam-organize-registry))
           (template (org-roam-organize--record-moc-capture-template record))
           (target (plist-get (nthcdr 4 template) :target)))
      (should (equal target
                     `(file+head
                       ,(expand-file-name "moc/idea.org" root)
                       ":PROPERTIES:\n:MANAGED_TAG: idea\n:NODE_COUNT:\n:END:\n#+TITLE: Idea\n#+AUTHOR:\n#+DATE:\n#+DESCRIPTION:\n#+FILETAGS: :idea:\n"))))))

(ert-deftest org-roam-organize-test-record-moc-head-formats-file-keywords ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea"
             :tag "idea"
             :template ((properties . ((roam_refs . "@${citar-key}")
                                        (custom_id . nil)))
                        (keywords . ((author . "Lingyu Ren")
                                     (email . "lingyu@example.org")
                                     (date . "<%Y>")
                                     (description . nil)
                                     (filetags . ("idea" "note"))
                                     (author . "John Doe")
                                     (language . "en"))))))))
    (should
     (equal (org-roam-organize--record-moc-head
             (cadr org-roam-organize-registry))
            (concat
             ":PROPERTIES:\n"
             ":MOC_MANAGED_TAG: idea\n"
             ":MOC_MANAGED_NODE_COUNT:\n"
             ":ROAM_REFS: @${citar-key}\n"
             ":CUSTOM_ID:\n"
             ":END:\n"
             "#+TITLE: Idea\n"
             "#+AUTHOR: Lingyu Ren\n"
             "#+EMAIL: lingyu@example.org\n"
             "#+DATE: <%Y>\n"
             "#+DESCRIPTION:\n"
             "#+FILETAGS: :idea:note:\n"
             "#+AUTHOR: John Doe\n"
             "#+LANGUAGE: en\n")))))

(ert-deftest org-roam-organize-test-record-node-head-formats-properties-and-keywords ()
  (let ((record '(:name "literature"
                  :tag "ref"
                  :directory "literature"
                  :template ((properties . ((roam_refs . "@${citar-key}")))
                             (keywords . ((author . "${citar-author}")
                                          (filetags . ("ref"))))))))
    (should
     (equal (org-roam-organize--record-node-head record)
            (concat
             ":PROPERTIES:\n"
             ":ROAM_REFS: @${citar-key}\n"
             ":END:\n"
             "#+TITLE: ${title}\n"
             "#+AUTHOR: ${citar-author}\n"
             "#+FILETAGS: :ref:\n")))))

(ert-deftest org-roam-organize-test-record-node-capture-template-preserves-dynamic-fields ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record '(:name "literature"
                   :tag "ref"
                   :directory "literature"
                   :template ((properties . ((roam_refs . "@${citar-key}")))
                              (keywords . ((author . "${citar-author}")
                                           (date . "%<%Y-%m-%d>")
                                           (filetags . ("ref")))))))
         (template (org-roam-organize--record-node-capture-template record))
         (target (plist-get (nthcdr 4 template) :target))
         (head (nth 2 target)))
    (should (equal (nth 1 target)
                   (expand-file-name "literature/${id}/${slug}.org" root)))
    (dolist (expected '(":ROAM_REFS: @${citar-key}"
                        "#+TITLE: ${title}"
                        "#+AUTHOR: ${citar-author}"
                        "#+DATE: %<%Y-%m-%d>"
                        "#+FILETAGS: :ref:"))
      (should (string-match-p (regexp-quote expected) head)))))

(ert-deftest org-roam-organize-test-record-node-capture-template-uses-path-template ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record '(:name "literature"
                   :tag "ref"
                   :directory "literature"
                   :template ((path . "notes/note-${slug}.org")
                              (keywords . ((filetags . ("ref")))))))
         (template (org-roam-organize--record-node-capture-template record))
         (target (plist-get (nthcdr 4 template) :target)))
    (should (equal (nth 1 target)
                   (expand-file-name
                    "literature/${id}/notes/note-${slug}.org"
                    root)))))

(ert-deftest org-roam-organize-test-file-head-formatters-preserve-capture-text ()
  (should (equal (org-roam-organize--file-head-entry-value
                  '(author . "${citar-author}"))
                 "${citar-author}"))
  (should (equal (org-roam-organize--file-head-entry-value
                  '(date . "%<%Y-%m-%d>"))
                 "%<%Y-%m-%d>"))
  (should (equal (org-roam-organize--file-head-entry-value
                  '(filetags . ("ref" "note")))
                 ":ref:note:")))

(ert-deftest org-roam-organize-test-capture-node-passes-title-info-and-template ()
  (let ((template '("n" "test node" plain "%?"
                    :target (file+head "/tmp/test.org" "#+TITLE: ${title}\n")
                    :unnarrowed t))
        captured)
    (cl-letf (((symbol-function 'org-roam-capture-)
               (lambda (&rest args)
                 (setq captured args))))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       '(:citar-author "Jane Doe" :citar-key "doe2026")))
    (should (equal (plist-get captured :keys) "n"))
    (should (equal (org-roam-node-title (plist-get captured :node))
                   "Dynamic Title"))
    (should (equal (plist-get captured :info)
                   '(:citar-author "Jane Doe" :citar-key "doe2026")))
    (should (equal (plist-get captured :templates)
                   (list template)))))

(ert-deftest org-roam-organize-test-capture-node-cleans-empty-directory-after-finalize ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name
           "literature/test-id/test-title.org"
           root))
         (target-directory (file-name-directory target-file))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t))
         (org-capture-after-finalize-hook nil))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook)))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat function &rest args)
                 (apply function args))))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       record)
      (should (file-directory-p target-directory))
      (should org-capture-after-finalize-hook)
      (run-hooks 'org-capture-after-finalize-hook)
      (should-not (file-exists-p target-directory))
      (should-not org-capture-after-finalize-hook))))

(ert-deftest org-roam-organize-test-capture-node-rejects-target-outside-bundle ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file (expand-file-name "literature/evil.org" root))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t)))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook))))
      (should-error
       (org-roam-organize--capture-node
        "Dynamic Title"
        template
        nil
        nil
        record)))))

(ert-deftest org-roam-organize-test-capture-node-rejects-non-org-target ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file (expand-file-name "literature/test-id/readme.txt" root))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t)))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook))))
      (should-error
       (org-roam-organize--capture-node
        "Dynamic Title"
        template
        nil
        nil
        record)))))

(ert-deftest org-roam-organize-test-capture-node-asks-before-deleting-nonempty-aborted-bundle ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name
           "literature/test-id/notes/test-title.org"
           root))
         (bundle-directory (expand-file-name "literature/test-id/" root))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook)))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat function &rest args)
                 (apply function args)))
              ((symbol-function 'yes-or-no-p)
               (lambda (&rest _args)
                 (setq asked t)
                 t)))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       record)
      (should (file-directory-p bundle-directory))
      (let ((org-note-abort t)
            (noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should asked)
      (should-not (file-exists-p bundle-directory)))))

(ert-deftest org-roam-organize-test-capture-node-keeps-nonempty-aborted-bundle-when-rejected ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name
           "literature/test-id/notes/test-title.org"
           root))
         (bundle-directory (expand-file-name "literature/test-id/" root))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook)))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat function &rest args)
                 (apply function args)))
              ((symbol-function 'yes-or-no-p)
               (lambda (&rest _args)
                 (setq asked t)
                 nil)))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       record)
      (should (file-directory-p bundle-directory))
      (let ((org-note-abort t)
            (noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should asked)
      (should (file-directory-p bundle-directory)))))

(ert-deftest org-roam-organize-test-capture-node-does-not-ask-after-successful-finalize ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name
           "literature/test-id/notes/test-title.org"
           root))
         (bundle-directory (expand-file-name "literature/test-id/" root))
         (record '(:name "literature" :tag "ref" :directory "literature"))
         (template `("n" "test node" plain "%?"
                     :target (file+head ,target-file "#+TITLE: ${title}\n")
                     :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function 'org-roam-organize--capture-target-file)
               (lambda ()
                 target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook)))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat function &rest args)
                 (apply function args)))
              ((symbol-function 'yes-or-no-p)
               (lambda (&rest _args)
                 (setq asked t)
                 t)))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       record)
      (should (file-directory-p bundle-directory))
      (let ((noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should-not asked)
      (should (file-directory-p bundle-directory)))))

(ert-deftest org-roam-organize-test-capture-template-dynamic-fields-expand ()
  (let* ((root (file-name-as-directory
                (make-temp-file "org-roam-organize-test-" t)))
         (org-roam-directory root)
         (org-roam-db-location (expand-file-name ".org-roam.db" root))
         (org-roam-organize-directory root)
         (org-id-locations-file (expand-file-name ".org-id-locations" root))
         (year (format-time-string "%Y"))
         (record '(:name "literature"
                   :tag "ref"
                   :directory "literature"
                   :template ((path . "${citar-key}/${slug}.org")
                              (properties . ((roam_refs . "@${citar-key}")))
                              (keywords . ((author . "${citar-author}")
                                           (date . "%<%Y>")
                                           (filetags . ("ref")))))))
         (template (org-roam-organize--record-node-capture-template record)))
    (org-roam-organize--capture-node
     "Dynamic Capture"
     template
     '(:citar-author "Jane Doe" :citar-key "doe2026")
     '(:immediate-finish t)
     record)
    (let* ((files (directory-files-recursively root "\\.org\\'"))
           (node-file (car files))
           (relative (and node-file (file-relative-name node-file root)))
           (content (and node-file
                         (with-temp-buffer
                           (insert-file-contents node-file)
                           (buffer-string)))))
      (should (= (length files) 1))
      (should (string-match-p
               "\\`literature/[[:alnum:]-]+/doe2026/dynamic_capture\\.org\\'"
               relative))
      (dolist (expected (list ":ROAM_REFS: @doe2026"
                              "#+TITLE: Dynamic Capture"
                              "#+AUTHOR: Jane Doe"
                              (format "#+DATE: %s" year)
                              "#+FILETAGS: :ref:"))
        (should (string-match-p (regexp-quote expected) content)))
      (should-not (string-match-p (regexp-quote "${citar-author}") content))
      (should-not (string-match-p (regexp-quote "%<%Y>") content)))))

(ert-deftest org-roam-organize-test-record-provider-defaults-when-missing-or-nil ()
  (let ((missing '(:name "idea" :tag "idea" :directory "fleeting"))
        (explicit-nil '(:name "idea" :tag "idea" :directory "fleeting" :provider nil)))
    (should (eq (org-roam-organize--record-provider missing)
                #'org-roam-organize--default-node-provider))
    (should (eq (org-roam-organize--record-provider explicit-nil)
                #'org-roam-organize--default-node-provider))))

(ert-deftest org-roam-organize-test-registry-rejects-invalid-provider ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "idea" :tag "idea" :directory "fleeting" :provider "invalid"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":provider function" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-flat-template-sections ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "idea"
            :tag "idea"
            :directory "fleeting"
            :template ((filetags . ("idea")))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":template section keys" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-invalid-path-template ()
  (let ((org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "idea"
            :tag "idea"
            :directory "fleeting"
            :template ((path . "/tmp/${slug}.org")
                       (keywords . ((filetags . ("idea")))))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":template path" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-moc-path-template ()
  (let ((org-roam-organize-registry
         '((:name "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template ((path . "${slug}.org"))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":moc t cannot use :template path" (cdr result))))))

(ert-deftest org-roam-organize-test-moc-capture-template-ignores-path-template ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "literature" :tag "ref")))
         (record '(:name "literature"
                   :tag "ref"
                   :template ((path . "ignored-${slug}.org")
                              (keywords . ((filetags . ("ref")))))))
         (template (org-roam-organize--record-moc-capture-template record))
         (target (plist-get (nthcdr 4 template) :target)))
    (should (equal (nth 1 target)
                   (expand-file-name "moc/literature.org" root)))))

(ert-deftest org-roam-organize-test-node-create-uses-default-provider ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record '(:name "idea" :tag "idea" :directory "fleeting"))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function 'org-roam-organize--default-node-provider)
               (lambda (_record)
                 '(:title "Default Title" :info (:author "John Doe"))))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args)
                 (setq captured args))))
      (org-roam-organize-node-create))
    (should (equal (nth 0 captured) "Default Title"))
    (should (equal (nth 2 captured) '(:author "John Doe")))
    (should (eq (nth 4 captured) record))))

(ert-deftest org-roam-organize-test-node-create-uses-custom-provider-request ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record '(:name "idea"
                   :tag "idea"
                   :directory "fleeting"
                   :provider org-roam-organize-test--custom-provider))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function 'org-roam-organize-test--custom-provider)
               (lambda (_record)
                 '(:title "Custom Title"
                   :info (:author "Jane Doe" :date "2026")
                   :path "/tmp/ignored.org")))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args)
                 (setq captured args))))
      (org-roam-organize-node-create))
    (let* ((template (nth 1 captured))
           (target (plist-get (nthcdr 4 template) :target)))
      (should (equal (nth 0 captured) "Custom Title"))
      (should (equal (nth 2 captured) '(:author "Jane Doe" :date "2026")))
      (should (eq (nth 4 captured) record))
      (should (equal target
                     `(file+head
                       ,(expand-file-name "fleeting/${id}/${slug}.org" root)
                       ,(org-roam-organize--record-node-head record)))))))

(ert-deftest org-roam-organize-test-node-create-cancels-when-provider-returns-nil ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record '(:name "idea"
                   :tag "idea"
                   :directory "fleeting"
                   :provider org-roam-organize-test--cancel-provider))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function 'org-roam-organize-test--cancel-provider)
               (lambda (_record) nil))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args)
                 (setq captured args))))
      (org-roam-organize-node-create))
    (should-not captured)))

(ert-deftest org-roam-organize-test-node-create-rejects-invalid-provider-request ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record '(:name "idea"
                   :tag "idea"
                   :directory "fleeting"
                   :provider org-roam-organize-test--invalid-request-provider))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function 'org-roam-organize-test--invalid-request-provider)
               (lambda (_record) '(:title "" :info (:author "Jane Doe"))))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args)
                 (setq captured args))))
      (org-roam-organize-node-create))
    (should-not captured)))

(ert-deftest org-roam-organize-test-moc-node-provider-uses-moc-title-and-tag-info ()
  (let ((record '(:name "idea"
                  :tag "idea"
                  :moc-title "Ideas")))
    (should (equal (org-roam-organize--moc-node-provider record)
                   '(:title "Ideas" :info (:moc_managed_tag "idea"))))))

(ert-deftest org-roam-organize-test-moc-node-provider-uses-derived-moc-title ()
  (let ((record '(:name "literature" :tag "ref")))
    (should (equal (org-roam-organize--moc-node-provider record)
                   '(:title "Literature" :info (:moc_managed_tag "ref"))))))

(ert-deftest org-roam-organize-test-moc-create-skips-existing-mocs ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (existing-path (expand-file-name "moc/maps.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea")))
         captures)
    (write-region "" nil existing-path)
    (cl-letf (((symbol-function 'org-roam-capture-)
               (lambda (&rest args)
                 (push args captures))))
      (org-roam-organize-moc-create))
    (should (= (length captures) 1))
    (let* ((args (car captures))
           (templates (plist-get args :templates))
           (template (car templates))
           (target (plist-get (nthcdr 4 template) :target)))
      (should (equal (plist-get args :keys) "m"))
      (should (equal (plist-get args :info) '(:moc_managed_tag "idea")))
      (should (equal (org-roam-node-title (plist-get args :node)) "Idea"))
      (should (equal target
                     `(file+head
                       ,(expand-file-name "moc/idea.org" root)
                       ,(org-roam-organize--record-moc-head
                         (cadr org-roam-organize-registry))))))))

(ert-deftest org-roam-organize-test-sync-id-link-keyword-entries-updates-inbox ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (path (expand-file-name "moc/maps.org" root))
         (nodes '((:id "node-a" :title "Title A")
                  (:id "node-b" :title "Title B"))))
    (write-region
     (concat
      "#+TITLE: Maps\n"
      "* Inbox\n"
      "#+ROAM_TEST: [[id:node-a][Old Title]]\n"
      "#+ROAM_TEST: [[id:node-a][Duplicate Old Title]]\n"
      "#+ROAM_TEST: [[id:removed][Removed Title]]\n"
      "#+ROAM_TEST: malformed\n"
      "** Child\n"
      "Child body\n"
      "* COMMENT Ignored\n"
      "#+ROAM_TEST: [[id:commented][Commented Title]]\n"
      "#+BEGIN_SRC org\n"
      "#+ROAM_TEST: [[id:source][Source Title]]\n"
      "#+END_SRC\n")
     nil path)
    (let ((result
           (org-roam-organize--sync-id-link-keyword-entries
            "ROAM_TEST"
            path
            nodes
            "Inbox")))
      (should (eq (plist-get result :status) 'ok))
      (should (equal (plist-get result :duplicates) '("node-a")))
      (should (equal (plist-get result :removed) '("removed")))
      (should (equal (plist-get result :malformed)
                     '("#+ROAM_TEST: malformed"))))
    (let ((content
           (with-temp-buffer
             (insert-file-contents path)
             (buffer-string))))
      (with-temp-buffer
        (insert content)
        (should (= (how-many
                    (regexp-quote "#+ROAM_TEST: [[id:node-a][Title A]]")
                    (point-min)
                    (point-max))
                   2))
        (should (= (how-many
                    (regexp-quote "#+ROAM_TEST: [[id:node-b][Title B]]")
                    (point-min)
                    (point-max))
                   1))
        (should (string-match-p
                 (regexp-quote "* Inbox\n#+ROAM_TEST: [[id:node-a][Title A]]")
                 content))
        (should (string-match-p
                 (regexp-quote "#+ROAM_TEST: [[id:node-b][Title B]]\n** Child")
                 content))
        (should-not (string-match-p "Removed Title" content))
        (should (string-match-p "COMMENT Ignored" content))
        (should (string-match-p "Commented Title" content))
        (should (string-match-p "Source Title" content))))))

(ert-deftest org-roam-organize-test-moc-sync-wrapper-preserves-delete-marker ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea" :inbox "Inbox")))
         (path (expand-file-name "moc/idea.org" root))
         (record '(:name "idea"
                   :tag "idea"
                   :inbox "Inbox"))
         (nodes '((:id "node-a" :title "Updated Title"))))
    (write-region
     (concat
      "#+TITLE: Idea\n"
      "* Inbox\n"
      "#+ROAM_NODE: [[id:node-a][Old Title]] :delete t\n")
     nil path)
    (let ((result (org-roam-organize--moc-sync-node-entries record nodes)))
      (should (eq (plist-get result :status) 'ok)))
    (with-temp-buffer
      (insert-file-contents path)
      (should (search-forward
               "#+ROAM_NODE: [[id:node-a][Updated Title]] :delete t"
               nil t)))))

(ert-deftest org-roam-organize-test-moc-sync-collects-failure-messages ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "idea" :tag "idea" :inbox "Inbox")))
        messages)
    (cl-letf (((symbol-function 'org-roam-db)
               (lambda () t))
              ((symbol-function 'org-roam-organize--nodes-with-tag)
               (lambda (_tag) nil))
              ((symbol-function 'org-roam-organize--moc-sync-node-entries)
               (lambda (&rest _args)
                 '(:status failed :reason "Missing MOC file")))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (org-roam-organize-moc-sync))
    (should (= (length messages) 1))
    (should (string-match-p
             "Sync MOCs: 0 synced, 1 failed"
             (car messages)))
    (should (string-match-p
             (regexp-quote org-roam-organize--report-buffer-name)
             (car messages)))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should (string-match-p "Cannot sync MOC for registry record"
                              (buffer-string)))
      (should (string-match-p
               "Sync MOCs: 0 synced, 1 failed"
               (buffer-string))))))

(ert-deftest org-roam-organize-test-cite-citing-node-data-deduplicates-by-reference-and-citing-node ()
  (let ((org-roam-organize-mode t)
        captured-query
        captured-args)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (query &rest args)
                 (setq captured-query query)
                 (setq captured-args args)
                 '(("ref-a" "key-a" "citing-a" "Citing A")
                   ("ref-a" "key-a" "citing-a" "Citing A")
                   ("ref-a" "key-a" "citing-b" "Citing B")
                   ("ref-b" "key-b" "citing-c" "Citing C")))))
      (let* ((result
              (org-roam-organize--cite-citing-node-data
               '("ref-a" "ref-b")))
             (alist (plist-get result :alist)))
        (should (vectorp captured-query))
        (should (equal (aref captured-query 7)
                       '(= r:node_id c:cite_key)))
        (should (equal captured-args
                       (list (vconcat '("ref-a" "ref-b")))))
        (should (equal (cdr (assoc "ref-a" alist))
                       '((:id "citing-a" :title "Citing A")
                         (:id "citing-b" :title "Citing B"))))
        (should (equal (cdr (assoc "ref-b" alist))
                       '((:id "citing-c" :title "Citing C"))))))))

(ert-deftest org-roam-organize-test-cite-reference-map-data-reports-missing-multiple-and-duplicate-citekeys ()
  (let (captured-query
        captured-args)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (query &rest args)
                 (setq captured-query query)
                 (setq captured-args args)
                 '(("ref-a" "key-a")
                   ("ref-b" "key-a")
                   ("ref-c" "key-c-1")
                   ("ref-c" "key-c-2")))))
      (let ((result
             (org-roam-organize--cite-reference-map-data
              '((:id "ref-a" :title "Ref A")
                (:id "ref-b" :title "Ref B")
                (:id "ref-c" :title "Ref C")
                (:id "ref-d" :title "Ref D")))))
        (should (vectorp captured-query))
        (should (equal captured-args
                       (list (vconcat '("ref-a" "ref-b" "ref-c" "ref-d")))))
        (should (equal (gethash "ref-a"
                                (plist-get result :uuid-to-citekey))
                       "key-a"))
        (should (equal (gethash "key-a"
                                (plist-get result :citekey-to-uuids))
                       '("ref-b" "ref-a")))
        (should (equal (plist-get result :missing)
                       '((:id "ref-d" :title "Ref D"))))
        (should (equal (plist-get result :multiple)
                       '((:id "ref-c"
                          :title "Ref C"
                          :refs ("key-c-1" "key-c-2")))))
        (should (equal (plist-get result :duplicate-citekeys)
                       '((:citekey "key-a"
                          :uuids ("ref-a" "ref-b")))))
        (should-not
         (org-roam-organize--cite-reference-refs-valid-p result))))))

(ert-deftest org-roam-organize-test-cite-sync-wrapper-uses-citing-node-keyword ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (path (expand-file-name "literature/ref.org" root))
         (record '(:name "literature"
                   :tag "ref"
                   :cite t
                   :inbox "Inbox"))
         (nodes '((:id "citing-a" :title "Citing A"))))
    (write-region "#+TITLE: Ref\n" nil path)
    (let ((result
           (org-roam-organize--cite-sync-citing-node-entries
            record
            path
            nodes)))
      (should (eq (plist-get result :status) 'ok)))
    (with-temp-buffer
      (insert-file-contents path)
      (should (search-forward "* Inbox" nil t))
      (should (search-forward
               "#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]"
               nil t)))))

(ert-deftest org-roam-organize-test-cite-sync-requires-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :basic t :directory "literature")))
        synced)
    (cl-letf (((symbol-function 'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (&rest _args)
                 (setq synced t))))
      (org-roam-organize-cite-sync))
    (should-not synced)))

(ert-deftest org-roam-organize-test-cite-check-requires-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :basic t :directory "literature")))
        checked)
    (cl-letf (((symbol-function 'org-roam-organize--cite-global-reference-map-data)
               (lambda ()
                 (setq checked t))))
      (org-roam-organize-cite-check))
    (should-not checked)))

(ert-deftest org-roam-organize-test-cite-check-reports-global-validation-result ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :cite t :basic t :directory "literature")))
        messages)
    (cl-letf (((symbol-function 'org-roam-db)
               (lambda () t))
              ((symbol-function 'org-roam-organize--cite-global-reference-map-data)
               (lambda ()
                 '(:nodes ((:id "ref-a" :title "Ref A")
                           (:id "ref-b" :title "Ref B"))
                   :missing ((:id "ref-a" :title "Ref A"))
                   :multiple nil
                   :duplicate-citekeys ((:citekey "key-a"
                                         :uuids ("ref-a" "ref-b"))))))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (org-roam-organize-cite-check))
    (should (= (length messages) 1))
    (should (seq-find
             (lambda (message)
               (string-match-p "Check cite references: 2 checked, 1 missing cite refs, 0 multiple cite refs, 1 duplicate cite keys, status failed"
                               message))
             messages))
    (should (seq-find
             (lambda (message)
               (string-match-p
                (regexp-quote org-roam-organize--report-buffer-name)
                message))
             messages))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should (string-match-p "External citekey belongs to multiple literature nodes"
                              (buffer-string)))
      (should (string-match-p
               "Check cite references: 2 checked, 1 missing cite refs"
               (buffer-string))))))

(ert-deftest org-roam-organize-test-cite-sync-syncs-all-cite-nodes ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (ref-b-file (expand-file-name "literature/ref-b.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature"
             :inbox "Inbox"))))
    (write-region "#+TITLE: Ref A\n" nil ref-a-file)
    (write-region
     (concat
      "#+TITLE: Ref B\n"
      "* Inbox\n"
      "#+ROAM_CITING_NODE: [[id:stale][Stale]]\n")
     nil ref-b-file)
    (cl-letf (((symbol-function 'org-roam-db)
               (lambda () t))
              ((symbol-function 'org-roam-organize--nodes-with-tag-and-file)
               (lambda (tag)
                 (should (equal tag "ref"))
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file)
                   (:id "ref-b" :title "Ref B" :file ,ref-b-file))))
              ((symbol-function 'org-roam-organize--cite-reference-map-data)
               (lambda (nodes)
                 (should (equal (mapcar (lambda (node)
                                          (plist-get node :id))
                                        nodes)
                                '("ref-a" "ref-b")))
                 '(:missing nil
                   :multiple nil
                   :duplicate-citekeys nil)))
              ((symbol-function 'org-roam-organize--cite-citing-node-data)
               (lambda (ids)
                 (should (equal ids '("ref-a" "ref-b")))
                 '(:alist (("ref-a" . ((:id "citing-a" :title "Citing A")))))))
              ((symbol-function 'org-roam-organize--cite-report-reference-map-data)
               (lambda (map-data)
                 (should (equal (plist-get map-data :missing) nil))
                 '(:valid-p t :lines nil)))
              ((symbol-function 'message)
               (lambda (&rest _args) nil)))
      (org-roam-organize-cite-sync))
    (with-temp-buffer
      (insert-file-contents ref-a-file)
      (should (search-forward
               "#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]"
               nil t)))
    (with-temp-buffer
      (insert-file-contents ref-b-file)
      (should-not (search-forward "Stale" nil t)))))

(ert-deftest org-roam-organize-test-cite-sync-stops-when-reference-ref-validation-fails ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature"
             :inbox "Inbox")))
         cite-data-called
         synced)
    (write-region "#+TITLE: Ref A\n" nil ref-a-file)
    (cl-letf (((symbol-function 'org-roam-db)
               (lambda () t))
              ((symbol-function 'org-roam-organize--nodes-with-tag-and-file)
               (lambda (_tag)
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file))))
              ((symbol-function 'org-roam-organize--cite-reference-map-data)
               (lambda (_nodes)
                 '(:missing ((:id "ref-a" :title "Ref A"))
                   :multiple nil
                   :duplicate-citekeys nil)))
              ((symbol-function 'org-roam-organize--cite-citing-node-data)
               (lambda (&rest _args)
                 (setq cite-data-called t)
                 nil))
              ((symbol-function 'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (&rest _args)
                 (setq synced t)
                 nil))
              ((symbol-function 'message)
               (lambda (&rest _args) nil)))
      (org-roam-organize-cite-sync))
    (should-not cite-data-called)
    (should-not synced)
    (with-temp-buffer
      (insert-file-contents ref-a-file)
      (should-not (search-forward org-roam-organize--cite-citing-node-keyword
                                  nil t)))))

(ert-deftest org-roam-organize-test-cite-sync-reports-duplicate-citekeys-without-blocking ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature"
             :inbox "Inbox")))
         synced
         messages)
    (write-region "#+TITLE: Ref A\n" nil ref-a-file)
    (cl-letf (((symbol-function 'org-roam-db)
               (lambda () t))
              ((symbol-function 'org-roam-organize--nodes-with-tag-and-file)
               (lambda (_tag)
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file))))
              ((symbol-function 'org-roam-organize--cite-reference-map-data)
               (lambda (_nodes)
                 '(:missing nil
                   :multiple nil
                   :duplicate-citekeys ((:citekey "key-a"
                                         :uuids ("ref-a" "ref-b"))))))
              ((symbol-function 'org-roam-organize--cite-citing-node-data)
               (lambda (_ids)
                 '(:alist (("ref-a" . ((:id "citing-a"
                                        :title "Citing A")))))))
              ((symbol-function 'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (_record _path nodes)
                 (setq synced nodes)
                 '(:status ok
                   :duplicates nil
                   :removed nil
                   :malformed nil)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (org-roam-organize-cite-sync))
    (should (equal synced '((:id "citing-a" :title "Citing A"))))
    (should (= (length messages) 1))
    (should (seq-find
             (lambda (message)
               (string-match-p
                (regexp-quote org-roam-organize--report-buffer-name)
                message))
             messages))
    (should (seq-find
             (lambda (message)
               (string-match-p "Sync citing-node entries: 1 synced, 0 failed"
                               message))
             messages))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should (string-match-p "External citekey belongs to multiple literature nodes"
                              (buffer-string)))
      (should (string-match-p "Sync citing-node entries: 1 synced, 0 failed"
                              (buffer-string))))))

(ert-deftest org-roam-organize-test-cite-export-filter-replaces-managed-uuid-citation-keys ()
  (let ((org-roam-organize-mode t))
    (cl-letf (((symbol-function
                'org-roam-organize--cite-export-reference-map-data-or-error)
               (lambda (keys)
                 (should (equal keys '("ref-a" "plain-key")))
                 (let ((uuid-to-citekey (make-hash-table :test 'equal)))
                   (puthash "ref-a" "key-a" uuid-to-citekey)
                   (list :uuid-to-citekey uuid-to-citekey)))))
      (with-temp-buffer
        (insert "[cite:@ref-a;@plain-key]")
        (org-mode)
        (let ((parse-tree (org-element-parse-buffer))
              keys)
          (org-roam-organize--cite-export-filter parse-tree nil nil)
          (org-element-map parse-tree 'citation-reference
            (lambda (reference)
              (push (org-element-property :key reference) keys)))
          (should (equal (nreverse keys)
                         '("key-a" "plain-key"))))))))

(ert-deftest org-roam-organize-test-cite-export-filter-runs-in-org-export-pipeline ()
  (let ((org-roam-organize-mode t)
        captured-keys)
    (cl-letf (((symbol-function
                'org-roam-organize--cite-export-reference-map-data-or-error)
               (lambda (keys)
                 (should (equal keys '("ref-a" "plain-key")))
                 (let ((uuid-to-citekey (make-hash-table :test 'equal)))
                   (puthash "ref-a" "key-a" uuid-to-citekey)
                   (list :uuid-to-citekey uuid-to-citekey)))))
      (with-temp-buffer
        (insert "[cite:@ref-a;@plain-key]")
        (org-mode)
        (let ((org-export-filter-parse-tree-functions
               (list
                #'org-roam-organize--cite-export-filter
                (lambda (parse-tree _backend _info)
                  (setq captured-keys nil)
                  (org-element-map parse-tree 'citation-reference
                    (lambda (reference)
                      (push (org-element-property :key reference)
                            captured-keys)))
                  parse-tree))))
          (org-export-as 'ascii nil nil t)
          (should (equal (nreverse captured-keys)
                         '("key-a" "plain-key"))))))))

(ert-deftest org-roam-organize-test-cite-export-filter-errors-on-invalid-managed-map ()
  (let ((org-roam-organize-mode t))
    (cl-letf (((symbol-function
                'org-roam-organize--cite-export-reference-map-data-or-error)
               (lambda (_keys)
                 (user-error "Cite reference validation failed"))))
      (with-temp-buffer
        (insert "[cite:@ref-a]")
        (org-mode)
        (should-error
         (org-roam-organize--cite-export-filter
          (org-element-parse-buffer)
          nil
          nil)
         :type 'user-error)))))

(ert-deftest org-roam-organize-test-cite-export-reference-map-data-validates-only-exported-managed-uuids ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
           (:name "literature" :tag "ref" :cite t :basic t :directory "literature")))
        selected-nodes)
    (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
               (lambda (tag)
                 (should (equal tag "ref"))
                 '((:id "ref-a" :title "Ref A")
                   (:id "ref-b" :title "Ref B"))))
              ((symbol-function 'org-roam-organize--cite-reference-map-data)
               (lambda (nodes)
                 (setq selected-nodes nodes)
                 (let ((uuid-to-citekey (make-hash-table :test 'equal)))
                   (puthash "ref-a" "key-a" uuid-to-citekey)
                   (list :missing nil
                         :multiple nil
                         :duplicate-citekeys nil
                         :uuid-to-citekey uuid-to-citekey)))))
      (let ((result
             (org-roam-organize--cite-export-reference-map-data-or-error
              '("ref-a" "plain-key"))))
        (should (equal selected-nodes
                       '((:id "ref-a" :title "Ref A"))))
        (should (equal (gethash "ref-a"
                                (plist-get result :uuid-to-citekey))
                       "key-a"))))))

(ert-deftest org-roam-organize-test-cite-export-reference-map-data-skips-registry-without-keys ()
  (let (registry-called)
    (cl-letf (((symbol-function 'org-roam-organize--registry-cite-records)
               (lambda ()
                 (setq registry-called t)
                 nil)))
      (let ((result
             (org-roam-organize--cite-export-reference-map-data-or-error
              nil)))
        (should-not registry-called)
        (should (hash-table-p (plist-get result :uuid-to-citekey)))))))

(ert-deftest org-roam-organize-test-count-nodes-with-given-tag-list-returns-ordered-alist ()
  (let ((org-roam-organize-mode t)
        captured-query
        captured-args)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (query &rest args)
                 (setq captured-query query)
                 (setq captured-args args)
                 '(("idea" 2)))))
      (let ((result
             (org-roam-organize--count-nodes-with-given-tag-list
              '("idea" "ref")
              t)))
        (should (vectorp captured-query))
        (should (equal captured-args
                       (list (vconcat '("idea" "ref")))))
        (should (equal result
                       '(("idea" . 2)
                         ("ref" . 0))))))))

(ert-deftest org-roam-organize-test-mode-does-not-register-raw-capture-template ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea")))
         (org-roam-capture-templates nil)
         (org-roam-organize-mode nil))
    (unwind-protect
        (progn
          (org-roam-organize-mode 1)
          (should org-roam-organize-mode)
          (should-not org-roam-capture-templates))
      (org-roam-organize-mode -1))))

(ert-deftest org-roam-organize-test-mode-registers-and-removes-cite-export-filter ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea")))
         (org-export-filter-parse-tree-functions nil)
         (org-roam-organize-mode nil))
    (unwind-protect
        (progn
          (org-roam-organize-mode 1)
          (should (memq #'org-roam-organize--cite-export-filter
                        org-export-filter-parse-tree-functions))
          (org-roam-organize-mode -1)
          (should-not (memq #'org-roam-organize--cite-export-filter
                            org-export-filter-parse-tree-functions)))
      (org-roam-organize-mode -1))))

(ert-deftest org-roam-organize-test-check-setup-combines-variable-registry-and-capability-checks ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea" :basic t :directory "fleeting")))
         (org-roam-organize-moc-managed-tag-property "MOC_MANAGED_TAG")
         (org-roam-organize-moc-managed-node-count-property "MOC_MANAGED_NODE_COUNT"))
    (let ((result (org-roam-organize--check-setup)))
      (should (car result))
      (should (string-match-p "Variable validation result: passed"
                              (cdr result)))
      (should (string-match-p "Root directory validation result: passed"
                              (cdr result)))
      (should (string-match-p "Registry validation result: passed"
                              (cdr result)))
      (should (string-match-p "Runtime capability validation result: passed"
                              (cdr result))))))

(ert-deftest org-roam-organize-test-check-setup-rejects-root-outside-org-roam-directory ()
  (let* ((roam-root (org-roam-organize-test--temporary-root))
         (root (org-roam-organize-test--temporary-root))
         (org-roam-directory roam-root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea" :basic t :directory "fleeting")))
         (org-roam-organize-moc-managed-tag-property "MOC_MANAGED_TAG")
         (org-roam-organize-moc-managed-node-count-property "MOC_MANAGED_NODE_COUNT"))
    (let ((result (org-roam-organize--check-setup)))
      (should-not (car result))
      (should (string-match-p "Root directory validation result: failed"
                              (cdr result)))
      (should (string-match-p "in org-roam-directory\\? nil"
                              (cdr result))))))

(ert-deftest org-roam-organize-test-check-setup-displays-report-on-failure ()
  (let* ((roam-root (org-roam-organize-test--temporary-root))
         (root (org-roam-organize-test--temporary-root))
         (org-roam-directory roam-root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea" :basic t :directory "fleeting")))
         (org-roam-organize-moc-managed-tag-property "MOC_MANAGED_TAG")
         (org-roam-organize-moc-managed-node-count-property "MOC_MANAGED_NODE_COUNT")
         messages
         displayed-buffer)
    (when-let ((buffer (get-buffer org-roam-organize--report-buffer-name)))
      (kill-buffer buffer))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages)))
              ((symbol-function 'display-buffer)
               (lambda (buffer &rest _args)
                 (setq displayed-buffer buffer))))
      (org-roam-organize-check-setup))
    (should (get-buffer org-roam-organize--report-buffer-name))
    (should (eq displayed-buffer
                (get-buffer org-roam-organize--report-buffer-name)))
    (should (= (length messages) 1))
    (should (string-match-p
             (regexp-quote org-roam-organize--report-buffer-name)
             (car messages)))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should (string-match-p "Root directory validation result: failed"
                              (buffer-string))))))

(ert-deftest org-roam-organize-test-check-setup-does-not-display-report-on-success ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "idea" :tag "idea" :basic t :directory "fleeting")))
         (org-roam-organize-moc-managed-tag-property "MOC_MANAGED_TAG")
         (org-roam-organize-moc-managed-node-count-property "MOC_MANAGED_NODE_COUNT")
         messages
         display-called)
    (when-let ((buffer (get-buffer org-roam-organize--report-buffer-name)))
      (kill-buffer buffer))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages)))
              ((symbol-function 'display-buffer)
               (lambda (&rest _args)
                 (setq display-called t))))
      (org-roam-organize-check-setup))
    (should-not display-called)
    (should-not (get-buffer org-roam-organize--report-buffer-name))
    (should (= (length messages) 1))
    (should (string-match-p "setup checks passed" (car messages)))))

(ert-deftest org-roam-organize-test-registry-tag-id-alist-reports-missing-records ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps" :tag "map" :moc t :basic t :directory "moc")
            (:name "missing" :tag "missing")))
         (queries nil))
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest args)
                 (push args queries)
                 (if (string= (cadr args)
                              (expand-file-name "moc/maps.org" root))
                     '(("map-id"))
                   nil))))
      (let ((result (org-roam-organize--registry-tag-id-alist)))
        (should (equal (car result) '(("map" . "map-id"))))
        (should (equal (cdr result)
                       '((:name "missing" :tag "missing"))))
        (should (= (length queries) 2))))))

(ert-deftest org-roam-organize-test-capability-check-reports-missing-capabilities ()
  (let ((result (org-roam-organize--check-capabilities
                 '((org-roam-organize-test--missing-function . function)
                   (org-roam-organize-test--missing-variable . variable)))))
    (should-not (car result))
    (should (string-match-p "org-roam-organize-test--missing-function"
                            (cdr result)))
    (should (string-match-p "org-roam-organize-test--missing-variable"
                            (cdr result)))))

(ert-deftest org-roam-organize-test-required-runtime-capabilities-exist ()
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize--capability-alist)))
    (ert-info ((cdr result))
      (should (car result)))))

(provide 'org-roam-organize-test)
;;; org-roam-organize-test.el ends here
