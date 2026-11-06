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
  (let ((root
         (file-name-as-directory
          (make-temp-file "org-roam-organize-test-" t))))
    (dolist (dir '("moc" "fleeting" "literature" "permanent"))
      (make-directory (expand-file-name dir root) t))
    root))

(ert-deftest
    org-roam-organize-test-registry-defaults-resolve-title-and-path
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (moc
          '(:name "maps" :tag "map" :moc t :basic t :directory "moc"))
         (record '(:name "permanent" :tag "zettel")))
    (should
     (equal (org-roam-organize--record-moc-title record) "Permanent"))
    (should-not (org-roam-organize--record-moc-path record))
    (should
     (equal (org-roam-organize--record-moc-path moc) "moc/maps.org"))
    (should
     (equal
      (org-roam-organize--record-absolute-moc-path moc)
      (expand-file-name "moc/maps.org" root)))))

(ert-deftest
    org-roam-organize-test-registry-allows-shared-basic-directories
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "permanent"
             :tag "zettel"
             :basic t
             :directory "permanent")
            (:name
             "fleeting"
             :tag "idea"
             :basic t
             :directory "permanent/.")
            (:name "note" :tag "note" :directory "permanent"))))
    (should (car (org-roam-organize--validate-registry)))))

(ert-deftest org-roam-organize-test-registry-rejects-unsafe-name ()
  (let ((org-roam-organize-registry
         '((:name
            "map node"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":name safe string" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-paths-outside-root
    ()
  (let ((org-roam-organize-directory "/test/root/")
        (org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name "escape" :tag "escape" :moc-path "../escape.org"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "inside root" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-improper-list-record
    ()
  (let ((org-roam-organize-registry (list (cons :name "maps"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "plist\\?" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-malformed-record-does-not-break-default-moc-path
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          (list
           '(:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
           (cons :name "broken") '(:name "idea" :tag "idea"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "plist\\?" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-improper-top-level-list
    ()
  (let ((org-roam-organize-registry
         (cons
          '(:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
          :invalid-tail)))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p "proper list" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-requires-one-moc-record
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "other-maps"
            :tag "other_map"
            :moc t
            :basic t
            :directory "other-moc"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p "Exactly one :moc t record" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-allows-zero-or-one-cite-record
    ()
  (let ((org-roam-organize-directory
         (org-roam-organize-test--temporary-root)))
    (let ((org-roam-organize-registry
           '((:name
              "maps"
              :tag "map"
              :moc t
              :basic t
              :directory "moc"
              :template
              ((keywords . ((filetags . ("map"))))))
             (:name
              "literature"
              :tag "ref"
              :basic t
              :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should (car result))))
    (let ((org-roam-organize-registry
           '((:name
              "maps"
              :tag "map"
              :moc t
              :basic t
              :directory "moc"
              :template
              ((keywords . ((filetags . ("map"))))))
             (:name
              "literature"
              :tag "ref"
              :cite t
              :basic t
              :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should (car result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-multiple-cite-records
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite t
            :basic t
            :directory "literature")
           (:name
            "papers"
            :tag "paper"
            :cite t
            :basic t
            :directory "papers"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p "At most one :cite t record" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-invalid-cite-value
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite "yes"
            :basic t
            :directory "literature"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":cite boolean" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-allows-optional-bibliography
    ()
  (let ((org-roam-organize-directory
         (org-roam-organize-test--temporary-root)))
    (dolist (bibliography '(nil t))
      (let ((org-roam-organize-registry
             `((:name
                "maps"
                :tag "map"
                :moc t
                :basic t
                :directory "moc"
                :template
                ((keywords . ((filetags . ("map"))))))
               (:name
                "literature"
                :tag "ref"
                :cite t
                :bibliography ,bibliography
                :basic t
                :directory "literature"))))
        (should (car (org-roam-organize--validate-registry)))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-invalid-bibliography
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite t
            :bibliography "yes"
            :basic t
            :directory "literature"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p (rx ":bibliography boolean") (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-requires-cite-for-bibliography
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :bibliography t
            :basic t
            :directory "literature"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p
        (rx ":bibliography t requires :cite t") (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-allows-optional-cite-backend
    ()
  (let ((org-roam-organize-directory
         (org-roam-organize-test--temporary-root)))
    (dolist (backend
             '(nil
               citar
               (citar
                :title "${title}"
                :info (:key "${=key=}"))
               unsupported (unsupported :option t)))
      (let ((org-roam-organize-registry
             `((:name
                "maps"
                :tag "map"
                :moc t
                :basic t
                :directory "moc"
                :template
                ((keywords . ((filetags . ("map"))))))
               (:name
                "literature"
                :tag "ref"
                :cite t
                :backend ,backend
                :basic t
                :directory "literature"))))
        (should (car (org-roam-organize--validate-registry)))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-citar-backend-without-cite
    ()
  (dolist (backend '(citar (citar :title "${title}")))
    (let ((org-roam-organize-registry
           `((:name
              "maps"
              :tag "map"
              :moc t
              :basic t
              :directory "moc"
              :template
              ((keywords . ((filetags . ("map"))))))
             (:name
              "literature"
              :tag "ref"
              :backend ,backend
              :basic t
              :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should-not (car result))
        (should
         (string-match-p
          (rx ":backend citar requires :cite t") (cdr result)))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-malformed-tagged-backend
    ()
  (dolist (backend
           '((citar :title)
             (citar . :title)
             ("citar" :title "${title}")))
    (let ((org-roam-organize-registry
           `((:name
              "literature"
              :tag "ref"
              :cite t
              :backend ,backend
              :basic t
              :directory "literature"))))
      (let ((result (org-roam-organize--validate-registry)))
        (should-not (car result))
        (should
         (string-match-p
          (rx "tagged :backend must be (BACKEND OPTION VALUE...)")
          (cdr result)))))))

(ert-deftest org-roam-organize-test-record-backend-accessors ()
  (let ((record
         '(:name
           "literature"
           :backend
           (citar :title "${title}" :info (:key "${=key=}")))))
    (should
     (equal
      (org-roam-organize--record-backend-specification record)
      '(citar :title "${title}" :info (:key "${=key=}"))))
    (should (eq (org-roam-organize--record-backend record) 'citar))
    (should
     (equal
      (org-roam-organize--record-backend-options record)
      '(:title "${title}" :info (:key "${=key=}")))))
  (let ((record '(:name "literature" :backend citar)))
    (should (eq (org-roam-organize--record-backend record) 'citar))
    (should-not (org-roam-organize--record-backend-options record))))

(ert-deftest org-roam-organize-test-record-bibliography-accessors ()
  (should
   (org-roam-organize--record-bibliography-p
    '(:name "literature" :bibliography t)))
  (should-not
   (org-roam-organize--record-bibliography-p '(:name "literature")))
  (let ((org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t :bibliography t))))
    (should (org-roam-organize--registry-cite-bibliography-p))))

(ert-deftest
    org-roam-organize-test-registry-cite-backend-reads-cite-record
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite t
            :backend citar
            :basic t
            :directory "literature"))))
    (should (eq (org-roam-organize--registry-cite-backend) 'citar))))

(ert-deftest
    org-roam-organize-test-registry-cite-backend-normalizes-tagged-record
    ()
  (let ((org-roam-organize-registry
         '((:name
            "literature"
            :tag "ref"
            :cite t
            :backend (citar :title "${title}")
            :basic t
            :directory "literature"))))
    (should (eq (org-roam-organize--registry-cite-backend) 'citar))))

(ert-deftest
    org-roam-organize-test-queries-bibliography-files-from-properties
    ()
  (let ((org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t :bibliography t)))
        query-arguments)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (_query &rest arguments)
                 (setq query-arguments arguments)
                 '(("/notes/b.org" (("BIBLIOGRAPHY" . "z.bib")))
                   ("/notes/a.org" (("BIBLIOGRAPHY" . "a.bib")))
                   ("/notes/duplicate.org"
                    (("BIBLIOGRAPHY" . "a.bib")))
                   ("/notes/missing.org" (("ID" . "ignored")))))))
      (should
       (equal
        (org-roam-organize--bibliography-files)
        '("/notes/a.bib" "/notes/z.bib")))
      (should (equal query-arguments (list "ref"))))))

(ert-deftest
    org-roam-organize-test-bibliography-files-require-enabled-cite-record
    ()
  (let ((org-roam-organize-registry nil))
    (should-not (org-roam-organize--bibliography-files)))
  (let ((org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t)))
        query-called)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) (setq query-called t))))
      (should-not (org-roam-organize--bibliography-files))
      (should-not query-called))))

(ert-deftest
    org-roam-organize-test-filter-bibliography-files-appends-managed-files
    ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t :bibliography t))))
    (cl-letf (((symbol-function
                'org-roam-organize--bibliography-files)
               (lambda ()
                 '("/managed/shared.bib" "/managed/new.bib"))))
      (with-temp-buffer
        (org-mode)
        (should
         (equal
          (org-roam-organize--filter-bibliography-files
           '("/org/local.bib" "/managed/shared.bib"))
          '("/org/local.bib"
            "/managed/shared.bib"
            "/managed/new.bib")))))))

(ert-deftest
    org-roam-organize-test-filter-bibliography-files-obeys-mode-and-buffer
    ()
  (let ((files '("/org/local.bib"))
        query-called)
    (cl-letf (((symbol-function
                'org-roam-organize--bibliography-files)
               (lambda ()
                 (setq query-called t)
                 '("/managed/reference.bib"))))
      (with-temp-buffer
        (org-mode)
        (let ((org-roam-organize-mode nil))
          (should
           (eq
            (org-roam-organize--filter-bibliography-files
             files)
            files)))
        (fundamental-mode)
        (let ((org-roam-organize-mode t))
          (should
           (eq
            (org-roam-organize--filter-bibliography-files
             files)
            files)))))
    (should-not query-called)))

(ert-deftest
    org-roam-organize-test-org-cite-lists-enabled-bibliographies-without-backend
    ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t :bibliography t)))
        (org-cite-global-bibliography nil))
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (_query &rest _arguments)
                 '(("/managed/node.org"
                    (("BIBLIOGRAPHY" . "reference.bib")))))))
      (unwind-protect
          (progn
            (org-roam-organize--setup-cite-integration)
            (with-temp-buffer
              (org-mode)
              (should
               (equal
                (org-cite-list-bibliography-files)
                '("/managed/reference.bib")))))
        (org-roam-organize--teardown-cite-integration)))))

(ert-deftest
    org-roam-organize-test-setup-ignores-unsupported-cite-backend
    ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize--active-cite-backend nil)
        messages)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments)
                       messages))))
      (should-not
       (org-roam-organize--setup-cite-backend 'unsupported)))
    (should-not org-roam-organize--active-cite-backend)
    (should
     (seq-some
      (lambda (message-text)
        (string-match-p
         (rx
          "Citation backend is not supported and was ignored: unsupported")
         message-text))
      messages))))

(ert-deftest
    org-roam-organize-test-create-directories-uses-basic-registry-directories
    ()
  (let* ((root
          (file-name-as-directory
           (make-temp-file "org-roam-organize-test-" t)))
         (org-roam-organize-directory root)
         (moc-directory (expand-file-name "moc" root))
         (permanent-directory (expand-file-name "permanent" root))
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name "note" :tag "note")
            (:name
             "permanent"
             :tag "zettel"
             :basic t
             :directory "permanent")
            (:name
             "fleeting"
             :tag "idea"
             :basic t
             :directory "permanent"))))
    (should-not (file-exists-p moc-directory))
    (should-not (file-exists-p permanent-directory))
    (org-roam-organize-create-directories)
    (should (file-directory-p moc-directory))
    (should (file-directory-p permanent-directory))))

(ert-deftest
    org-roam-organize-test-record-moc-capture-template-uses-registry-path-and-head
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record
          '(:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :moc-title "Navigation"
            :moc-path "moc/index.org"
            :template
            ((keywords
              .
              ((author . "Map Author") (filetags . ("map")))))))
         (template
          (org-roam-organize--record-moc-capture-template record)))
    (should
     (equal
      (plist-get (nthcdr 4 template) :target)
      `(file+head
        ,(expand-file-name "moc/index.org" root)
        "#+TITLE: Navigation\n#+AUTHOR: Map Author\n#+FILETAGS: :map:\n")))))

(ert-deftest
    org-roam-organize-test-record-moc-head-formats-file-keywords
    ()
  (let ((record
         '(:name
           "maps"
           :tag "map"
           :moc t
           :template
           ((properties
             .
             ((moc_role . "navigation") (custom_id . nil)))
            (keywords
             .
             ((author . "Map Author")
              (email . "moc@example.org")
              (date . "<%Y>")
              (description . nil)
              (filetags . ("map" "navigation"))
              (author . "Second Map Author")
              (language . "en")))))))
    (should
     (equal
      (org-roam-organize--record-moc-head record)
      (concat
       ":PROPERTIES:\n:MOC_ROLE: navigation\n:CUSTOM_ID:\n:END:\n"
       "#+TITLE: Maps\n#+AUTHOR: Map Author\n#+EMAIL: moc@example.org\n"
       "#+DATE: <%Y>\n#+DESCRIPTION:\n#+FILETAGS: :map:navigation:\n"
       "#+AUTHOR: Second Map Author\n#+LANGUAGE: en\n")))))

(ert-deftest
    org-roam-organize-test-record-moc-template-does-not-fall-back-to-managed-record
    ()
  (let ((record
         '(:name
           "idea"
           :tag "idea"
           :template
           ((properties . ((roam_refs . "@idea-key")))
            (keywords . ((filetags . ("idea"))))))))
    (should-not (org-roam-organize--record-moc-head record))
    (should-not
     (org-roam-organize--record-moc-capture-template record))))

(ert-deftest
    org-roam-organize-test-record-node-head-formats-properties-and-keywords
    ()
  (let ((record
         '(:name
           "literature"
           :tag "ref"
           :directory "literature"
           :template
           ((properties . ((roam_refs . "@${citar-key}")))
            (keywords
             .
             ((author . "${citar-author}") (filetags . ("ref"))))))))
    (should
     (equal
      (org-roam-organize--record-node-head record)
      (concat
       ":PROPERTIES:\n"
       ":ROAM_REFS: @${citar-key}\n"
       ":END:\n"
       "#+TITLE: ${title}\n"
       "#+AUTHOR: ${citar-author}\n"
       "#+FILETAGS: :ref:\n")))))

(ert-deftest
    org-roam-organize-test-record-node-capture-template-preserves-dynamic-fields
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record
          '(:name
            "literature"
            :tag "ref"
            :directory "literature"
            :template
            ((properties . ((roam_refs . "@${citar-key}")))
             (keywords
              .
              ((author . "${citar-author}")
               (date . "%<%Y-%m-%d>")
               (filetags . ("ref")))))))
         (template
          (org-roam-organize--record-node-capture-template record))
         (target (plist-get (nthcdr 4 template) :target))
         (head (nth 2 target)))
    (should
     (equal
      (nth 1 target)
      (expand-file-name "literature/${id}/${slug}.org" root)))
    (dolist (expected
             '(":ROAM_REFS: @${citar-key}"
               "#+TITLE: ${title}"
               "#+AUTHOR: ${citar-author}"
               "#+DATE: %<%Y-%m-%d>"
               "#+FILETAGS: :ref:"))
      (should (string-match-p (regexp-quote expected) head)))))

(ert-deftest
    org-roam-organize-test-record-node-capture-template-uses-path-template
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record
          '(:name
            "literature"
            :tag "ref"
            :directory "literature"
            :template
            ((path . "notes/note-${slug}.org")
             (keywords . ((filetags . ("ref")))))))
         (template
          (org-roam-organize--record-node-capture-template record))
         (target (plist-get (nthcdr 4 template) :target)))
    (should
     (equal
      (nth 1 target)
      (expand-file-name "literature/${id}/notes/note-${slug}.org"
                        root)))))

(ert-deftest
    org-roam-organize-test-file-head-formatters-preserve-capture-text
    ()
  (should
   (equal
    (org-roam-organize--file-head-entry-value
     '(author . "${citar-author}"))
    "${citar-author}"))
  (should
   (equal
    (org-roam-organize--file-head-entry-value
     '(date . "%<%Y-%m-%d>"))
    "%<%Y-%m-%d>"))
  (should
   (equal
    (org-roam-organize--file-head-entry-value
     '(filetags . ("ref" "note")))
    ":ref:note:")))

(ert-deftest
    org-roam-organize-test-capture-node-passes-title-info-and-template
    ()
  (let ((template
         '("n"
           "test node"
           plain
           "%?"
           :target (file+head "/tmp/test.org" "#+TITLE: ${title}\n")
           :unnarrowed t))
        captured)
    (cl-letf (((symbol-function 'org-roam-capture-)
               (lambda (&rest args) (setq captured args))))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       '(:citar-author "Jane Doe" :citar-key "doe2026")))
    (should (equal (plist-get captured :keys) "n"))
    (should
     (equal
      (org-roam-node-title (plist-get captured :node))
      "Dynamic Title"))
    (should
     (equal
      (plist-get captured :info)
      '(:citar-author "Jane Doe" :citar-key "doe2026")))
    (should (equal (plist-get captured :templates) (list template)))))

(ert-deftest
    org-roam-organize-test-capture-node-runs-success-callback-after-finalize
    ()
  (let ((template
         '("n"
           "test node"
           plain
           "%?"
           :target (file+head "/tmp/test.org" "#+TITLE: ${title}\n")
           :unnarrowed t))
        (org-capture-after-finalize-hook nil)
        (call-count 0))
    (cl-letf (((symbol-function 'org-roam-capture-)
               (lambda (&rest _args))))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       nil
       (lambda () (setq call-count (1+ call-count))))
      (should (= call-count 0))
      (should org-capture-after-finalize-hook)
      (run-hooks 'org-capture-after-finalize-hook)
      (should (= call-count 1))
      (should-not org-capture-after-finalize-hook))))

(ert-deftest
    org-roam-organize-test-capture-node-skips-success-callback-after-abort
    ()
  (let ((template
         '("n"
           "test node"
           plain
           "%?"
           :target (file+head "/tmp/test.org" "#+TITLE: ${title}\n")
           :unnarrowed t))
        (org-capture-after-finalize-hook nil)
        called)
    (cl-letf (((symbol-function 'org-roam-capture-)
               (lambda (&rest _args))))
      (org-roam-organize--capture-node
       "Dynamic Title"
       template
       nil
       nil
       nil
       (lambda () (setq called t)))
      (let ((org-note-abort t))
        (run-hooks 'org-capture-after-finalize-hook))
      (should-not called)
      (should-not org-capture-after-finalize-hook))))

(ert-deftest
    org-roam-organize-test-capture-node-cleans-up-after-success-callback-error
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/test-title.org" root))
         (target-directory (file-name-directory target-file))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t))
         (org-capture-after-finalize-hook nil))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
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
       record
       (lambda () (error "Callback failed")))
      (should (file-directory-p target-directory))
      (should-error (run-hooks 'org-capture-after-finalize-hook))
      (should-not (file-exists-p target-directory))
      (should-not org-capture-after-finalize-hook))))

(ert-deftest
    org-roam-organize-test-capture-node-cleans-empty-directory-after-finalize
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/test-title.org" root))
         (target-directory (file-name-directory target-file))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t))
         (org-capture-after-finalize-hook nil))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook)))
              ((symbol-function 'run-at-time)
               (lambda (_secs _repeat function &rest args)
                 (apply function args))))
      (org-roam-organize--capture-node
       "Dynamic Title" template nil nil record)
      (should (file-directory-p target-directory))
      (should org-capture-after-finalize-hook)
      (run-hooks 'org-capture-after-finalize-hook)
      (should-not (file-exists-p target-directory))
      (should-not org-capture-after-finalize-hook))))

(ert-deftest
    org-roam-organize-test-capture-node-rejects-target-outside-bundle
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file (expand-file-name "literature/evil.org" root))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t)))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook))))
      (should-error
       (org-roam-organize--capture-node
        "Dynamic Title" template nil nil record)))))

(ert-deftest
    org-roam-organize-test-capture-node-rejects-non-org-target
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/readme.txt" root))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t)))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest _args)
                 (run-hooks 'org-roam-capture-preface-hook))))
      (should-error
       (org-roam-organize--capture-node
        "Dynamic Title" template nil nil record)))))

(ert-deftest
    org-roam-organize-test-capture-node-asks-before-deleting-nonempty-aborted-bundle
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/notes/test-title.org"
                            root))
         (bundle-directory
          (expand-file-name "literature/test-id/" root))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
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
       "Dynamic Title" template nil nil record)
      (should (file-directory-p bundle-directory))
      (let ((org-note-abort t)
            (noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should asked)
      (should-not (file-exists-p bundle-directory)))))

(ert-deftest
    org-roam-organize-test-capture-node-keeps-nonempty-aborted-bundle-when-rejected
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/notes/test-title.org"
                            root))
         (bundle-directory
          (expand-file-name "literature/test-id/" root))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
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
       "Dynamic Title" template nil nil record)
      (should (file-directory-p bundle-directory))
      (let ((org-note-abort t)
            (noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should asked)
      (should (file-directory-p bundle-directory)))))

(ert-deftest
    org-roam-organize-test-capture-node-does-not-ask-after-successful-finalize
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (target-file
          (expand-file-name "literature/test-id/notes/test-title.org"
                            root))
         (bundle-directory
          (expand-file-name "literature/test-id/" root))
         (record
          '(:name "literature" :tag "ref" :directory "literature"))
         (template
          `("n"
            "test node"
            plain
            "%?"
            :target (file+head ,target-file "#+TITLE: ${title}\n")
            :unnarrowed t))
         (org-capture-after-finalize-hook nil)
         (asked nil))
    (cl-letf (((symbol-function
                'org-roam-organize--capture-target-file)
               (lambda () target-file))
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
       "Dynamic Title" template nil nil record)
      (should (file-directory-p bundle-directory))
      (let ((noninteractive nil))
        (run-hooks 'org-capture-after-finalize-hook))
      (should-not asked)
      (should (file-directory-p bundle-directory)))))

(ert-deftest
    org-roam-organize-test-capture-template-dynamic-fields-expand
    ()
  (let* ((root
          (file-name-as-directory
           (make-temp-file "org-roam-organize-test-" t)))
         (org-roam-directory root)
         (org-roam-db-location (expand-file-name ".org-roam.db" root))
         (org-roam-organize-directory root)
         (org-id-locations-file
          (expand-file-name ".org-id-locations" root))
         (year (format-time-string "%Y"))
         (record
          '(:name
            "literature"
            :tag "ref"
            :directory "literature"
            :template
            ((path . "${citar-key}/${slug}.org")
             (properties . ((roam_refs . "@${citar-key}")))
             (keywords
              .
              ((author . "${citar-author}")
               (date . "%<%Y>")
               (filetags . ("ref")))))))
         (template
          (org-roam-organize--record-node-capture-template record)))
    (org-roam-organize--capture-node
     "Dynamic Capture"
     template
     '(:citar-author "Jane Doe" :citar-key "doe2026")
     '(:immediate-finish t)
     record)
    (let* ((files (directory-files-recursively root "\\.org\\'"))
           (node-file (car files))
           (relative
            (and node-file (file-relative-name node-file root)))
           (content
            (and node-file
                 (with-temp-buffer
                   (insert-file-contents node-file)
                   (buffer-string)))))
      (should (= (length files) 1))
      (should
       (string-match-p
        "\\`literature/[[:alnum:]-]+/doe2026/dynamic_capture\\.org\\'"
        relative))
      (dolist (expected
               (list
                ":ROAM_REFS: @doe2026"
                "#+TITLE: Dynamic Capture"
                "#+AUTHOR: Jane Doe"
                (format "#+DATE: %s" year)
                "#+FILETAGS: :ref:"))
        (should (string-match-p (regexp-quote expected) content)))
      (should-not
       (string-match-p (regexp-quote "${citar-author}") content))
      (should-not (string-match-p (regexp-quote "%<%Y>") content)))))

(ert-deftest
    org-roam-organize-test-record-provider-defaults-when-missing-or-nil
    ()
  (let ((missing '(:name "idea" :tag "idea" :directory "fleeting"))
        (explicit-nil
         '(:name
           "idea"
           :tag "idea"
           :directory "fleeting"
           :provider nil)))
    (should
     (eq
      (org-roam-organize--record-provider missing)
      #'org-roam-organize--default-node-provider))
    (should
     (eq
      (org-roam-organize--record-provider explicit-nil)
      #'org-roam-organize--default-node-provider))))

(ert-deftest org-roam-organize-test-registry-rejects-invalid-provider
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "idea"
            :tag "idea"
            :directory "fleeting"
            :provider "invalid"))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":provider function" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-flat-template-sections
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "idea"
            :tag "idea"
            :directory "fleeting"
            :template
            ((filetags . ("idea")))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p ":template section keys" (cdr result))))))

(ert-deftest
    org-roam-organize-test-registry-rejects-invalid-path-template
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "idea"
            :tag "idea"
            :directory "fleeting"
            :template
            ((path . "/tmp/${slug}.org")
             (keywords . ((filetags . ("idea")))))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should (string-match-p ":template path" (cdr result))))))

(ert-deftest org-roam-organize-test-registry-rejects-moc-path-template
    ()
  (let ((org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((path . "${slug}.org"))))))
    (let ((result (org-roam-organize--validate-registry)))
      (should-not (car result))
      (should
       (string-match-p
        ":moc t cannot use :template path" (cdr result))))))

(ert-deftest
    org-roam-organize-test-moc-capture-template-ignores-path-template
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-directory root)
         (record
          '(:name
            "maps"
            :tag "map"
            :moc t
            :directory "moc"
            :template
            ((path . "ignored-${slug}.org")
             (keywords . ((filetags . ("map")))))))
         (template
          (org-roam-organize--record-moc-capture-template record)))
    (should
     (equal
      (nth 1 (plist-get (nthcdr 4 template) :target))
      (expand-file-name "moc/maps.org" root)))))

(ert-deftest org-roam-organize-test-node-create-uses-default-provider
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record '(:name "idea" :tag "idea" :directory "fleeting"))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function
                'org-roam-organize--default-node-provider)
               (lambda (_record)
                 '(:title
                   "Default Title"
                   :info (:author "John Doe"))))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args) (setq captured args))))
      (org-roam-organize-node-create))
    (should (equal (nth 0 captured) "Default Title"))
    (should (equal (nth 2 captured) '(:author "John Doe")))
    (should (eq (nth 4 captured) record))))

