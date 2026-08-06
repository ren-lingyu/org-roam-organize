;;; org-roam-organize-citar-test.el --- Tests for the Citar adapter -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for Org-roam Organize's optional Citar adapter.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'rx)
(require 'org-roam-organize-citar)

(defconst org-roam-organize-citar-test--uuid-a
  "11111111-1111-1111-1111-111111111111"
  "A UUID used by Citar adapter tests.")

(defconst org-roam-organize-citar-test--uuid-b
  "22222222-2222-2222-2222-222222222222"
  "A second UUID used by Citar adapter tests.")

(defmacro org-roam-organize-citar-test--with-adapter-context (&rest body)
  "Evaluate BODY with a valid, enabled citation adapter context.

The context enables `org-roam-organize-mode' dynamically and configures one
managed citation registry record tagged `ref'.  It does not install the Citar
adapter or access the Org-roam database unless BODY does so."
  (declare (indent 0) (debug t))
  `(let ((org-roam-organize-mode t)
         (org-roam-organize-registry
          '((:name "literature" :tag "ref" :cite t))))
     ,@body))

(defmacro org-roam-organize-citar-test--with-database (&rest body)
  "Evaluate BODY with two managed literature nodes in a temporary database.

Create a temporary Org-roam root containing two level-0 nodes tagged `ref'.
Each node has one cite ref and uses the UUID constants defined by this test
suite.  Synchronize a temporary SQLite database before evaluating BODY."
  (declare (indent 0) (debug t))
  `(let* ((root (file-name-as-directory
                 (make-temp-file "org-roam-organize-citar-test-" t)))
          (literature-directory (expand-file-name "literature" root))
          (org-roam-directory root)
          (org-roam-organize-directory root)
          (org-roam-db-location (expand-file-name ".org-roam.db" root))
          (org-id-locations-file
           (expand-file-name ".org-id-locations" root))
          (org-roam-db-update-on-save nil))
     (make-directory literature-directory t)
     (write-region
      (format
       (concat ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @key-a\n"
               ":END:\n"
               "#+TITLE: Reference A\n"
               "#+FILETAGS: :ref:\n")
       org-roam-organize-citar-test--uuid-a)
      nil
      (expand-file-name "reference-a.org" literature-directory)
      nil
      'silent)
     (write-region
      (format
       (concat ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @key-b\n"
               ":END:\n"
               "#+TITLE: Reference B\n"
               "#+FILETAGS: :ref:\n")
       org-roam-organize-citar-test--uuid-b)
      nil
      (expand-file-name "reference-b.org" literature-directory)
      nil
      'silent)
     (org-roam-db-sync)
     ,@body))

(defmacro org-roam-organize-citar-test--should-user-error (regexp form)
  "Assert that FORM signals `user-error' with a message matching REGEXP.

Evaluate FORM once.  Return non-nil when ERT observes the expected error type
and its formatted message matches REGEXP; otherwise signal a test failure."
  (declare (indent 1) (debug (form form)))
  `(let ((error-data (should-error ,form :type 'user-error)))
     (should
      (string-match-p ,regexp (error-message-string error-data)))))

(ert-deftest org-roam-organize-citar-test-requires-organize-mode ()
  (let ((org-roam-organize-mode nil))
    (should-error
     (org-roam-organize-citar--citekeys-to-uuids '("key-a"))
     :type 'user-error)))

(ert-deftest org-roam-organize-citar-test-requires-one-valid-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry nil))
    (org-roam-organize-citar-test--should-user-error
        (rx "No :cite t registry record")
      (org-roam-organize-citar--cite-record-tag)))
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag nil :cite t))))
    (org-roam-organize-citar-test--should-user-error (rx "no valid tag")
      (org-roam-organize-citar--cite-record-tag))))

(ert-deftest org-roam-organize-citar-test-maps-citekeys-to-uuids-in-order ()
  (org-roam-organize-citar-test--with-adapter-context
    (let (query-arguments)
      (cl-letf (((symbol-function 'org-roam-db-query)
                 (lambda (_query &rest arguments)
                   (setq query-arguments arguments)
                   `(("key-b" ,org-roam-organize-citar-test--uuid-b)
                     ("key-a" ,org-roam-organize-citar-test--uuid-a)))))
        (should
         (equal
          (org-roam-organize-citar--citekeys-to-uuids
           '("key-a" "key-b" "key-a"))
          (list org-roam-organize-citar-test--uuid-a
                org-roam-organize-citar-test--uuid-b
                org-roam-organize-citar-test--uuid-a)))
        (should
         (equal query-arguments
                (list "ref" ["key-a" "key-b" "key-a"])))))))

