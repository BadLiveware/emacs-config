;;; badliveware-sidebar.el -*- lexical-binding: t; -*-

(require 'use-package)
;; For when you need to go explorin'

(use-package treemacs
    :custom
    (treemacs-follow-after-init t)
    (treemacs-is-never-other-window t)
    (treemacs-sorting 'alphabetic-case-insensitive-desc)
    (treemacs-persist-file (concat my/cache-dir "treemacs-persist"))
    (treemacs-last-error-persist-file (concat my/cache-dir "treemacs-last-error-persist"))
    (doom-themes-treemacs-theme "doom-colors") ; Colorful theme
    :config
    (treemacs-follow-mode +1)
    (with-eval-after-load 'treemacs-persistence
        (setq treemacs--last-error-persist-file
            (concat my/cache-dir
            "treemacs-persist-at-last-error"))))

(use-package treemacs-projectile
    :requires (treemacs projectile)
    :after (treemacs projectile)
    :defer t)

(use-package treemacs-magit
    :requires (treemacs evil)
    :after (treemacs magit)
    :defer t)


(defun +treemacs--init ()
  (require 'treemacs)
  (let ((origin-buffer (current-buffer)))
    (cl-letf (((symbol-function 'treemacs-workspace->is-empty?)
               (symbol-function 'ignore)))
      (treemacs--init))
    (dolist (project (treemacs-workspace->projects (treemacs-current-workspace)))
      (treemacs-do-remove-project-from-workspace project))
    (with-current-buffer origin-buffer
      (let ((project-root (or (doom-project-root) default-directory)))
        (treemacs-do-add-project-to-workspace
         (treemacs--canonical-path project-root)
         (doom-project-name project-root)))
      (setq treemacs--ready-to-follow t)
      (when (or treemacs-follow-after-init treemacs-follow-mode)
        (treemacs--follow)))))

;;;###autoload
(defun +treemacs/toggle ()
  "Initialize or toggle treemacs.

Ensures that only the current project is present and all other projects have
been removed.

Use `treemacs' command for old functionality."
  (interactive)
  (require 'treemacs)
  (pcase (treemacs-current-visibility)
    (`visible (delete-window (treemacs-get-local-window)))
    (_ (+treemacs--init))))

;;;###autoload
(defun +treemacs/find-file (arg)
  "Open treemacs (if necessary) and find current file."
  (interactive "P")
  (let ((origin-buffer (current-buffer)))
    (+treemacs--init)
    (with-current-buffer origin-buffer
      (treemacs-find-file arg))))

(provide 'badliveware-sidebar)
;;; badliveware-sidebar.el ends here