(ert-deftest
    org-roam-organize-test-node-create-uses-custom-provider-request
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record
          '(:name
            "idea"
            :tag "idea"
            :directory "fleeting"
            :provider org-roam-organize-test--custom-provider))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function
                'org-roam-organize-test--custom-provider)
               (lambda (_record)
                 '(:title
                   "Custom Title"
                   :info (:author "Jane Doe" :date "2026")
                   :path "/tmp/ignored.org")))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args) (setq captured args))))
      (org-roam-organize-node-create))
    (let* ((template (nth 1 captured))
           (target (plist-get (nthcdr 4 template) :target)))
      (should (equal (nth 0 captured) "Custom Title"))
      (should
       (equal (nth 2 captured) '(:author "Jane Doe" :date "2026")))
      (should (eq (nth 4 captured) record))
      (should
       (equal
        target
        `(file+head
          ,(expand-file-name "fleeting/${id}/${slug}.org" root)
          ,(org-roam-organize--record-node-head record)))))))

(ert-deftest
    org-roam-organize-test-node-create-cancels-when-provider-returns-nil
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (record
          '(:name
            "idea"
            :tag "idea"
            :directory "fleeting"
            :provider org-roam-organize-test--cancel-provider))
         captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function
                'org-roam-organize-test--cancel-provider)
               (lambda (_record) nil))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args) (setq captured args))))
      (org-roam-organize-node-create))
    (should-not captured)))

(ert-deftest
    org-roam-organize-test-node-create-rejects-invalid-provider-request
    ()
  (let*
      ((root (org-roam-organize-test--temporary-root))
       (org-roam-organize-mode t)
       (org-roam-organize-directory root)
       (record
        '(:name
          "idea"
          :tag "idea"
          :directory "fleeting"
          :provider org-roam-organize-test--invalid-request-provider))
       captured)
    (cl-letf (((symbol-function 'org-roam-organize--read-node-record)
               (lambda () record))
              ((symbol-function
                'org-roam-organize-test--invalid-request-provider)
               (lambda (_record)
                 '(:title "" :info (:author "Jane Doe"))))
              ((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest args) (setq captured args))))
      (org-roam-organize-node-create))
    (should-not captured)))

(ert-deftest org-roam-organize-test-moc-node-provider-uses-file-title
    ()
  (should
   (equal
    (org-roam-organize--moc-node-provider
     '(:name "maps" :tag "map" :moc t :moc-title "Navigation"))
    '(:title "Navigation"))))

(ert-deftest
    org-roam-organize-test-moc-node-provider-uses-derived-moc-title
    ()
  (should
   (equal
    (org-roam-organize--moc-node-provider
     '(:name "maps" :tag "map" :moc t))
    '(:title "Maps"))))


(ert-deftest
    org-roam-organize-test-parse-id-link-keyword-entries-in-tree-is-scoped
    ()
  (with-temp-buffer
    (org-mode)
    (insert
     "* First\n"
     "#+ROAM_TEST: [[id:first][First]]\n"
     "** Nested\n"
     "#+ROAM_TEST: [[id:nested][Nested]]\n"
     "* Second\n"
     "#+ROAM_TEST: [[id:second][Second]]\n")
    (let* ((tree (org-element-parse-buffer))
           (first-headline
            (org-element-map tree 'headline #'identity nil t))
           (result
            (org-roam-organize--parse-id-link-keyword-entries-in-tree
             first-headline "ROAM_TEST")))
      (should
       (equal
        (mapcar
         (lambda (entry) (plist-get entry :id))
         (plist-get result :entries))
        '("first" "nested")))
      (should-not (plist-get result :malformed)))))

(ert-deftest
    org-roam-organize-test-plan-id-link-keyword-entries-preserves-order
    ()
  (let* ((entries
          '((:id "node-a" :begin 10 :end 20)
            (:id "stale-1" :begin 30 :end 40)
            (:id "node-a" :begin 50 :end 60)
            (:id "stale-2" :begin 70 :end 80)))
         (nodes
          '((:id "node-a" :title "Title A")
            (:id "node-b" :title "Title B")))
         (plan
          (org-roam-organize--plan-id-link-keyword-entries
           entries nodes)))
    (should (equal (plist-get plan :duplicates) '("node-a")))
    (should (equal (plist-get plan :removed) '("stale-2" "stale-1")))
    (should
     (equal
      (mapcar
       (lambda (edit)
         (plist-get (car edit) :begin))
       (plist-get plan :edits))
      '(70 50 30 10)))
    (should
     (equal
      (mapcar
       (lambda (node) (plist-get node :id)) (plist-get plan :missing))
      '("node-b")))))

(ert-deftest
    org-roam-organize-test-entry-edits-and-insertion-use-caller-region
    ()
  (with-temp-buffer
    (org-mode)
    (insert
     "* First\n"
     "#+ROAM_TEST: [[id:node-a][Old]] :delete t\n"
     "#+ROAM_TEST: [[id:stale][Stale]]\n"
     "** Child\nManual content\n"
     "* Second\n#+ROAM_TEST: [[id:outside][Untouched]]\n")
    (let* ((tree (org-element-parse-buffer))
           (region (org-element-map tree 'headline #'identity nil t))
           (parsed
            (org-roam-organize--parse-id-link-keyword-entries-in-tree
             region "ROAM_TEST"
             (lambda (suffix)
               (list
                :delete
                (org-roam-organize--moc-node-entry-delete-p
                 suffix)))))
           (plan
            (org-roam-organize--plan-id-link-keyword-entries
             (plist-get parsed :entries)
             '((:id "node-a" :title "A much longer title")
               (:id "node-b" :title "Title B")
               (:id "node-c" :title "Title C"))))
           (position
            (copy-marker
             (org-roam-organize--first-child-headline-begin region)
             t)))
      (cl-letf (((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest _) (ert-fail "Unexpected parse")))
                ((symbol-function 'save-buffer)
                 (lambda (&rest _) (ert-fail "Unexpected save"))))
        (org-roam-organize--apply-id-link-keyword-entry-plan
         "ROAM_TEST" plan
         (lambda (entry)
           (when (plist-get entry :delete)
             " :delete t")))
        (org-roam-organize--insert-id-link-keyword-entries
         "ROAM_TEST" (plist-get plan :missing) position))
      (set-marker position nil)
      (should
       (equal
        (buffer-string)
        (concat
         "* First\n"
         "#+ROAM_TEST: [[id:node-a][A much longer title]] :delete t\n"
         "#+ROAM_TEST: [[id:node-b][Title B]]\n"
         "#+ROAM_TEST: [[id:node-c][Title C]]\n"
         "** Child\nManual content\n"
         "* Second\n#+ROAM_TEST: [[id:outside][Untouched]]\n"))))))

(ert-deftest
    org-roam-organize-test-buffer-sync-inserts-in-initial-section-without-saving
    ()
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Example\n#+ROAM_TEST: [[id:stale][Stale]]\n")
    (cl-letf (((symbol-function 'save-buffer)
               (lambda (&rest _) (ert-fail "Unexpected save"))))
      (let
          ((result
            (org-roam-organize--sync-id-link-keyword-entries-in-buffer
             "ROAM_TEST"
             '((:id "node-b" :title "Title B")
               (:id "node-c" :title "Title C")))))
        (should (equal (plist-get result :removed) '("stale")))
        (should-not (plist-get result :duplicates))
        (should-not (plist-get result :malformed))))
    (should
     (equal
      (buffer-string)
      (concat
       "#+TITLE: Example\n\n"
       "#+ROAM_TEST: [[id:node-b][Title B]]\n"
       "#+ROAM_TEST: [[id:node-c][Title C]]\n")))))

(ert-deftest
    org-roam-organize-test-sync-id-link-keyword-entries-in-buffer-does-not-save
    ()
  (with-temp-buffer
    (org-mode)
    (insert "* Inbox\n#+ROAM_TEST: [[id:node-a][Old Title]]\n")
    (let ((save-calls 0))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _)
                   (setq save-calls (1+ save-calls)))))
        (let
            ((result
              (org-roam-organize--sync-id-link-keyword-entries-in-buffer
               "ROAM_TEST" '((:id "node-a" :title "New Title")))))
          (should-not (plist-get result :duplicates))
          (should
           (string-match-p
            (regexp-quote "#+ROAM_TEST: [[id:node-a][New Title]]")
            (buffer-string)))
          (should (= save-calls 0)))))))

(ert-deftest
    org-roam-organize-test-sync-id-link-keyword-entries-preserves-old-inbox
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (path (expand-file-name "moc/maps.org" root))
         (nodes
          '((:id "node-a" :title "Title A")
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
            "ROAM_TEST" path nodes)))
      (should (eq (plist-get result :status) 'ok))
      (should (equal (plist-get result :duplicates) '("node-a")))
      (should (equal (plist-get result :removed) '("removed")))
      (should
       (equal
        (plist-get result :malformed) '("#+ROAM_TEST: malformed"))))
    (let ((content
           (with-temp-buffer
             (insert-file-contents path)
             (buffer-string))))
      (with-temp-buffer
        (insert content)
        (should
         (= (how-many (regexp-quote
                       "#+ROAM_TEST: [[id:node-a][Title A]]")
                      (point-min) (point-max))
            2))
        (should
         (= (how-many (regexp-quote
                       "#+ROAM_TEST: [[id:node-b][Title B]]")
                      (point-min) (point-max))
            1))
        (should
         (string-match-p
          (regexp-quote
           "* Inbox\n#+ROAM_TEST: [[id:node-a][Title A]]")
          content))
        (should
         (string-prefix-p
          (concat
           "#+TITLE: Maps\n\n"
           "#+ROAM_TEST: [[id:node-b][Title B]]\n\n"
           "* Inbox\n")
          content))
        (should-not (string-match-p "Removed Title" content))
        (should (string-match-p "COMMENT Ignored" content))
        (should (string-match-p "Commented Title" content))
        (should (string-match-p "Source Title" content))))))


(ert-deftest
    org-roam-organize-test-cite-citing-node-data-deduplicates-by-reference-and-citing-node
    ()
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
        (should
         (equal (aref captured-query 7) '(= r:node_id c:cite_key)))
        (should
         (equal captured-args (list (vconcat '("ref-a" "ref-b")))))
        (should
         (equal
          (cdr (assoc "ref-a" alist))
          '((:id "citing-a" :title "Citing A")
            (:id "citing-b" :title "Citing B"))))
        (should
         (equal
          (cdr (assoc "ref-b" alist))
          '((:id "citing-c" :title "Citing C"))))))))

(ert-deftest
    org-roam-organize-test-cite-reference-map-data-reports-missing-multiple-and-duplicate-citekeys
    ()
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
        (should
         (equal
          captured-args
          (list (vconcat '("ref-a" "ref-b" "ref-c" "ref-d")))))
        (should
         (equal
          (gethash
           "ref-a" (plist-get result :uuid-to-citekey))
          "key-a"))
        (should
         (equal
          (gethash
           "key-a" (plist-get result :citekey-to-uuids))
          '("ref-b" "ref-a")))
        (should
         (equal
          (plist-get result :missing)
          '((:id "ref-d" :title "Ref D"))))
        (should
         (equal
          (plist-get result :multiple)
          '((:id
             "ref-c"
             :title "Ref C"
             :refs ("key-c-1" "key-c-2")))))
        (should
         (equal
          (plist-get result :duplicate-citekeys)
          '((:citekey "key-a" :uuids ("ref-a" "ref-b")))))
        (should-not
         (org-roam-organize--cite-reference-refs-valid-p result))))))

(ert-deftest
    org-roam-organize-test-cite-identity-map-data-preserves-candidates
    ()
  (let* ((result
          (org-roam-organize--cite-identity-map-data-from-rows
           '(("ref-a" "key-a")
             ("ref-a" "key-a")
             ("ref-b" "key-a")
             ("ref-a" "key-b"))))
         (uuid-to-citekeys (plist-get result :uuid-to-citekeys))
         (citekey-to-uuids (plist-get result :citekey-to-uuids)))
    (should
     (equal (gethash "ref-a" uuid-to-citekeys) '("key-a" "key-b")))
    (should (equal (gethash "ref-b" uuid-to-citekeys) '("key-a")))
    (should
     (equal (gethash "key-a" citekey-to-uuids) '("ref-a" "ref-b")))
    (should (equal (gethash "key-b" citekey-to-uuids) '("ref-a")))))

(ert-deftest
    org-roam-organize-test-cite-reference-map-data-preserves-duplicate-rows
    ()
  (cl-letf (((symbol-function 'org-roam-db-query)
             (lambda (&rest _arguments)
               '(("ref-a" "key-a") ("ref-a" "key-a")))))
    (let ((result
           (org-roam-organize--cite-reference-map-data
            '((:id "ref-a" :title "Ref A")))))
      (should
       (equal
        (plist-get result :multiple)
        '((:id "ref-a" :title "Ref A" :refs ("key-a" "key-a")))))
      (should-not
       (org-roam-organize--cite-reference-refs-valid-p result)))))

(ert-deftest
    org-roam-organize-test-cite-managed-identity-map-data-selectors
    ()
  (let (calls)
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (query &rest arguments)
                 (push (list query arguments) calls)
                 nil)))
      (org-roam-organize--cite-managed-identity-map-data "ref" 'all)
      (org-roam-organize--cite-managed-identity-map-data
       "ref" 'uuid '("ref-a"))
      (org-roam-organize--cite-managed-identity-map-data
       "ref" 'citekey '("key-a"))
      (org-roam-organize--cite-managed-identity-map-data
       "ref" 'uuid nil))
    (setq calls (nreverse calls))
    (should (= (length calls) 3))
    (dolist (call calls)
      (should (vectorp (car call)))
      (should (vectorp (aref (car call) 1))))
    (should (equal (cadr (nth 0 calls)) '("ref")))
    (should (equal (cadr (nth 1 calls)) '("ref" ["ref-a"])))
    (should (equal (cadr (nth 2 calls)) '("ref" ["key-a"])))
    (let ((where-clauses
           (mapcar
            (lambda (call)
              (let* ((query (car call))
                     (position (cl-position :where query)))
                (should position)
                (should (< (1+ position) (length query)))
                (aref query (1+ position))))
            calls)))
      (should
       (equal
        (nth 0 where-clauses) '(and (= r:type "cite") (= t:tag $s1))))
      (should
       (equal
        (nth 1 where-clauses)
        '(and (= r:type "cite") (= t:tag $s1) (in r:node_id $v2))))
      (should
       (equal
        (nth 2 where-clauses)
        '(and (= r:type "cite") (= t:tag $s1) (in r:ref $v2)))))))

(ert-deftest org-roam-organize-test-cite-reference-map-bijective-p ()
  (should
   (org-roam-organize--cite-reference-map-bijective-p
    '(:missing nil :multiple nil :duplicate-citekeys nil)))
  (should-not
   (org-roam-organize--cite-reference-map-bijective-p
    '(:missing
      ((:id "ref-a"))
      :multiple nil
      :duplicate-citekeys nil)))
  (should-not
   (org-roam-organize--cite-reference-map-bijective-p
    '(:missing
      nil
      :multiple
      ((:id "ref-a" :refs ("key-a" "key-b")))
      :duplicate-citekeys nil)))
  (should-not
   (org-roam-organize--cite-reference-map-bijective-p
    '(:missing
      nil
      :multiple nil
      :duplicate-citekeys
      ((:citekey "key-a" :uuids ("ref-a" "ref-b")))))))

(ert-deftest
    org-roam-organize-test-cite-sync-wrapper-uses-citing-node-keyword
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (path (expand-file-name "literature/ref.org" root))
         (record
          '(:name
            "literature"
            :tag "ref"
            :cite t
            :inbox "UnusedForCite"))
         (nodes '((:id "citing-a" :title "Citing A"))))
    (write-region
     "#+TITLE: Ref\n* COMMENT Draft\nKeep private\n" nil path)
    (let ((result
           (org-roam-organize--cite-sync-citing-node-entries
            record path nodes)))
      (should (eq (plist-get result :status) 'ok)))
    (with-temp-buffer
      (insert-file-contents path)
      (should
       (equal
        (buffer-string)
        (concat
         "#+TITLE: Ref\n\n"
         "#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]\n\n"
         "* COMMENT Draft\nKeep private\n"))))))

(ert-deftest org-roam-organize-test-cite-initial-section-boundaries ()
  (let ((nodes '((:id "citing-a" :title "Citing A"))))
    (dolist
        (case
         '(("#+TITLE: Ref\n"
            .
            "#+TITLE: Ref\n\n#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]\n")
           ("#+TITLE: Ref"
            .
            "#+TITLE: Ref\n\n#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]\n")
           ("#+TITLE: Ref\n\n* Notes\nText\n"
            .
            "#+TITLE: Ref\n\n#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]\n\n* Notes\nText\n")
           ("#+TITLE: Ref\n#+BEGIN_SRC org\n,* Fake\n\n#+END_SRC\n* Notes\n"
            .
            "#+TITLE: Ref\n#+BEGIN_SRC org\n,* Fake\n\n#+END_SRC\n\n#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]\n\n* Notes\n")))
      (with-temp-buffer
        (org-mode)
        (insert (car case))
        (org-roam-organize--sync-id-link-keyword-entries-in-buffer
         "ROAM_CITING_NODE" nodes)
        (should (equal (buffer-string) (cdr case)))))))

(ert-deftest org-roam-organize-test-cite-sync-requires-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :basic t
            :directory "literature")))
        synced)
    (cl-letf (((symbol-function
                'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (&rest _args) (setq synced t))))
      (org-roam-organize-cite-sync))
    (should-not synced)))

(ert-deftest org-roam-organize-test-cite-check-requires-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :basic t
            :directory "literature")))
        checked)
    (cl-letf (((symbol-function
                'org-roam-organize--cite-global-reference-map-data)
               (lambda () (setq checked t))))
      (org-roam-organize-cite-check))
    (should-not checked)))

(ert-deftest
    org-roam-organize-test-cite-check-reports-global-validation-result
    ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite t
            :basic t
            :directory "literature")))
        messages)
    (cl-letf (((symbol-function 'org-roam-db) (lambda () t))
              ((symbol-function
                'org-roam-organize--cite-global-reference-map-data)
               (lambda ()
                 '(:nodes
                   ((:id "ref-a" :title "Ref A")
                    (:id "ref-b" :title "Ref B"))
                   :missing nil
                   :multiple nil
                   :duplicate-citekeys
                   ((:citekey "key-a" :uuids ("ref-a" "ref-b"))))))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push
                  (apply #'format format-string args) messages))))
      (org-roam-organize-cite-check))
    (should (= (length messages) 1))
    (should
     (seq-find
      (lambda (message)
        (string-match-p
         (rx
          "Check cite references: 2 checked, "
          "0 missing cite refs, "
          "0 multiple cite refs, "
          "1 duplicate cite keys, status failed")
         message))
      messages))
    (should
     (seq-find
      (lambda (message)
        (string-match-p
         (regexp-quote org-roam-organize--report-buffer-name)
         message))
      messages))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should
       (string-match-p
        "External citekey belongs to multiple literature nodes"
        (buffer-string)))
      (should
       (string-match-p
        (rx "Check cite references: 2 checked, 0 missing cite refs")
        (buffer-string))))))

(ert-deftest org-roam-organize-test-cite-sync-syncs-all-cite-nodes ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (ref-b-file (expand-file-name "literature/ref-b.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "literature"
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
    (cl-letf (((symbol-function 'org-roam-db) (lambda () t))
              ((symbol-function
                'org-roam-organize--nodes-with-tag-and-file)
               (lambda (tag)
                 (should (equal tag "ref"))
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file)
                   (:id "ref-b" :title "Ref B" :file ,ref-b-file))))
              ((symbol-function
                'org-roam-organize--cite-reference-map-data)
               (lambda (nodes)
                 (should
                  (equal
                   (mapcar
                    (lambda (node) (plist-get node :id)) nodes)
                   '("ref-a" "ref-b")))
                 '(:missing
                   nil
                   :multiple nil
                   :duplicate-citekeys nil)))
              ((symbol-function
                'org-roam-organize--cite-citing-node-data)
               (lambda (ids)
                 (should (equal ids '("ref-a" "ref-b")))
                 '(:alist
                   (("ref-a"
                     .
                     ((:id "citing-a" :title "Citing A")))))))
              ((symbol-function
                'org-roam-organize--cite-report-reference-map-data)
               (lambda (map-data)
                 (should (equal (plist-get map-data :missing) nil))
                 '(:valid-p t :lines nil)))
              ((symbol-function 'message) (lambda (&rest _args) nil)))
      (org-roam-organize-cite-sync))
    (with-temp-buffer
      (insert-file-contents ref-a-file)
      (should
       (search-forward "#+ROAM_CITING_NODE: [[id:citing-a][Citing A]]"
                       nil t)))
    (with-temp-buffer
      (insert-file-contents ref-b-file)
      (should-not (search-forward "Stale" nil t)))))

(ert-deftest
    org-roam-organize-test-cite-sync-stops-when-reference-ref-validation-fails
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature"
             :inbox "Inbox")))
         cite-data-called
         synced)
    (write-region "#+TITLE: Ref A\n" nil ref-a-file)
    (cl-letf (((symbol-function 'org-roam-db) (lambda () t))
              ((symbol-function
                'org-roam-organize--nodes-with-tag-and-file)
               (lambda (_tag)
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file))))
              ((symbol-function
                'org-roam-organize--cite-reference-map-data)
               (lambda (_nodes)
                 '(:missing
                   ((:id "ref-a" :title "Ref A"))
                   :multiple nil
                   :duplicate-citekeys nil)))
              ((symbol-function
                'org-roam-organize--cite-citing-node-data)
               (lambda (&rest _args)
                 (setq cite-data-called t)
                 nil))
              ((symbol-function
                'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (&rest _args)
                 (setq synced t)
                 nil))
              ((symbol-function 'message) (lambda (&rest _args) nil)))
      (org-roam-organize-cite-sync))
    (should-not cite-data-called)
    (should-not synced)
    (with-temp-buffer
      (insert-file-contents ref-a-file)
      (should-not
       (search-forward org-roam-organize--cite-citing-node-keyword
                       nil t)))))

(ert-deftest
    org-roam-organize-test-cite-sync-reports-duplicate-citekeys-without-blocking
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (ref-a-file (expand-file-name "literature/ref-a.org" root))
         (org-roam-organize-mode t)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature"
             :inbox "Inbox")))
         synced
         messages)
    (write-region "#+TITLE: Ref A\n" nil ref-a-file)
    (cl-letf (((symbol-function 'org-roam-db) (lambda () t))
              ((symbol-function
                'org-roam-organize--nodes-with-tag-and-file)
               (lambda (_tag)
                 `((:id "ref-a" :title "Ref A" :file ,ref-a-file))))
              ((symbol-function
                'org-roam-organize--cite-reference-map-data)
               (lambda (_nodes)
                 '(:missing
                   nil
                   :multiple nil
                   :duplicate-citekeys
                   ((:citekey "key-a" :uuids ("ref-a" "ref-b"))))))
              ((symbol-function
                'org-roam-organize--cite-citing-node-data)
               (lambda (_ids)
                 '(:alist
                   (("ref-a"
                     .
                     ((:id "citing-a" :title "Citing A")))))))
              ((symbol-function
                'org-roam-organize--cite-sync-citing-node-entries)
               (lambda (_record _path nodes)
                 (setq synced nodes)
                 '(:status
                   ok
                   :duplicates nil
                   :removed nil
                   :malformed nil)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push
                  (apply #'format format-string args) messages))))
      (org-roam-organize-cite-sync))
    (should (equal synced '((:id "citing-a" :title "Citing A"))))
    (should (= (length messages) 1))
    (should
     (seq-find
      (lambda (message)
        (string-match-p
         (regexp-quote org-roam-organize--report-buffer-name)
         message))
      messages))
    (should
     (seq-find
      (lambda (message)
        (string-match-p
         "Sync citing-node entries: 1 synced, 0 failed" message))
      messages))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should
       (string-match-p
        "External citekey belongs to multiple literature nodes"
        (buffer-string)))
      (should
       (string-match-p
        "Sync citing-node entries: 1 synced, 0 failed"
        (buffer-string))))))

(ert-deftest
    org-roam-organize-test-cite-export-filter-replaces-managed-uuid-citation-keys
    ()
  (let ((org-roam-organize-mode t))
    (cl-letf
        (((symbol-function
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
          (org-element-map
           parse-tree 'citation-reference
           (lambda (reference)
             (push (org-element-property :key reference) keys)))
          (should (equal (nreverse keys) '("key-a" "plain-key"))))))))

(ert-deftest
    org-roam-organize-test-cite-export-filter-runs-in-org-export-pipeline
    ()
  (let ((org-roam-organize-mode t)
        captured-keys)
    (cl-letf
        (((symbol-function
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
                  (org-element-map
                   parse-tree 'citation-reference
                   (lambda (reference)
                     (push (org-element-property
                            :key reference)
                           captured-keys)))
                  parse-tree))))
          (org-export-as 'ascii nil nil t)
          (should
           (equal
            (nreverse captured-keys) '("key-a" "plain-key"))))))))

(ert-deftest
    org-roam-organize-test-cite-export-filter-errors-on-invalid-managed-map
    ()
  (let ((org-roam-organize-mode t))
    (cl-letf
        (((symbol-function
           'org-roam-organize--cite-export-reference-map-data-or-error)
          (lambda (_keys)
            (user-error "Cite reference validation failed"))))
      (with-temp-buffer
        (insert "[cite:@ref-a]")
        (org-mode)
        (should-error
         (org-roam-organize--cite-export-filter
          (org-element-parse-buffer) nil nil)
         :type 'user-error)))))

(ert-deftest
    org-roam-organize-test-cite-export-reference-map-data-validates-only-exported-managed-uuids
    ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name
            "maps"
            :tag "map"
            :moc t
            :basic t
            :directory "moc"
            :template
            ((keywords . ((filetags . ("map"))))))
           (:name
            "literature"
            :tag "ref"
            :cite t
            :basic t
            :directory "literature")))
        selected-nodes)
    (cl-letf (((symbol-function 'org-roam-organize--cite-export-nodes)
               (lambda (tag keys)
                 (should (equal tag "ref"))
                 (should (equal keys '("ref-a" "plain-key")))
                 '((:id "ref-a" :title "Ref A"))))
              ((symbol-function
                'org-roam-organize--cite-reference-map-data)
               (lambda (nodes)
                 (setq selected-nodes nodes)
                 (let ((uuid-to-citekey
                        (make-hash-table :test 'equal)))
                   (puthash "ref-a" "key-a" uuid-to-citekey)
                   (list
                    :missing nil
                    :multiple nil
                    :duplicate-citekeys nil
                    :uuid-to-citekey uuid-to-citekey)))))
      (let
          ((result
            (org-roam-organize--cite-export-reference-map-data-or-error
             '("ref-a" "plain-key"))))
        (should
         (equal selected-nodes '((:id "ref-a" :title "Ref A"))))
        (should
         (equal
          (gethash
           "ref-a" (plist-get result :uuid-to-citekey))
          "key-a"))))))

(ert-deftest
    org-roam-organize-test-cite-export-reference-map-data-skips-registry-without-keys
    ()
  (let (registry-called)
    (cl-letf (((symbol-function
                'org-roam-organize--registry-cite-records)
               (lambda ()
                 (setq registry-called t)
                 nil)))
      (let
          ((result
            (org-roam-organize--cite-export-reference-map-data-or-error
             nil)))
        (should-not registry-called)
        (should
         (hash-table-p (plist-get result :uuid-to-citekey)))))))

(ert-deftest
    org-roam-organize-test-count-nodes-with-given-tag-list-returns-ordered-alist
    ()
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
              '("idea" "ref") t)))
        (should (vectorp captured-query))
        (should
         (equal captured-args (list (vconcat '("idea" "ref")))))
        (should (equal result '(("idea" . 2) ("ref" . 0))))))))

(ert-deftest
    org-roam-organize-test-mode-does-not-register-raw-capture-template
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name "idea" :tag "idea")))
         (org-roam-capture-templates nil)
         (org-font-lock-set-keywords-hook nil)
         (org-roam-organize-mode nil))
    (unwind-protect
        (progn
          (org-roam-organize-mode 1)
          (should org-roam-organize-mode)
          (should-not org-roam-capture-templates)
          (should-not
           (memq
            #'org-roam-organize-cite-display--font-lock-setup
            org-font-lock-set-keywords-hook)))
      (org-roam-organize-mode -1))))

(ert-deftest
    org-roam-organize-test-mode-registers-and-removes-cite-integration
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "literature"
             :tag "ref"
             :cite t
             :bibliography t
             :basic t
             :directory "literature")))
         (org-export-filter-parse-tree-functions nil)
         (org-export-filter-final-output-functions nil)
         (org-font-lock-set-keywords-hook nil)
         (org-roam-organize-mode nil))
    (unwind-protect
        (progn
          (org-roam-organize-mode 1)
          (should
           (memq
            #'org-roam-organize--cite-export-filter
            org-export-filter-parse-tree-functions))
          (should
           (memq
            #'org-roam-organize-cite-display--font-lock-setup
            org-font-lock-set-keywords-hook))
          (should
           (advice-member-p
            #'org-roam-organize--filter-bibliography-files
            'org-cite-list-bibliography-files))
          (should
           (advice-member-p
            #'org-roam-organize--cite-around-export 'org-export-as))
          (org-roam-organize-mode -1)
          (should-not
           (memq
            #'org-roam-organize--cite-export-filter
            org-export-filter-parse-tree-functions))
          (should-not
           (memq
            #'org-roam-organize-cite-display--font-lock-setup
            org-font-lock-set-keywords-hook))
          (should-not
           (advice-member-p
            #'org-roam-organize--filter-bibliography-files
            'org-cite-list-bibliography-files))
          (should-not
           (advice-member-p
            #'org-roam-organize--cite-around-export 'org-export-as)))
      (org-roam-organize-mode -1))))

(ert-deftest
    org-roam-organize-test-mode-skips-disabled-bibliography-integration
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "literature"
             :tag "ref"
             :cite t
             :basic t
             :directory "literature")))
         (org-export-filter-parse-tree-functions nil)
         (org-export-filter-final-output-functions nil)
         (org-roam-organize-mode nil))
    (unwind-protect
        (progn
          (org-roam-organize-mode 1)
          (should
           (memq
            #'org-roam-organize--cite-export-filter
            org-export-filter-parse-tree-functions))
          (should-not
           (advice-member-p
            #'org-roam-organize--filter-bibliography-files
            'org-cite-list-bibliography-files))
          (should-not
           (advice-member-p
            #'org-roam-organize--cite-around-export 'org-export-as)))
      (org-roam-organize-mode -1))))

(ert-deftest
    org-roam-organize-test-check-setup-combines-variable-registry-and-capability-checks
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "idea"
             :tag "idea"
             :basic t
             :directory "fleeting"))))
    (let ((result (org-roam-organize--check-setup)))
      (should (car result))
      (should
       (string-match-p
        "Variable validation result: passed" (cdr result)))
      (should
       (string-match-p
        "Root directory validation result: passed" (cdr result)))
      (should
       (string-match-p
        "Registry validation result: passed" (cdr result)))
      (should
       (string-match-p
        "Runtime capability validation result: passed"
        (cdr result))))))

(ert-deftest
    org-roam-organize-test-check-setup-rejects-root-outside-org-roam-directory
    ()
  (let* ((roam-root (org-roam-organize-test--temporary-root))
         (root (org-roam-organize-test--temporary-root))
         (org-roam-directory roam-root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "idea"
             :tag "idea"
             :basic t
             :directory "fleeting"))))
    (let ((result (org-roam-organize--check-setup)))
      (should-not (car result))
      (should
       (string-match-p
        "Root directory validation result: failed" (cdr result)))
      (should
       (string-match-p
        "in org-roam-directory\\? nil" (cdr result))))))

(ert-deftest
    org-roam-organize-test-check-setup-displays-report-on-failure
    ()
  (let* ((roam-root (org-roam-organize-test--temporary-root))
         (root (org-roam-organize-test--temporary-root))
         (org-roam-directory roam-root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "idea"
             :tag "idea"
             :basic t
             :directory "fleeting")))


         messages
         displayed-buffer)
    (when-let* ((buffer
                 (get-buffer org-roam-organize--report-buffer-name)))
      (kill-buffer buffer))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages)))
              ((symbol-function 'display-buffer)
               (lambda (buffer &rest _args)
                 (setq displayed-buffer buffer))))
      (org-roam-organize-check-setup))
    (should (get-buffer org-roam-organize--report-buffer-name))
    (should
     (eq
      displayed-buffer
      (get-buffer org-roam-organize--report-buffer-name)))
    (should (= (length messages) 1))
    (should
     (string-match-p
      (regexp-quote
       org-roam-organize--report-buffer-name)
      (car messages)))
    (with-current-buffer org-roam-organize--report-buffer-name
      (should (eq major-mode 'special-mode))
      (should buffer-read-only)
      (should
       (string-match-p
        "Root directory validation result: failed"
        (buffer-string))))))

(ert-deftest
    org-roam-organize-test-check-setup-does-not-display-report-on-success
    ()
  (let* ((root (org-roam-organize-test--temporary-root))
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name
             "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc"
             :template
             ((keywords . ((filetags . ("map"))))))
            (:name
             "idea"
             :tag "idea"
             :basic t
             :directory "fleeting")))


         messages
         display-called)
    (when-let* ((buffer
                 (get-buffer org-roam-organize--report-buffer-name)))
      (kill-buffer buffer))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages)))
              ((symbol-function 'display-buffer)
               (lambda (&rest _args) (setq display-called t))))
      (org-roam-organize-check-setup))
    (should-not display-called)
    (should-not (get-buffer org-roam-organize--report-buffer-name))
    (should (= (length messages) 1))
    (should (string-match-p "setup checks passed" (car messages)))))


(ert-deftest
    org-roam-organize-test-capability-check-reports-missing-capabilities
    ()
  (let ((result
         (org-roam-organize--check-capabilities
          '((org-roam-organize-test--missing-function . function)
            (org-roam-organize-test--missing-variable . variable)))))
    (should-not (car result))
    (should
     (string-match-p
      "org-roam-organize-test--missing-function" (cdr result)))
    (should
     (string-match-p
      "org-roam-organize-test--missing-variable" (cdr result)))))

(ert-deftest
    org-roam-organize-test-required-runtime-capabilities-exist
    ()
  (let ((result
         (org-roam-organize--check-capabilities
          (org-roam-organize--required-capabilities))))
    (ert-info ((cdr result)) (should (car result)))))

(ert-deftest
    org-roam-organize-test-required-capabilities-follow-bibliography-option
    ()
  (let ((org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t))))
    (should-not
     (assq
      'org-cite-list-bibliography-files
      (org-roam-organize--required-capabilities))))
  (let ((org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t :bibliography t))))
    (should
     (assq
      'org-cite-list-bibliography-files
      (org-roam-organize--required-capabilities)))))


;; Single-file MOC fixtures use real Org-roam databases and capture.
(defmacro org-roam-organize-test--with-moc (&rest body)
  "Run BODY with isolated registry, files and a real Org-roam database."
  (declare (indent 0) (debug t))
  `(let* ((root (org-roam-organize-test--temporary-root))
          (default-directory root)
          (org-roam-directory root)
          (org-roam-organize-directory root)
          (org-roam-db-location (expand-file-name "roam.db" root))
          (org-id-locations-file (expand-file-name "ids" root))
          (org-roam-db-update-on-save nil)
          (org-roam-organize-mode t)
          (org-roam-organize-registry
           (copy-tree
            '((:name
               "maps"
               :tag "map"
               :moc t
               :basic t
               :directory "moc"
               :template
               ((keywords . ((filetags . ("map"))))))
              (:name "idea" :tag "idea" :basic t :directory "notes")
              (:name
               "note"
               :tag "note"
               :basic t
               :directory "notes")))))
     (unwind-protect
         (progn
           ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (file-in-directory-p
                     (buffer-file-name buffer) root))
           (with-current-buffer buffer
             (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (org-roam-db--close-all)
       (delete-directory root t))))

(defun org-roam-organize-test--write-node
    (file id title tags &optional body)
  "Write and index a real node FILE with ID, TITLE, TAGS and BODY."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert
     (format
      ":PROPERTIES:\n:ID: %s\n:END:\n#+TITLE: %s\n#+FILETAGS: :%s:\n"
      id title (mapconcat #'identity tags ":"))
     (or body "")))
  (org-roam-db-update-file file)
  file)

(defun org-roam-organize-test--write-moc (&optional body file)
  "Write a tagged MOC with BODY at FILE or the default creation target."
  (org-roam-organize-test--write-node (or
                                       file
                                       (expand-file-name
                                        "moc/maps.org"
                                        org-roam-organize-directory))
                                      "map-id" "Maps" '("map")
                                      body))

(ert-deftest org-roam-organize-test-moc-registry-declarations ()
  (org-roam-organize-test--with-moc
    (let ()
      (dolist (template
               '(nil
                 ((keywords . ((filetags . nil))))
                 ((keywords . ((filetags . ("other")))))
                 ((keywords . ((filetags . "map"))))))
        (setf (plist-get (car org-roam-organize-registry) :template)
              template)
        (should-not (car (org-roam-organize--validate-registry))))
      (setf (plist-get (car org-roam-organize-registry) :template)
            '((keywords . ((filetags . ("map" "nav"))))))
      (should (car (org-roam-organize--validate-registry)))
      (dolist (id '(nil "" "bad id" "bad\nID" "bad/id"))
        (setf (plist-get (car org-roam-organize-registry) :moc-id) id)
        (should-not (car (org-roam-organize--validate-registry))))
      (setf (plist-get (car org-roam-organize-registry) :moc-id)
            "7d713c24-20f2-167a-9a98-67a704ac31ec")
      (should (car (org-roam-organize--validate-registry)))
      (dolist (path
               '(nil
                 "/tmp/index.org" "../escape.org" "moc/index.txt"))
        (setf (plist-get (car org-roam-organize-registry) :moc-path)
              path)
        (should-not (car (org-roam-organize--validate-registry))))
      (setf (plist-get (car org-roam-organize-registry) :moc-path)
            "moc/index.org")
      (should (car (org-roam-organize--validate-registry)))
      (setf (plist-get (car org-roam-organize-registry) :template)
            '((properties . ((ID . "conflicting")))
              (keywords . ((filetags . ("map"))))))
      (should-not (car (org-roam-organize--validate-registry))))
    (dolist (key '(:moc-id :moc-path))
      (let ((org-roam-organize-registry
             (copy-tree org-roam-organize-registry)))
        (setf (plist-get (cadr org-roam-organize-registry) key)
              "value")
        (should-not (car (org-roam-organize--validate-registry)))))))

(ert-deftest
    org-roam-organize-test-moc-discovery-independent-constraints
    ()
  (org-roam-organize-test--with-moc
    (let* ((file
            (org-roam-organize-test--write-moc
             nil (expand-file-name "moved/index.org" root)))
           (moc (car org-roam-organize-registry)))
      (should
       (equal
        (plist-get (org-roam-organize--moc-discover) :file) file))
      (setf (plist-get (car org-roam-organize-registry) :moc-id)
            "map-id")
      (should
       (eq (plist-get (org-roam-organize--moc-discover) :status) 'ok))
      (setf (plist-get (car org-roam-organize-registry) :moc-path)
            "moved/index.org")
      (should
       (eq (plist-get (org-roam-organize--moc-discover) :status) 'ok))
      (setf (plist-get (car org-roam-organize-registry) :moc-id)
            "other-id")
      (should-error
       (org-roam-organize--moc-discover t)
       :type 'user-error)
      (setf
       (plist-get (car org-roam-organize-registry) :moc-id) "map-id"
       (plist-get (car org-roam-organize-registry) :moc-path) "moc/maps.org")
      (should-error
       (org-roam-organize--moc-discover t)
       :type 'user-error))))

(ert-deftest org-roam-organize-test-moc-discovery-conflicts ()
  (org-roam-organize-test--with-moc
    (should-error (org-roam-organize--moc-discover) :type 'user-error)
    (should
     (eq
      (plist-get
       (org-roam-organize--moc-discover t)
       :status)
      'missing))
    (let ((moc (car org-roam-organize-registry)))
      (setf (plist-get (car org-roam-organize-registry) :moc-id)
            "taken-id")
      (org-roam-organize-test--write-node
       (expand-file-name "other.org" root)
       "taken-id"
       "Other"
       '("other"))
      (should-error
       (org-roam-organize--moc-discover t)
       :type 'user-error))
    (setf (plist-get (car org-roam-organize-registry) :moc-id) nil)
    (let ((file (org-roam-organize-test--write-moc)))
      (org-roam-organize-test--write-node
       (expand-file-name "second.org" root)
       "second-id"
       "Second"
       '("map"))
      (should-error
       (org-roam-organize--moc-discover t)
       :type 'user-error)
      (should (file-exists-p file)))))

(ert-deftest
    org-roam-organize-test-moc-discovery-deduplicates-join-rows
    ()
  (org-roam-organize-test--with-moc
    (let ((file (org-roam-organize-test--write-moc)))
      (cl-letf (((symbol-function
                  'org-roam-organize--nodes-with-tag-and-file)
                 (lambda (_tag)
                   (list
                    (list :id "map-id" :file file)
                    (list :id "map-id" :file file)))))
        (should
         (eq
          (plist-get
           (org-roam-organize--moc-discover)
           :status)
          'ok))))))

(ert-deftest org-roam-organize-test-moc-create-capture-combinations ()
  (dolist (explicit-id '(nil t))
    (dolist (explicit-path '(nil t))
      (org-roam-organize-test--with-moc
        (let* ((moc (car org-roam-organize-registry))
               (file
                (expand-file-name (if explicit-path
                                      "custom/index.org"
                                    "moc/maps.org")
                                  root))
               (capture-count 0)
               (capture (symbol-function 'org-roam-capture-)))
          (when explicit-id
            (setf (plist-get (car org-roam-organize-registry) :moc-id)
                  "chosen-id"))
          (when explicit-path
            (setf (plist-get
                   (car org-roam-organize-registry)
                   :moc-path)
                  "custom/index.org"))
          (cl-letf (((symbol-function 'org-roam-capture-)
                     (lambda (&rest args)
                       (setq capture-count (1+ capture-count))
                       (apply capture args))))
            (should
             (eq
              (plist-get
               (org-roam-organize-moc-create)
               :status)
              'ok)))
          (should (= capture-count 1))
          (should (file-exists-p file))
          (with-current-buffer (find-file-noselect file)
            (should
             (equal
              (org-entry-get (point-min) "ID")
              (if explicit-id
                  "chosen-id"
                (plist-get (org-roam-organize--moc-discover) :id))))
            (let ((text (buffer-string)))
              (should
               (string-match-p (regexp-quote "#+TITLE: Maps") text))
              (should
               (string-match-p
                (regexp-quote "#+FILETAGS: :map:") text))
              (should (string-match-p ":CUSTOM_ID: idea" text))
              (should (string-match-p ":CUSTOM_ID: note" text))
              (should-not (string-match-p ":CUSTOM_ID: map\\b" text))
              (should-not
               (string-match-p
                "MOC_MANAGED\\|Inbox\\|ROAM_NODE" text))))
          (should
           (= (plist-get (org-roam-organize-moc-create) :created)
              0)))))))

(ert-deftest
    org-roam-organize-test-moc-create-abort-and-target-conflict
    ()
  (org-roam-organize-test--with-moc
    (cl-letf (((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest _) nil)))
      (should
       (eq
        (plist-get (org-roam-organize-moc-create) :status) 'failed)))
    (should-not
     (file-exists-p (expand-file-name "moc/maps.org" root)))
    (write-region
     "Manual content" nil (expand-file-name "moc/maps.org" root))
    (should
     (eq (plist-get (org-roam-organize-moc-create) :status) 'failed))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "moc/maps.org" root))
      (should (equal (buffer-string) "Manual content")))))

(ert-deftest
    org-roam-organize-test-moc-create-preserves-existing-file-and-regions
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((body
          "Manual preface\n* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\nHandwritten\n")
         (file (org-roam-organize-test--write-moc body)))
      (cl-letf (((symbol-function 'org-roam-organize--capture-node)
                 (lambda (&rest _)
                   (ert-fail "Existing file must not be captured"))))
        (should
         (= (plist-get (org-roam-organize-moc-create) :created) 1)))
      (with-current-buffer (find-file-noselect file)
        (should (string-match-p (regexp-quote body) (buffer-string))))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _)
                   (ert-fail "Repeated create must not save"))))
        (should
         (= (plist-get (org-roam-organize-moc-create) :created)
            0))))))

(ert-deftest
    org-roam-organize-test-moc-create-common-level-and-inbox-policy
    ()
  (dolist (level '(1 2 3))
    (dolist (parent '(nil t))
      (org-roam-organize-test--with-moc
        (let*
            ((body
              (concat
               (unless (= level 1)
                 "* Knowledge\n")
               (org-roam-organize--moc-region-text
                (cadr org-roam-organize-registry) level)
               (when parent
                 "* Inbox\nManual intro\n** Existing child\nChild text\n")))
             (file (org-roam-organize-test--write-moc body))
             (before
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string)))
             (new
              (org-roam-organize--moc-region-text
               (caddr org-roam-organize-registry) level))
             (expected
              (cond
               ((= level 1)
                (concat before new))
               (parent
                (replace-regexp-in-string (regexp-quote
                                           "** Existing child\n")
                                          (concat
                                           new "** Existing child\n")
                                          before
                                          t t))
               (t
                (concat before "* Inbox\n" new)))))
          (should
           (= (plist-get (org-roam-organize-moc-create) :created) 1))
          (with-current-buffer (find-file-noselect file)
            (should (equal (buffer-string) expected))
            (let* ((tree (org-element-parse-buffer))
                   (layout (org-roam-organize--moc-regions tree)))
              (should (= (plist-get layout :level) level))
              (should-not (plist-get layout :missing))
              (when (and (= level 3) (not parent))
                (should-not
                 (org-element-map
                  tree 'headline
                  (lambda (h)
                    (when (= (org-element-property :level h) 2)
                      h))
                  nil t))))))))))

(ert-deftest
    org-roam-organize-test-moc-create-inbox-uses-ast-and-first-child
    ()
  (org-roam-organize-test--with-moc
    (setf (plist-get (car org-roam-organize-registry) :inbox)
          "Incoming")
    (let*
        ((body
          (concat
           "#+begin_src org\n,* Incoming\n#+end_src\n"
           "* COMMENT Incoming\nIgnored content\n"
           "* Manual\n** Incoming\nNested content\n"
           "* Knowledge\n*** Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
           "* Incoming :container:\n:PROPERTIES:\n:NOTE: Keep property\n:END:\nManual intro\n"
           "** First child\nChild text\n*** Deeper child\nDeep text\n"
           "* Tail\nKeep tail\n"))
         (file (org-roam-organize-test--write-moc body))
         (before
          (with-temp-buffer
            (insert-file-contents file)
            (buffer-string)))
         (new
          (org-roam-organize--moc-region-text
           (caddr org-roam-organize-registry) 3))
         (expected
          (replace-regexp-in-string (regexp-quote "** First child\n")
                                    (concat
                                     new "** First child\n")
                                    before
                                    t t)))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 1))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) expected))
        (let* ((layout
                (org-roam-organize--moc-regions
                 (org-element-parse-buffer)))
               (note (cdr (assoc "note" (plist-get layout :regions))))
               (parent (org-element-lineage note '(headline))))
          (should (= (org-element-property :level note) 3))
          (should (= (org-element-property :level parent) 1))
          (should
           (equal
            (org-element-property :raw-value parent) "Incoming")))))))

(ert-deftest org-roam-organize-test-moc-structure-errors-are-atomic ()
  (dolist
      (body
       '("* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
         "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n** Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"
         "* Renamed\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
         "* COMMENT Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"))
    (org-roam-organize-test--with-moc
      (let* ((file (org-roam-organize-test--write-moc body))
             (before
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string))))
        (dolist (command
                 '(org-roam-organize-moc-create
                   org-roam-organize-moc-sync))
          (should (eq (plist-get (funcall command) :status) 'failed))
          (with-current-buffer (find-file-noselect file)
            (should (equal (buffer-string) before))
            (should-not (buffer-modified-p))))))))

(ert-deftest
    org-roam-organize-test-moc-sync-batch-scope-and-idempotence
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((body
          (concat
           "#+ROAM_NODE: [[id:outside][Outside]]\n"
           "* Parent A\n** Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
           "#+ROAM_NODE: [[id:a][Old]] :delete t\n"
           "#+ROAM_NODE: [[id:a][Duplicate]]\n"
           "#+ROAM_NODE: [[id:stale][Stale]]\n"
           "#+ROAM_NODE: malformed\n"
           "*** Inbox\nHandwritten\n**** Child\nKeep\n"
           "*** COMMENT Hidden\n#+ROAM_NODE: [[id:hidden][Old]]\n"
           "#+begin_src org\n#+ROAM_NODE: [[id:source][Old]]\n#+end_src\n"
           "* Parent B\n** Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"
           "*** Manual\n#+ROAM_NODE: [[id:a][Short]]\n"
           "* Outside\n#+ROAM_NODE: [[id:outside][Outside]]\n"))
         (file (org-roam-organize-test--write-moc body))
         (save-count 0)
         (db-count 0)
         (parse-count 0)
         (save (symbol-function 'save-buffer))
         (db (symbol-function 'org-roam-db-update-file))
         (parse (symbol-function 'org-element-parse-buffer)))
      (org-roam-organize-test--write-node
       (expand-file-name "a.org" root)
       "a"
       "A much longer title"
       '("idea" "note"))
      (org-roam-organize-test--write-node
       (expand-file-name "b.org" root) "b" "B" '("idea" "note"))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest args)
                   (when (buffer-modified-p)
                     (setq save-count (1+ save-count)))
                   (apply save args)))
                ((symbol-function 'org-roam-db-update-file)
                 (lambda (&rest args)
                   (setq db-count (1+ db-count))
                   (apply db args)))
                ((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest args)
                   (when (equal buffer-file-name file)
                     (setq parse-count (1+ parse-count)))
                   (apply parse args))))
        (let* ((result (org-roam-organize-moc-sync))
               (first (car (plist-get result :results))))
          (should (eq (plist-get result :status) 'ok))
          (should (equal (plist-get first :duplicates) '("a")))
          (should (equal (plist-get first :removed) '("stale")))
          (should
           (equal
            (plist-get first :malformed)
            '("#+ROAM_NODE: malformed"))))
        (should (= save-count 1))
        (should (= db-count 1))
        ;; The explicit document parse is once; the DB refresh parses separately.
        (should (<= parse-count 2))
        (setq
         save-count 0
         db-count 0
         parse-count 0)
        (should-not (plist-get (org-roam-organize-moc-sync) :saved))
        (should (= save-count 0))
        (should (= db-count 0))
        (should (= parse-count 1)))
      (with-current-buffer (find-file-noselect file)
        (let ((text (buffer-string)))
          (should
           (string-match-p
            (regexp-quote "[[id:a][A much longer title]] :delete t")
            text))
          (should
           (string-match-p
            (regexp-quote
             "*** Inbox\nHandwritten\n#+ROAM_NODE: [[id:b][B]]\n**** Child\nKeep")
            text))
          (should
           (string-match-p
            (regexp-quote
             "*** Manual\n#+ROAM_NODE: [[id:a][A much longer title]]\n*** Inbox\n#+ROAM_NODE: [[id:b][B]]\n* Outside")
            text))
          (should (string-match-p "malformed" text))
          (should
           (string-match-p (regexp-quote "[[id:hidden][Old]]") text))
          (should
           (string-match-p (regexp-quote "[[id:source][Old]]") text))
          (should (string-prefix-p ":PROPERTIES:" text))
          (should
           (= (how-many "\\[\\[id:outside" (point-min) (point-max))
              2)))))))

(ert-deftest
    org-roam-organize-test-moc-sync-missing-region-does-not-create
    ()
  (org-roam-organize-test--with-moc
    (let ((file
           (org-roam-organize-test--write-moc
            "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n")))
      (org-roam-organize-test--write-node
       (expand-file-name "a.org" root) "a" "A" '("idea"))
      (let ((result (org-roam-organize-moc-sync)))
        (should (eq (plist-get result :status) 'partial))
        (should
         (eq
          (plist-get
           (cadr (plist-get result :results))
           :status)
          'failed)))
      (with-current-buffer (find-file-noselect file)
        (should (string-match-p "\\[\\[id:a" (buffer-string)))
        (should-not
         (string-match-p ":CUSTOM_ID: note" (buffer-string)))))))

(ert-deftest
    org-roam-organize-test-moc-level-zero-identity-and-members
    ()
  (org-roam-organize-test--with-moc
    (org-roam-organize-test--write-node
     (expand-file-name "headlines.org" root)
     "ordinary"
     "Ordinary"
     '("other")
     "* A headline :map:idea:\n:PROPERTIES:\n:ID: headline-id\n:END:\n")
    (should
     (eq
      (plist-get
       (org-roam-organize--moc-discover t)
       :status)
      'missing))
    (let
        ((file
          (org-roam-organize-test--write-moc
           "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n* Headline :idea:\n:PROPERTIES:\n:ID: nested-id\n:END:\n")))
      (should
       (eq (plist-get (org-roam-organize-moc-sync) :status) 'ok))
      (with-current-buffer (find-file-noselect file)
        (should-not
         (string-match-p
          (regexp-quote "#+ROAM_NODE:") (buffer-string)))))))

(ert-deftest org-roam-organize-test-moc-open-validates-moved-file ()
  (org-roam-organize-test--with-moc
    (let* ((file
            (org-roam-organize-test--write-moc
             nil (expand-file-name "moved.org" root)))
           opened)
      (cl-letf (((symbol-function 'find-file)
                 (lambda (path &rest _) (setq opened path))))
        (org-roam-organize-moc-open-index)
        (should (equal opened file))
        (setq opened nil)
        (setf (plist-get (car org-roam-organize-registry) :moc-id)
              "wrong-id")
        (should
         (eq
          (plist-get
           (org-roam-organize-moc-open-index)
           :status)
          'failed))
        (should-not opened)))))

(ert-deftest
    org-roam-organize-test-moc-file-identity-preflight-is-atomic
    ()
  (dolist (replacement '(":ID: stale-id" "#+FILETAGS: :other:"))
    (org-roam-organize-test--with-moc
      (let
          ((file
            (org-roam-organize-test--write-moc
             "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n#+ROAM_NODE: [[id:stale][Keep until fixed]]\n")))
        (with-current-buffer (find-file-noselect file)
          (goto-char (point-min))
          (re-search-forward
           (if (string-prefix-p ":ID" replacement)
               "^:ID:.*$"
             "^#\\+FILETAGS:.*$"))
          (replace-match replacement t t)
          (let ((before (buffer-string)))
            (should
             (eq
              (plist-get
               (org-roam-organize-moc-sync)
               :status)
              'failed))
            (should (equal before (buffer-string)))))))))

(ert-deftest
    org-roam-organize-test-moc-discovery-rejects-invalid-db-identities
    ()
  (org-roam-organize-test--with-moc
    (let ((file (org-roam-organize-test--write-moc)))
      (dolist (node
               (list
                (list :id "bad id" :file file)
                (list :id "map-id" :file "/outside/index.org")
                (list
                 :id "map-id"
                 :file
                 (expand-file-name "absent.org" root))))
        (cl-letf (((symbol-function
                    'org-roam-organize--nodes-with-tag-and-file)
                   (lambda (_tag) (list node))))
          (should-error
           (org-roam-organize--moc-discover t)
           :type 'user-error))))))

(ert-deftest
    org-roam-organize-test-moc-create-duplicate-level-one-inboxes-rejected
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((file
          (org-roam-organize-test--write-moc
           "* First\n** Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n* Inbox\nFirst manual\n* Inbox\nSecond manual\n* Tail\nKeep\n"))
         (before
          (with-temp-buffer
            (insert-file-contents file)
            (buffer-string))))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _)
                   (ert-fail "Ambiguous Inbox must not save"))))
        (should
         (eq
          (plist-get (org-roam-organize-moc-create) :status)
          'failed)))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) before))
        (should-not (buffer-modified-p))))))

(ert-deftest
    org-roam-organize-test-moc-create-invalid-declarations-have-no-effects
    ()
  (org-roam-organize-test--with-moc
    (setf (plist-get (car org-roam-organize-registry) :template) nil)
    (cl-letf (((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest _)
                 (ert-fail "Invalid declaration must not capture"))))
      (should
       (eq
        (plist-get (org-roam-organize-moc-create) :status) 'failed)))
    (should-not
     (file-exists-p (expand-file-name "moc/maps.org" root)))))

(ert-deftest
    org-roam-organize-test-moc-sync-excludes-live-blocks-and-moc-file
    ()
  (org-roam-organize-test--with-moc
    (let
        ((file
          (org-roam-organize-test--write-moc
           (concat
            "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
            "#+begin_src org\n#+ROAM_NODE: [[id:source][Keep source]]\n#+end_src\n"
            "** COMMENT Hidden\n#+ROAM_NODE: [[id:comment][Keep comment]]\n"
            "* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"))))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (search-forward "#+FILETAGS: :map:")
        (replace-match "#+FILETAGS: :map:idea:" t t)
        (save-buffer))
      (org-roam-db-update-file file)
      (should-not (plist-get (org-roam-organize-moc-sync) :saved))
      (with-current-buffer (find-file-noselect file)
        (should
         (string-match-p
          (regexp-quote
           "[[id:source][Keep source]]")
          (buffer-string)))
        (should
         (string-match-p
          (regexp-quote
           "[[id:comment][Keep comment]]")
          (buffer-string)))
        (should-not
         (string-match-p
          (regexp-quote "[[id:map-id]") (buffer-string)))))))

(ert-deftest org-roam-organize-test-moc-scale-ten-thousand-entries ()
  (org-roam-organize-test--with-moc
    (setq org-roam-organize-registry
          (cons
           (car org-roam-organize-registry)
           (cl-loop
            for n below 4 collect
            (list
             :name (format "region%d" n)
             :tag (format "tag%d" n)))))
    (let ((nodes (make-hash-table :test 'equal))
          (saves 0)
          (updates 0)
          (save (symbol-function 'save-buffer))
          (db (symbol-function 'org-roam-db-update-file)))
      (with-current-buffer (find-file-noselect
                            (org-roam-organize-test--write-moc))
        (goto-char (point-max))
        (dotimes (region 4)
          (insert
           (format
            "* Region%d\n:PROPERTIES:\n:CUSTOM_ID: tag%d\n:END:\n"
            region region))
          (let (members)
            (dotimes (n 2500)
              (let ((id (format "node-%d-%d" region n)))
                (insert
                 (org-roam-organize--moc-node-entry-line id "Old"))
                (push (list
                       :id id
                       :title "Updated"
                       :file "/member.org")
                      members)))
            (puthash
             (format "tag%d" region) (nreverse members) nodes)))
        (cl-letf (((symbol-function
                    'org-roam-organize--nodes-with-tag-and-file)
                   (lambda (tag) (gethash tag nodes)))
                  ((symbol-function 'save-buffer)
                   (lambda (&rest args)
                     (when (buffer-modified-p)
                       (setq saves (1+ saves)))
                     (apply save args)))
                  ((symbol-function 'org-roam-db-update-file)
                   (lambda (&rest args)
                     (setq updates (1+ updates))
                     (apply db args))))
          (let* ((start (float-time))
                 (tree (org-element-parse-buffer))
                 (layout (org-roam-organize--moc-regions tree)))
            (should
             (plist-get
              (org-roam-organize--moc-sync-buffer
               layout buffer-file-name)
              :saved))
            (message
             "MOC benchmark: 10000 entries, first %.3fs, saves=%d DB updates=%d"
             (- (float-time) start) saves updates))
          (setq
           saves 0
           updates 0)
          (let* ((start (float-time))
                 (tree (org-element-parse-buffer))
                 (layout (org-roam-organize--moc-regions tree)))
            (should-not
             (plist-get
              (org-roam-organize--moc-sync-buffer
               layout buffer-file-name)
              :saved))
            (message
             "MOC benchmark: 10000 entries, unchanged %.3fs, saves=%d DB updates=%d"
             (- (float-time) start) saves updates))
          (should (= saves 0))
          (should (= updates 0)))))))


(ert-deftest org-roam-organize-test-registry-tags-use-org-alphabet ()
  (dolist (index '(0 1))
    (dolist (tag
             '(nil
               10
               ""
               "bad\n* Unexpected"
               "bad\r:END:"
               "bad\tvalue"
               "with space"
               "bad:tag"
               "bad-tag"
               "bad[link]"
               "bad\0value"))
      (org-roam-organize-test--with-moc
        (setf (plist-get (nth index org-roam-organize-registry) :tag)
              tag)
        (let ((result (org-roam-organize--validate-registry)))
          (should-not (car result))
          (should
           (string-match-p
            ":tag valid nonempty Org tag" (cdr result))))))
    (dolist (tag '("alpha" "A0_@#%" "@work" "#ref" "100%" "科研"))
      (org-roam-organize-test--with-moc
        (setf (plist-get (nth index org-roam-organize-registry) :tag)
              tag)
        (when (= index 0)
          (setf (plist-get (car org-roam-organize-registry) :template)
                `((keywords . ((filetags . (,tag)))))))
        (should (car (org-roam-organize--validate-registry)))))))

(ert-deftest
    org-roam-organize-test-moc-title-round-trips-with-org-parser
    ()
  (dolist (title
           '("Research"
             "Research: physics"
             "Research [1/2]"
             "*bold* research"
             "TODO-related research"
             "研究"))
    (should (org-roam-organize--moc-headline-title-p title)))
  (dolist (title
           '(nil
             10
             ""
             " "
             " Research"
             "Research "
             "Research\n* Unexpected"
             "Research\rUnexpected"
             "Research\tvalue"
             "TODO Research"
             "DONE Research"
             "[#A] Research"
             "COMMENT Research"
             "Research :physics:"
             "Research :ARCHIVE:"
             "Footnotes"))
    (should-not (org-roam-organize--moc-headline-title-p title)))
  (let ((org-todo-keywords '((sequence "WAIT" "|" "FINISHED"))))
    (should-not
     (org-roam-organize--moc-headline-title-p "WAIT Research"))
    (should-not
     (org-roam-organize--moc-headline-title-p "FINISHED Research"))
    (should
     (org-roam-organize--moc-headline-title-p "TODO Research"))))

(ert-deftest
    org-roam-organize-test-registry-rejects-nonliteral-region-titles
    ()
  (org-roam-organize-test--with-moc
    (dolist (title
             '(""
               " "
               "Research\n* Unexpected"
               "TODO Research"
               "[#A] Research"
               "COMMENT Research"
               "Research :physics:"))
      (setf (plist-get (cadr org-roam-organize-registry) :moc-title)
            title)
      (let ((result (org-roam-organize--validate-registry)))
        (should-not (car result))
        (should
         (string-match-p
          "management titles must round-trip" (cdr result)))))
    (setf (plist-get (cadr org-roam-organize-registry) :moc-title)
          "Research")
    (should (car (org-roam-organize--validate-registry)))
    (setf (plist-get (car org-roam-organize-registry) :moc-title)
          "Maps\n#+FILETAGS: :other:")
    (should-not (car (org-roam-organize--validate-registry)))))

(ert-deftest
    org-roam-organize-test-moc-unsafe-structure-declarations-do-not-capture
    ()
  (dolist (declaration
           '((:tag . "bad\n* Unexpected")
             (:moc-title . "Research :physics:")
             (:moc-title . "Research\n* Unexpected")))
    (org-roam-organize-test--with-moc
      (setf (plist-get
             (cadr org-roam-organize-registry) (car declaration))
            (cdr declaration))
      (cl-letf (((symbol-function 'org-roam-organize--capture-node)
                 (lambda (&rest _)
                   (ert-fail "Invalid metadata must not capture")))
                ((symbol-function 'make-directory)
                 (lambda (&rest _)
                   (ert-fail
                    "Invalid metadata must not create directories"))))
        (should
         (eq
          (plist-get (org-roam-organize-moc-create) :status)
          'failed)))
      (should-not
       (file-exists-p (expand-file-name "moc/maps.org" root))))))

(ert-deftest
    org-roam-organize-test-moc-new-titles-respect-file-todo-keywords
    ()
  (org-roam-organize-test--with-moc
    (setf (plist-get (cadr org-roam-organize-registry) :moc-title)
          "WAIT Research")
    (should (car (org-roam-organize--validate-registry)))
    (let ((file
           (org-roam-organize-test--write-moc
            "#+TODO: WAIT | DONE\n")))
      (with-current-buffer (find-file-noselect file)
        (let ((before (buffer-string)))
          (should
           (eq
            (plist-get
             (org-roam-organize-moc-create)
             :status)
            'failed))
          (should (equal before (buffer-string)))
          (should-not (buffer-modified-p)))))))

(ert-deftest
    org-roam-organize-test-moc-new-titles-respect-template-todo-keywords
    ()
  (org-roam-organize-test--with-moc
    (setf
     (plist-get (cadr org-roam-organize-registry) :moc-title) "WAIT Research"
     (plist-get (car org-roam-organize-registry) :moc-path) "new/deep/index.org"
     (plist-get (car org-roam-organize-registry) :template) '((keywords . ((filetags . ("map")) (todo . "WAIT | DONE")))))
    (should (car (org-roam-organize--validate-registry)))
    (cl-letf (((symbol-function 'org-roam-organize--capture-node)
               (lambda (&rest _)
                 (ert-fail "Invalid title must not capture"))))
      (should
       (eq
        (plist-get (org-roam-organize-moc-create) :status) 'failed)))
    (should-not (file-exists-p (expand-file-name "new" root)))))

(ert-deftest
    org-roam-organize-test-moc-capture-keeps-structural-text-literal
    ()
  (org-roam-organize-test--with-moc
    (let ((title "Research ${title} %t %<%Y>"))
      (setf
       (plist-get (car org-roam-organize-registry) :tag) "map%t"
       (plist-get (car org-roam-organize-registry) :template) '((keywords . ((filetags . ("map%t" "nav%t")))))
       (plist-get (cadr org-roam-organize-registry) :tag) "idea%t"
       (plist-get (cadr org-roam-organize-registry) :moc-title) title)
      (should (car (org-roam-organize--validate-registry)))
      (should
       (eq (plist-get (org-roam-organize-moc-create) :status) 'ok))
      (with-current-buffer (find-file-noselect
                            (expand-file-name "moc/maps.org" root))
        (let* ((layout
                (org-roam-organize--moc-regions
                 (org-element-parse-buffer)))
               (region
                (cdr (assoc "idea%t" (plist-get layout :regions)))))
          (should region)
          (should
           (equal (org-element-property :raw-value region) title))
          (should
           (equal
            (org-element-property :CUSTOM_ID region) "idea%t"))))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 0))
      (should-not (plist-get (org-roam-organize-moc-sync) :saved)))))


(ert-deftest
    org-roam-organize-test-moc-create-empty-layout-defaults-to-level-one
    ()
  (org-roam-organize-test--with-moc
    (setf (plist-get (car org-roam-organize-registry) :inbox)
          "Incoming")
    (let* ((file
            (org-roam-organize-test--write-moc "Manual preface\n"))
           (before
            (with-temp-buffer
              (insert-file-contents file)
              (buffer-string)))
           (expected
            (concat
             before
             (org-roam-organize--moc-region-text
              (cadr org-roam-organize-registry) 1)
             (org-roam-organize--moc-region-text
              (caddr org-roam-organize-registry) 1))))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 2))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) expected))
        (should-not
         (string-match-p
          (regexp-quote "* Incoming") (buffer-string)))))))

(ert-deftest
    org-roam-organize-test-moc-create-invalid-new-inbox-is-atomic
    ()
  (dolist (name
           '("WAIT Incoming"
             "Incoming\n* Unexpected"
             "Incoming :tag:"))
    (org-roam-organize-test--with-moc
      (setf (plist-get (car org-roam-organize-registry) :inbox) name)
      (let*
          ((file
            (org-roam-organize-test--write-moc
             "#+TODO: WAIT | DONE\n* Knowledge\n*** Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"))
           (before
            (with-temp-buffer
              (insert-file-contents file)
              (buffer-string))))
        (should
         (eq
          (plist-get (org-roam-organize-moc-create) :status) 'failed))
        (with-current-buffer (find-file-noselect file)
          (should (equal (buffer-string) before))
          (should-not (buffer-modified-p)))))))


(ert-deftest
    org-roam-organize-test-moc-member-inbox-keeps-headline-metadata
    ()
  (dolist (child '(nil t))
    (dolist
        (manual
         '(""
           "Introductory text\n:LOGBOOK:\n- Keep this note\n:END:\n"))
      (org-roam-organize-test--with-moc
        (let*
            ((body
              (concat
               "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
               "** Inbox\nSCHEDULED: <2026-11-05 Thu>\n"
               ":PROPERTIES:\n:CUSTOM_ID: idea-inbox\n:NOTE: Keep property\n:END:\n"
               manual
               (when child
                 "*** Child\nChild text\n")
               "* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"))
             (file (org-roam-organize-test--write-moc body))
             (before
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string)))
             (anchor
              (if child
                  "*** Child\n"
                "* Note\n"))
             (expected
              (replace-regexp-in-string
               (regexp-quote anchor)
               (concat "#+ROAM_NODE: [[id:node-a][Example]]\n" anchor)
               before
               t
               t)))
          (org-roam-organize-test--write-node
           (expand-file-name "member.org" root)
           "node-a"
           "Example"
           '("idea"))
          (should
           (eq (plist-get (org-roam-organize-moc-sync) :status) 'ok))
          (with-current-buffer (find-file-noselect file)
            (should (equal (buffer-string) expected))
            (let*
                ((tree (org-element-parse-buffer))
                 (inbox
                  (org-element-map
                   tree 'headline
                   (lambda (headline)
                     (when (equal
                            (org-element-property
                             :raw-value headline)
                            "Inbox")
                       headline))
                   nil t))
                 (entries
                  (org-roam-organize--parse-id-link-keyword-entries-in-tree
                   inbox "ROAM_NODE")))
              (should
               (equal
                (org-element-property :CUSTOM_ID inbox) "idea-inbox"))
              (should
               (equal
                (org-element-property :NOTE inbox) "Keep property"))
              (should (org-element-property :scheduled inbox))
              (should
               (equal
                (mapcar
                 (lambda (entry)
                   (plist-get entry :id))
                 (plist-get entries :entries))
                '("node-a")))))
          (should-not
           (plist-get (org-roam-organize-moc-sync) :saved)))))))

(ert-deftest
    org-roam-organize-test-moc-region-unknown-custom-id-conflict
    ()
  (dolist (wrong-id '("wrong-id" ""))
    (org-roam-organize-test--with-moc
      (let* ((body
              (concat
               "* Idea\n:PROPERTIES:\n:CUSTOM_ID: "
               wrong-id
               "\n:END:\n"
               "#+ROAM_NODE: [[id:stale][Do not remove]]\n"
               "* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"))
             (file (org-roam-organize-test--write-moc body))
             (before
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string))))
        (cl-letf (((symbol-function 'save-buffer)
                   (lambda (&rest _)
                     (ert-fail "Conflicting region must not save"))))
          (dolist (command
                   '(org-roam-organize-moc-create
                     org-roam-organize-moc-sync))
            (let ((result (funcall command)))
              (should (eq (plist-get result :status) 'failed))
              (should
               (string-match-p
                "identity conflict" (plist-get result :reason))))))
        (with-current-buffer (find-file-noselect file)
          (should (equal (buffer-string) before))
          (should-not (buffer-modified-p)))))))

(ert-deftest
    org-roam-organize-test-moc-region-title-alone-does-not-claim-identity
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((body
          (concat
           "* Idea\n:PROPERTIES:\n:ID: handwritten-id\n:END:\nManual text\n"
           "* Handwritten\n:PROPERTIES:\n:CUSTOM_ID: manual\n:END:\nKeep this\n"
           "* COMMENT Idea\n:PROPERTIES:\n:CUSTOM_ID: archived-idea\n:END:\nArchive\n"))
         (file (org-roam-organize-test--write-moc body)))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 2))
      (with-current-buffer (find-file-noselect file)
        (should (string-match-p (regexp-quote body) (buffer-string)))
        (let ((layout
               (org-roam-organize--moc-regions
                (org-element-parse-buffer))))
          (should (= (length (plist-get layout :regions)) 2))
          (should-not (plist-get layout :missing))))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 0)))))

(ert-deftest
    org-roam-organize-test-moc-region-known-identity-wins-over-unclaimed-title
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((body
          (concat
           "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
           "** Note\n:PROPERTIES:\n:CUSTOM_ID: manual-note\n:END:\nManual child\n"
           "* Idea\n:PROPERTIES:\n:CUSTOM_ID: manual-idea\n:END:\n"
           "#+ROAM_NODE: [[id:manual][Keep manual entry]]\n"))
         (file (org-roam-organize-test--write-moc body)))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 1))
      (should-not (plist-get (org-roam-organize-moc-sync) :saved))
      (with-current-buffer (find-file-noselect file)
        (should
         (string-match-p (regexp-quote body) (buffer-string)))))))

(ert-deftest
    org-roam-organize-test-moc-regions-allow-shared-declared-titles
    ()
  (org-roam-organize-test--with-moc
    (setf (plist-get (caddr org-roam-organize-registry) :moc-title)
          "Idea")
    (let ((file
           (org-roam-organize-test--write-moc
            "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n")))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 1))
      (with-current-buffer (find-file-noselect file)
        (let ((layout
               (org-roam-organize--moc-regions
                (org-element-parse-buffer))))
          (should
           (equal
            (mapcar #'car (plist-get layout :regions))
            '("idea" "note")))
          (should-not (plist-get layout :missing)))))))

(ert-deftest org-roam-organize-test-moc-capture-file-title-is-literal
    ()
  (dolist (title
           '("Navigation %t"
             "Navigation ${title} %<%Y>"
             "Navigation %(error \"must stay literal\")"
             "Navigation __ORGANIZE_LITERAL_PERCENT___TITLE %t"))
    (org-roam-organize-test--with-moc
      (setf (plist-get (car org-roam-organize-registry) :moc-title)
            title)
      (should
       (eq (plist-get (org-roam-organize-moc-create) :status) 'ok))
      (let* ((identity (org-roam-organize--moc-discover))
             (file (plist-get identity :file)))
        (should
         (equal
          (caar
           (org-roam-db-query
            [:select [title] :from nodes :where (= id $s1)]
            (plist-get identity :id)))
          title))
        (with-current-buffer (find-file-noselect file)
          (should
           (string-match-p
            (regexp-quote
             (concat "#+TITLE: " title "\n"))
            (buffer-string)))))
      (should
       (= (plist-get (org-roam-organize-moc-create) :created) 0)))))


(ert-deftest
    org-roam-organize-test-moc-member-inbox-duplicates-reject-entire-sync
    ()
  (dolist (name '("Inbox" "Incoming"))
    (dolist (state '(empty complete missing))
      (org-roam-organize-test--with-moc
        (setf (plist-get (caddr org-roam-organize-registry) :inbox)
              name)
        (let*
            ((body
              (concat
               "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
               "#+ROAM_NODE: [[id:node-a][Old title]]\n** Inbox\nIdea text\n"
               "* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"
               "** "
               name
               "\nFirst text\n"
               (when (eq state 'complete)
                 "#+ROAM_NODE: [[id:node-b][B]]\n")
               "** "
               name
               "\nSecond text\n"))
             (file (org-roam-organize-test--write-moc body))
             (before
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string))))
          ;; The earlier valid region has an actual update ready to apply.
          (org-roam-organize-test--write-node
           (expand-file-name "a.org" root)
           "node-a"
           "New title"
           '("idea"))
          (unless (eq state 'empty)
            (org-roam-organize-test--write-node
             (expand-file-name "b.org" root) "node-b" "B" '("note")))
          (cl-letf
              (((symbol-function 'save-buffer)
                (lambda (&rest _)
                  (ert-fail "Ambiguous member Inbox must not save")))
               ((symbol-function 'org-roam-db-update-file)
                (lambda (&rest _)
                  (ert-fail
                   "Ambiguous member Inbox must not refresh DB"))))
            (let ((result (org-roam-organize-moc-sync)))
              (should (eq (plist-get result :status) 'failed))
              (should
               (string-match-p
                "Multiple direct-child Inboxes"
                (plist-get result :reason)))
              (should
               (string-match-p
                "MOC region note" (plist-get result :reason)))))
          (with-current-buffer (find-file-noselect file)
            (should (equal (buffer-string) before))
            (should-not (buffer-modified-p))))))))

(ert-deftest
    org-roam-organize-test-moc-member-inbox-names-are-region-and-level-local
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((body
          (concat
           "* Parent A\n** Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\n"
           "#+begin_src org\n,*** Inbox\n#+end_src\n"
           "*** COMMENT Inbox\nCommented content\n"
           "*** Inbox\nIdea intro\n**** Child\nChild content\n"
           "*** Manual\n**** Inbox\nFirst deep text\n**** Inbox\nSecond deep text\n"
           "* Parent B\n** Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\n"
           "*** Inbox\nNote intro\n"))
         (file (org-roam-organize-test--write-moc body))
         (before
          (with-temp-buffer
            (insert-file-contents file)
            (buffer-string)))
         (line "#+ROAM_NODE: [[id:shared][Example]]\n")
         (expected
          (concat
           (replace-regexp-in-string (regexp-quote "**** Child\n")
                                     (concat line "**** Child\n")
                                     before
                                     t
                                     t)
           line)))
      (org-roam-organize-test--write-node
       (expand-file-name "shared.org" root)
       "shared"
       "Example"
       '("idea" "note"))
      (should
       (eq (plist-get (org-roam-organize-moc-sync) :status) 'ok))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) expected))
        (let ((layout
               (org-roam-organize--moc-regions
                (org-element-parse-buffer))))
          (dolist (record (org-roam-organize--moc-records))
            (let* ((headline
                    (cdr
                     (assoc
                      (plist-get record :tag)
                      (plist-get layout :regions))))
                   (inbox
                    (org-roam-organize--moc-region-inbox
                     headline record)))
              (should (= (org-element-property :level inbox) 3))
              (should
               (equal
                (mapcar
                 (lambda (entry) (plist-get entry :id))
                 (plist-get
                  (org-roam-organize--parse-id-link-keyword-entries-in-tree
                   inbox "ROAM_NODE")
                  :entries))
                '("shared")))))))
      (should-not (plist-get (org-roam-organize-moc-sync) :saved)))))

(ert-deftest
    org-roam-organize-test-moc-member-inbox-is-not-created-without-missing-members
    ()
  (org-roam-organize-test--with-moc
    (let*
        ((file
          (org-roam-organize-test--write-moc
           "* Idea\n:PROPERTIES:\n:CUSTOM_ID: idea\n:END:\nManual idea\n* Note\n:PROPERTIES:\n:CUSTOM_ID: note\n:END:\nManual note\n"))
         (before
          (with-temp-buffer
            (insert-file-contents file)
            (buffer-string))))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _)
                   (ert-fail "No missing members must not save"))))
        (let ((result (org-roam-organize-moc-sync)))
          (should (eq (plist-get result :status) 'ok))
          (should-not (plist-get result :saved))))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) before))
        (should-not (buffer-modified-p))))))

(provide 'org-roam-organize-test)
;;; org-roam-organize-test.el ends here