(ert-deftest org-roam-organize-citar-test-database-integration ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (should
       (equal
        (org-roam-organize-citar--citekeys-to-uuids
         '("key-b" "key-a" "key-b"))
        (list org-roam-organize-citar-test--uuid-b
              org-roam-organize-citar-test--uuid-a
              org-roam-organize-citar-test--uuid-b)))
      (should
       (equal
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a
               "ordinary-key"
               org-roam-organize-citar-test--uuid-b))
        '("key-a" "ordinary-key" "key-b")))
      (require 'citar)
      (require 'citar-org)
      (org-roam-organize-citar-teardown)
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (with-temp-buffer
              (org-mode)
              (citar-org-insert-citation '("key-a" "key-b"))
              (should
               (string-match-p
                (rx-to-string
                 `(seq "@" ,org-roam-organize-citar-test--uuid-a))
                (buffer-string)))
              (should
               (string-match-p
                (rx-to-string
                 `(seq "@" ,org-roam-organize-citar-test--uuid-b))
                (buffer-string)))
              (should-not (string-match-p (rx (or "key-a" "key-b"))
                                          (buffer-string))))
            (let (action-keys)
              (cl-letf (((symbol-function 'citar-run-default-action)
                         (lambda (keys)
                           (setq action-keys keys))))
                (with-temp-buffer
                  (org-mode)
                  (insert
                   (format "[cite:@%s]"
                           org-roam-organize-citar-test--uuid-a))
                  (goto-char (point-min))
                  (search-forward org-roam-organize-citar-test--uuid-a)
                  (org-roam-organize-citar-dwim))
                (should (equal action-keys '("key-a"))))))
        (org-roam-organize-citar-teardown)))))

(ert-deftest org-roam-organize-citar-test-rejects-missing-citekey-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No managed literature node for citekey")
        (org-roam-organize-citar--citekeys-to-uuids '("missing"))))))

(ert-deftest org-roam-organize-citar-test-rejects-ambiguous-citekey-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `(("key-a" ,org-roam-organize-citar-test--uuid-a)
                   ("key-a" ,org-roam-organize-citar-test--uuid-b)))))
      (org-roam-organize-citar-test--should-user-error
          (rx "Citekey mapping is ambiguous")
        (org-roam-organize-citar--citekeys-to-uuids '("key-a"))))))

(ert-deftest org-roam-organize-citar-test-maps-uuids-and-preserves-ordinary-keys ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `((,org-roam-organize-citar-test--uuid-b "key-b")
                   (,org-roam-organize-citar-test--uuid-a "key-a")))))
      (should
       (equal
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a
               "ordinary-key"
               org-roam-organize-citar-test--uuid-b))
        '("key-a" "ordinary-key" "key-b"))))))

(ert-deftest org-roam-organize-citar-test-rejects-unmapped-uuid ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No external citekey for managed UUID")
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a))))))

(ert-deftest org-roam-organize-citar-test-rejects-ambiguous-uuid-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `((,org-roam-organize-citar-test--uuid-a "key-a")
                   (,org-roam-organize-citar-test--uuid-a "key-b")))))
      (org-roam-organize-citar-test--should-user-error
          (rx "UUID mapping is ambiguous")
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a))))))

(ert-deftest org-roam-organize-citar-test-filter-insert-args-preserves-tail ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function
                'org-roam-organize-citar--citekeys-to-uuids)
               (lambda (citekeys)
                 (should (equal citekeys '("key-a")))
                 (list org-roam-organize-citar-test--uuid-a))))
      (should
       (equal
        (org-roam-organize-citar--filter-org-insert-args
         '(("key-a") prefix suffix))
        (list (list org-roam-organize-citar-test--uuid-a)
              'prefix
              'suffix))))))

(ert-deftest org-roam-organize-citar-test-filter-selected-key-preserves-shape ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function
                'org-roam-organize-citar--citekeys-to-uuids)
               (lambda (citekeys)
                 (mapcar
                  (lambda (citekey)
                    (if (equal citekey "key-a")
                        org-roam-organize-citar-test--uuid-a
                      org-roam-organize-citar-test--uuid-b))
                  citekeys))))
      (should-not (org-roam-organize-citar--filter-selected-key nil))
      (should
       (equal (org-roam-organize-citar--filter-selected-key "key-a")
              org-roam-organize-citar-test--uuid-a))
      (should
       (equal (org-roam-organize-citar--filter-selected-key
               '("key-a" "key-b"))
              (list org-roam-organize-citar-test--uuid-a
                    org-roam-organize-citar-test--uuid-b)))
      (org-roam-organize-citar-test--should-user-error
          (rx "Unexpected Citar Org selection result")
        (org-roam-organize-citar--filter-selected-key 1)))))

(ert-deftest org-roam-organize-citar-test-dwim-translates-before-action ()
  (org-roam-organize-citar-test--with-adapter-context
    (let (action-keys citation-called)
      (cl-letf (((symbol-function 'citar-key-at-point)
                 (lambda () org-roam-organize-citar-test--uuid-a))
                ((symbol-function 'citar-citation-at-point)
                 (lambda ()
                   (setq citation-called t)
                   nil))
                ((symbol-function
                  'org-roam-organize-citar--uuids-to-citekeys)
                 (lambda (keys)
                   (should
                    (equal keys
                           (list org-roam-organize-citar-test--uuid-a)))
                   '("key-a")))
                ((symbol-function 'citar-run-default-action)
                 (lambda (keys)
                   (setq action-keys keys))))
        (org-roam-organize-citar-dwim)
        (should (equal action-keys '("key-a")))
        (should-not citation-called)))))

(ert-deftest org-roam-organize-citar-test-dwim-rejects-missing-citation ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'citar-key-at-point) (lambda () nil))
              ((symbol-function 'citar-citation-at-point) (lambda () nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No citation keys found")
        (org-roam-organize-citar-dwim)))))

(ert-deftest org-roam-organize-citar-test-runtime-capabilities-exist ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (let ((result
           (org-roam-organize--check-capabilities
            org-roam-organize-citar--capability-alist)))
      (ert-info ((cdr result))
        (should (car result))))))

(ert-deftest org-roam-organize-citar-test-setup-and-teardown-own-global-state ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function)))
      (unwind-protect
          (progn
            (should (org-roam-organize-citar-setup))
            (should (org-roam-organize-citar-setup))
            (should org-roam-organize-citar--installed-p)
            (should
             (advice-member-p
              #'org-roam-organize-citar--filter-org-insert-args
              'citar-org-insert-citation))
            (should
             (advice-member-p
              #'org-roam-organize-citar--filter-selected-key
              'citar-org-select-key))
            (should
             (eq (default-value 'citar-at-point-function)
                 #'org-roam-organize-citar-dwim)))
        (org-roam-organize-citar-teardown))
      (should-not org-roam-organize-citar--installed-p)
      (should-not
       (advice-member-p
        #'org-roam-organize-citar--filter-org-insert-args
        'citar-org-insert-citation))
      (should-not
       (advice-member-p
        #'org-roam-organize-citar--filter-selected-key
        'citar-org-select-key))
      (should
       (eq (default-value 'citar-at-point-function)
           previous-at-point)))))

(ert-deftest org-roam-organize-citar-test-teardown-preserves-later-user-value ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (user-at-point (lambda () 'user-value)))
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (set-default 'citar-at-point-function user-at-point)
            (org-roam-organize-citar-teardown)
            (should
             (eq (default-value 'citar-at-point-function)
                 user-at-point)))
        (org-roam-organize-citar-teardown)
        (set-default 'citar-at-point-function previous-at-point)))))

(ert-deftest org-roam-organize-citar-test-capability-failure-leaves-uninstalled ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function)))
      (cl-letf (((symbol-function 'org-roam-organize--check-capabilities)
                 (lambda (_capabilities)
                   (cons nil "missing test capability"))))
        (org-roam-organize-citar-test--should-user-error
            (rx "capability check failed")
          (org-roam-organize-citar-setup)))
      (should-not org-roam-organize-citar--installed-p)
      (should
       (eq (default-value 'citar-at-point-function)
           previous-at-point)))))

(provide 'org-roam-organize-citar-test)
;;; org-roam-organize-citar-test.el ends here
