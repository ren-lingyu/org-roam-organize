;;; org-roam-organize-cite-display-test.el --- Citation display tests -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for managed literature UUID presentation in Org buffers.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'oc)
(require 'org-roam-organize)
(require 'org-roam-organize-cite-display)

(defun org-roam-organize-cite-display-test--overlays ()
  "Return live citation display overlays in the current buffer."
  (seq-filter
   (lambda (overlay)
     (and (overlay-buffer overlay)
          (overlay-get overlay 'org-roam-organize-cite-display)))
   org-roam-organize-cite-display--overlays))

(defmacro org-roam-organize-cite-display-test--with-buffer
    (contents nodes &rest body)
  "Evaluate BODY in an Org buffer containing CONTENTS and managed NODES.

NODES is the value returned by a stubbed
`org-roam-organize--nodes-with-tag'.  BODY runs with Org-roam Organize mode
logically enabled and citation display installed in the current buffer."
  (declare (indent 2) (debug (form form body)))
  `(with-temp-buffer
     (insert ,contents)
     (org-mode)
     (let ((org-roam-organize-mode t)
           (org-roam-organize-registry
            '((:name "literature" :tag "ref" :cite t))))
       (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                  (lambda (tag)
                    (should (equal tag "ref"))
                    ,nodes)))
         (add-hook 'org-font-lock-set-keywords-hook
                   #'org-roam-organize-cite-display--font-lock-setup
                   nil
                   t)
         (org-roam-organize-cite-display--refresh-font-lock)
         (font-lock-ensure (point-min) (point-max))
         ,@body))))

(ert-deftest org-roam-organize-cite-display-test-displays-managed-title-only ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a; @plain-key]"
      '((:id "ref-a" :title "Reference A"))
    (let ((overlays (org-roam-organize-cite-display-test--overlays)))
      (should (= (length overlays) 1))
      (let ((overlay (car overlays)))
        (should (equal (overlay-get overlay 'display) "Reference A"))
        (should
         (equal
          (buffer-substring-no-properties
           (overlay-start overlay) (overlay-end overlay))
          "@ref-a"))))
    (should (equal (buffer-string) "[cite:@ref-a; @plain-key]"))))

(ert-deftest org-roam-organize-cite-display-test-preserves-source-and-ast ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite/t:see @ref-a, p. 10]"
      '((:id "ref-a" :title "Reference A"))
    (set-buffer-modified-p nil)
    (font-lock-flush (point-min) (point-max))
    (font-lock-ensure (point-min) (point-max))
    (should-not (buffer-modified-p))
    (should (equal (buffer-string) "[cite/t:see @ref-a, p. 10]"))
    (goto-char (1+ (point-min)))
    (let* ((citation (org-element-context))
           (reference (car (org-cite-get-references citation))))
      (should (eq (org-element-type citation) 'citation))
      (should (equal (org-element-property :key reference) "ref-a")))
    (let ((overlay (car (org-roam-organize-cite-display-test--overlays))))
      (should
       (equal
        (buffer-substring-no-properties
         (overlay-start overlay) (overlay-end overlay))
        "@ref-a")))))

(ert-deftest org-roam-organize-cite-display-test-displays-multiple-references ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a; @ref-b]"
      '((:id "ref-a" :title "Reference A")
        (:id "ref-b" :title "Reference B"))
    (let ((display-values
           (sort
            (mapcar
             (lambda (overlay) (overlay-get overlay 'display))
             (org-roam-organize-cite-display-test--overlays))
            #'string<)))
      (should (equal display-values '("Reference A" "Reference B"))))))

(ert-deftest org-roam-organize-cite-display-test-skips-missing-title ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@missing; @untitled]"
      '((:id "untitled" :title nil))
    (should-not (org-roam-organize-cite-display-test--overlays))))

(ert-deftest org-roam-organize-cite-display-test-refontification-is-idempotent ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a]"
      '((:id "ref-a" :title "Reference A"))
    (should (= (length (org-roam-organize-cite-display-test--overlays)) 1))
    (font-lock-flush (point-min) (point-max))
    (font-lock-ensure (point-min) (point-max))
    (should (= (length (org-roam-organize-cite-display-test--overlays)) 1))))

(ert-deftest org-roam-organize-cite-display-test-edit-removes-stale-overlay ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a]"
      '((:id "ref-a" :title "Reference A"))
    (let ((overlay (car (org-roam-organize-cite-display-test--overlays))))
      (goto-char (1+ (overlay-start overlay)))
      (delete-char 1)
      (should-not (overlay-buffer overlay))
      (should-not (org-roam-organize-cite-display-test--overlays)))))

(ert-deftest org-roam-organize-cite-display-test-cache-and-refresh ()
  (with-temp-buffer
    (insert "[cite:@ref-a]")
    (org-mode)
    (let ((org-roam-organize-mode t)
          (org-roam-organize-registry
           '((:name "literature" :tag "ref" :cite t)))
          (title "First Title")
          (query-count 0))
      (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                 (lambda (_tag)
                   (setq query-count (1+ query-count))
                   (list (list :id "ref-a" :title title)))))
        (add-hook 'org-font-lock-set-keywords-hook
                  #'org-roam-organize-cite-display--font-lock-setup
                  nil
                  t)
        (org-roam-organize-cite-display--refresh-font-lock)
        (font-lock-ensure (point-min) (point-max))
        (should (= query-count 1))
        (font-lock-flush (point-min) (point-max))
        (font-lock-ensure (point-min) (point-max))
        (should (= query-count 1))
        (setq title "Second Title")
        (org-roam-organize-cite-display-refresh)
        (should (= query-count 2))
        (should
         (equal
          (overlay-get
           (car (org-roam-organize-cite-display-test--overlays))
           'display)
          "Second Title"))))))

(ert-deftest org-roam-organize-cite-display-test-setup-and-teardown-lifecycle ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t))))
    (with-temp-buffer
      (insert "[cite:@ref-a]")
      (org-mode)
      (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                 (lambda (_tag)
                   '((:id "ref-a" :title "Reference A")))))
        (unwind-protect
            (progn
              (should (org-roam-organize-cite-display--setup))
              (font-lock-ensure (point-min) (point-max))
              (should
               (= (length
                   (org-roam-organize-cite-display-test--overlays))
                  1))
              (setq org-roam-organize-mode nil)
              (should-not (org-roam-organize-cite-display--teardown))
              (should-not
               (org-roam-organize-cite-display-test--overlays))
              (should-not org-roam-organize-cite-display--title-cache))
          (org-roam-organize-cite-display--teardown))))))

(ert-deftest org-roam-organize-cite-display-test-refresh-preserves-font-lock-state ()
  (let (defaults-called refresh-called)
    (cl-letf (((symbol-function 'org-set-font-lock-defaults)
               (lambda ()
                 (setq defaults-called t)))
              ((symbol-function 'font-lock-refresh-defaults)
               (lambda ()
                 (setq refresh-called t))))
      (let ((font-lock-mode nil))
        (should-not
         (org-roam-organize-cite-display--refresh-font-lock))
        (should defaults-called)
        (should-not refresh-called))
      (setq defaults-called nil
            refresh-called nil)
      (let ((font-lock-mode t))
        (should-not
         (org-roam-organize-cite-display--refresh-font-lock))
        (should defaults-called)
        (should refresh-called)))))

(ert-deftest org-roam-organize-cite-display-test-capabilities-exist ()
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize-cite-display--capability-alist)))
    (ert-info ((cdr result))
      (should (car result)))))

(provide 'org-roam-organize-cite-display-test)
;;; org-roam-organize-cite-display-test.el ends here
