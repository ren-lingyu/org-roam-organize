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

(require 'org-roam-organize-core)
(require 'org-roam-organize-capture)
(require 'org-roam-organize-entry)
(require 'org-roam-organize-moc)
(require 'org-roam-organize-cite)

;; ==============================
;; Minor-Mode
;; ==============================

;; Definition.
;;;###autoload
(define-minor-mode org-roam-organize-mode
  "Toggle Org-roam Organize mode.

When enabled, the mode validates setup, registers backend-independent Org Cite
UUID title display and export, installs managed bibliography discovery and
bundled BibLaTeX export compatibility when the citation record sets
`:bibliography t', and installs the configured interactive citation adapter.
Disabling the mode removes those integrations and the adapter.  Core setup
failure disables the mode again.  Optional citation adapter failure leaves the
mode enabled and reports a warning.  User-facing check and sync commands
display detailed diagnostics in `org-roam-organize--report-buffer-name' when
needed."
  :lighter " Organize"
  :group 'org-roam-organize
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
                    (org-roam-organize--teardown-cite-integration)
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
                          (org-roam-organize--setup-cite-integration)
                          ;; The citation backend is optional.  Its setup
                          ;; failure must not undo successful core mode setup or
                          ;; remove the core citation integration installed
                          ;; above.
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
                       (org-roam-organize--teardown-cite-integration)
                       (message
                        "[WARNING] Org Roam Organize Mode setup failed: %s"
                        (error-message-string err)))))))
              (org-roam-organize--teardown-cite-backend)
              (org-roam-organize--teardown-cite-integration))))

(provide 'org-roam-organize)
;;; org-roam-organize.el ends here
