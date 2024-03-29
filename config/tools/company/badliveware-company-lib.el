;;; badliveware-company-lib.el -*- lexical-binding: t; -*-
(require 'use-package)


(defvar +company-backend-alist
  '((text-mode company-dabbrev company-yasnippet company-ispell)
    (prog-mode company-capf company-yasnippet)
    (conf-mode company-capf company-dabbrev-code company-yasnippet))
  "An alist matching modes to company backends. The backends for any mode is
built from this.")

(defun set-company-backend! (modes &rest backends)
  "Prepends BACKENDS (in order) to `company-backends' in MODES.

MODES should be one symbol or a list of them, representing major or minor modes.
This will overwrite backends for MODES on consecutive uses.

If the car of BACKENDS is nil, unset the backends for MODES.

Examples:

  (set-company-backend! 'js2-mode
    'company-tide 'company-yasnippet)

  (set-company-backend! 'sh-mode
    '(company-shell :with company-yasnippet))

  (set-company-backend! '(c-mode c++-mode)
    '(:separate company-irony-c-headers company-irony))

  (set-company-backend! 'sh-mode nil)  ; unsets backends for sh-mode"
  (declare (indent defun))
  (dolist (mode (doom-enlist modes))
    (if (null (car backends))
        (setq +company-backend-alist
              (delq (assq mode +company-backend-alist)
                    +company-backend-alist))
      (setf (alist-get mode +company-backend-alist)
            backends))))


;;
;;; Library

(defun +company--backends ()
  (let (backends)
    (let ((mode major-mode)
          (modes (list major-mode)))
      (while (setq mode (get mode 'derived-mode-parent))
        (push mode modes))
      (dolist (mode modes)
        (dolist (backend (append (cdr (assq mode +company-backend-alist))
                                 (default-value 'company-backends)))
          (push backend backends)))
      (delete-dups
       (append (cl-loop for (mode . backends) in +company-backend-alist
                        if (or (eq major-mode mode)  ; major modes
                               (and (boundp mode)
                                    (symbol-value mode))) ; minor modes
                        append backends)
               (nreverse backends))))))


;;
;;; Hooks

(defun +company|init-backends ()
  "Set `company-backends' for the current buffer."
  (if (not company-mode)
      (remove-hook 'change-major-mode-after-body-hook #'+company|init-backends 'local)
    (unless (eq major-mode 'fundamental-mode)
      (setq-local company-backends (+company--backends)))
    (add-hook 'change-major-mode-after-body-hook #'+company|init-backends nil 'local)))

(put '+company|init-backends 'permanent-local-hook t)


;;
;;; Commands

(defun +company-has-completion-p ()
  "Return non-nil if a completion candidate exists at point."
  (and (company-manual-begin)
       (= company-candidates-length 1)))

(defun +company/toggle-auto-completion ()
  "Toggle as-you-type code completion."
  (interactive)
  (require 'company)
  (setq company-idle-delay (unless company-idle-delay 0.2))
  (message "Auto completion %s"
           (if company-idle-delay "enabled" "disabled")))

(defun +company/complete ()
  "Bring up the completion popup. If only one result, complete it."
  (interactive)
  (require 'company)
  (when (ignore-errors
          (/= (point)
              (cdr (bounds-of-thing-at-point 'symbol))))
    (save-excursion (insert " ")))
  (when (and (company-manual-begin)
             (= company-candidates-length 1))
    (company-complete-common)))

(defun +company/dabbrev ()
  "Invokes `company-dabbrev-code' in prog-mode buffers and `company-dabbrev'
everywhere else."
  (interactive)
  (call-interactively
   (if (derived-mode-p 'prog-mode)
       #'company-dabbrev-code
     #'company-dabbrev)))

(defun +company/whole-lines (command &optional arg &rest ignored)
  "`company-mode' completion backend that completes whole-lines, akin to vim's
C-x C-l."
  (interactive (list 'interactive))
  (require 'company)
  (pcase command
    (`interactive (company-begin-backend '+company/whole-lines))
    (`prefix      (company-grab-line "^[\t\s]*\\(.+\\)" 1))
    (`candidates
     (all-completions
      arg
      (split-string
       (replace-regexp-in-string
        "^[\t\s]+" ""
        (concat (buffer-substring-no-properties (point-min) (line-beginning-position))
                (buffer-substring-no-properties (line-end-position) (point-max))))
       "\\(\r\n\\|[\n\r]\\)" t)))))

(defun +company/dict-or-keywords ()
  "`company-mode' completion combining `company-dict' and `company-keywords'."
  (interactive)
  (require 'company-dict)
  (require 'company-keywords)
  (let ((company-backends '((company-keywords company-dict))))
    (call-interactively #'company-complete)))

(defun +company/dabbrev-code-previous ()
  "TODO"
  (interactive)
  (require 'company-dabbrev)
  (let ((company-selection-wrap-around t))
    (call-interactively #'+company/dabbrev)
    (company-select-previous-or-abort)))


(provide 'badliveware-company-lib)
;;; badliveware-company-lib.el ends here
