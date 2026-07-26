;;; org-roam-organize-test.el --- Tests for org-roam-organize -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for registry configuration and compatibility behavior.

;;; Code:

(require 'ert)
(require 'cl-lib)
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
             :template ((author . nil)
                        (date . nil)
                        (description . nil)
                        (filetags . ("idea")))))))
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
             :template ((author . "Lingyu Ren")
                        (email . "lingyu@example.org")
                        (date . "<%Y>")
                        (description . nil)
                        (filetags . ("idea" "note"))
                        (author . "John Doe")
                        (language . "en"))))))
    (should
     (equal (org-roam-organize--record-moc-head
             (cadr org-roam-organize-registry))
            (concat
             ":PROPERTIES:\n"
             ":MOC_MANAGED_TAG: idea\n"
             ":MOC_MANAGED_NODE_COUNT:\n"
             ":END:\n"
             "#+TITLE: Idea\n"
             "#+AUTHOR: Lingyu Ren\n"
             "#+EMAIL: lingyu@example.org\n"
             "#+DATE: <%Y>\n"
             "#+DESCRIPTION:\n"
             "#+FILETAGS: :idea:note:\n"
             "#+AUTHOR: John Doe\n"
             "#+LANGUAGE: en\n")))))

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
      (should (equal (org-roam-node-title (plist-get args :node)) "Idea"))
      (should (equal target
                     `(file+head
                       ,(expand-file-name "moc/idea.org" root)
                       ,(org-roam-organize--record-moc-head
                         (cadr org-roam-organize-registry))))))))

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

(provide 'org-roam-organize-test)
;;; org-roam-organize-test.el ends here
