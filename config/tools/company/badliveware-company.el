;;; badliveware-company.el --- -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:
(require 'use-package)
(require 'all-the-icons)

(use-package company
  :bind
  (:map company-active-map
    ("RET" . nil)
    ([return] . nil)
    ("TAB" . company-complete-selection)
    ([tab] . company-complete-selection)
    ("<right>" . company-complete-common))
  :hook
  (after-init . global-company-mode)
  :init
  (setq company-minimum-prefix-length 2
        company-tooltip-limit 14
        company-dabbrev-downcase nil
        company-dabbrev-ignore-case nil
        company-dabbrev-code-other-buffers t
        company-tooltip-align-annotations t
        company-require-match 'never
        company-global-modes
        '(not erc-mode message-mode help-mode gud-mode eshell-mode)
        company-backends '(company-capf)
        company-frontends
        '(company-pseudo-tooltip-frontend
          company-echo-metadata-frontend))
  :config
  (with-eval-after-load 'evil (add-hook 'company-mode-hook #'evil-normalize-keymaps))
  (defun +company*abort-previous (&rest _) (company-abort))
  (advice-add #'company-begin-backend :before #'+company*abort-previous)
  (global-company-mode +1))

(use-package company-box
  :hook (company-mode . company-box-mode)
  :config
  (setq company-box-show-single-candidate t
        company-box-backends-colors nil
        company-box-max-candidates 50
        company-box-icons-alist 'company-box-icons-all-the-icons
        company-box-icons-functions
        '(+company-box-icons--yasnippet company-box-icons--lsp +company-box-icons--elisp company-box-icons--acphp))
        ;; company-box-icons-all-the-icons
        ;; `((Unknown       . ,(all-the-icons-material "find_in_page"             :height 0.8 :face 'all-the-icons-purple))
        ;;   (Text          . ,(all-the-icons-material "text_fields"              :height 0.8 :face 'all-the-icons-green))
        ;;   (Method        . ,(all-the-icons-material "functions"                :height 0.8 :face 'all-the-icons-red))
        ;;   (Function      . ,(all-the-icons-material "functions"                :height 0.8 :face 'all-the-icons-red))
        ;;   (Constructor   . ,(all-the-icons-material "functions"                :height 0.8 :face 'all-the-icons-red))
        ;;   (Field         . ,(all-the-icons-material "functions"                :height 0.8 :face 'all-the-icons-red))
        ;;   (Variable      . ,(all-the-icons-material "adjust"                   :height 0.8 :face 'all-the-icons-blue))
        ;;   (Class         . ,(all-the-icons-material "class"                    :height 0.8 :face 'all-the-icons-red))
        ;;   (Interface     . ,(all-the-icons-material "settings_input_component" :height 0.8 :face 'all-the-icons-red))
        ;;   (Module        . ,(all-the-icons-material "view_module"              :height 0.8 :face 'all-the-icons-red))
        ;;   (Property      . ,(all-the-icons-material "settings"                 :height 0.8 :face 'all-the-icons-red))
        ;;   (Unit          . ,(all-the-icons-material "straighten"               :height 0.8 :face 'all-the-icons-red))
        ;;   (Value         . ,(all-the-icons-material "filter_1"                 :height 0.8 :face 'all-the-icons-red))
        ;;   (Enum          . ,(all-the-icons-material "plus_one"                 :height 0.8 :face 'all-the-icons-red))
        ;;   (Keyword       . ,(all-the-icons-material "filter_center_focus"      :height 0.8 :face 'all-the-icons-red))
        ;;   (Snippet       . ,(all-the-icons-material "short_text"               :height 0.8 :face 'all-the-icons-red))
        ;;   (Color         . ,(all-the-icons-material "color_lens"               :height 0.8 :face 'all-the-icons-red))
        ;;   (File          . ,(all-the-icons-material "insert_drive_file"        :height 0.8 :face 'all-the-icons-red))
        ;;   (Reference     . ,(all-the-icons-material "collections_bookmark"     :height 0.8 :face 'all-the-icons-red))
        ;;   (Folder        . ,(all-the-icons-material "folder"                   :height 0.8 :face 'all-the-icons-red))
        ;;   (EnumMember    . ,(all-the-icons-material "people"                   :height 0.8 :face 'all-the-icons-red))
        ;;   (Constant      . ,(all-the-icons-material "pause_circle_filled"      :height 0.8 :face 'all-the-icons-red))
        ;;   (Struct        . ,(all-the-icons-material "streetview"               :height 0.8 :face 'all-the-icons-red))
        ;;   (Event         . ,(all-the-icons-material "event"                    :height 0.8 :face 'all-the-icons-red))
        ;;   (Operator      . ,(all-the-icons-material "control_point"            :height 0.8 :face 'all-the-icons-red))
        ;;   (TypeParameter . ,(all-the-icons-material "class"                    :height 0.8 :face 'all-the-icons-red))
        ;;   ;; (Template   . ,(company-box-icons-image "Template.png"))))
        ;;   (Yasnippet     . ,(all-the-icons-material "short_text"               :height 0.8 :face 'all-the-icons-green))
        ;;   (ElispFunction . ,(all-the-icons-material "functions"                :height 0.8 :face 'all-the-icons-red))
        ;;   (ElispVariable . ,(all-the-icons-material "check_circle"             :height 0.8 :face 'all-the-icons-blue))
        ;;   (ElispFeature  . ,(all-the-icons-material "stars"                    :height 0.8 :face 'all-the-icons-orange))
        ;;   (ElispFace     . ,(all-the-icons-material "format_paint"             :height 0.8 :face 'all-the-icons-pink))))

  (defun +company-box-icons--yasnippet (candidate)
    (when (get-text-property 0 'yas-annotation candidate)
      'Yasnippet))

  (defun +company-box-icons--elisp (candidate)
    (when (derived-mode-p 'emacs-lisp-mode)
      (let ((sym (intern candidate)))
        (cond ((fboundp sym)  'ElispFunction)
              ((boundp sym)   'ElispVariable)
              ((featurep sym) 'ElispFeature)
              ((facep sym)    'ElispFace))))))

(use-package company-prescient
  :hook (company-mode . company-prescient-mode)
  :config
  ;; NOTE prescient config duplicated with `ivy'
  (setq prescient-save-file (concat my/cache-dir "prescient-save.el"))
  (prescient-persist-mode +1))

(provide 'badliveware-company)
;;; badliveware-company.el ends here
