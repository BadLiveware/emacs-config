;;; badliveware-lib.el -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:
(require 'subr-x)
(require 'cl-lib)
(defun doom--resolve-path-forms (spec &optional directory)
  "Converts a simple nested series of or/and forms into a series of
`file-exists-p' checks.

For example

  (doom--resolve-path-forms
    '(or A (and B C))
    \"~\")

Returns (approximately):

  '(let* ((_directory \"~\")
          (A (expand-file-name A _directory))
          (B (expand-file-name B _directory))
          (C (expand-file-name C _directory)))
     (or (and (file-exists-p A) A)
         (and (if (file-exists-p B) B)
              (if (file-exists-p C) C))))

This is used by `associate!', `file-exists-p!' and `project-file-exists-p!'."
  (declare (pure t) (side-effect-free t))
  (cond ((stringp spec)
         `(let ((--file-- ,(if (file-name-absolute-p spec)
                             spec
                           `(expand-file-name ,spec ,directory))))
            (and (file-exists-p --file--)
                 --file--)))
        ((and (listp spec)
              (memq (car spec) '(or and)))
         `(,(car spec)
           ,@(cl-loop for i in (cdr spec)
                      collect (doom--resolve-path-forms i directory))))
        ((or (symbolp spec)
             (listp spec))
         `(let ((--file-- ,(if (and directory
                                    (or (not (stringp directory))
                                        (file-name-absolute-p directory)))
                               `(expand-file-name ,spec ,directory)
                             spec)))
            (and (file-exists-p --file--)
                 --file--)))
        (spec)))

(defun doom--resolve-hook-forms (hooks)
  "Converts a list of modes into a list of hook symbols.

If a mode is quoted, it is left as is. If the entire HOOKS list is quoted, the
list is returned as-is."
  (declare (pure t) (side-effect-free t))
  (let ((hook-list (doom-enlist (doom-unquote hooks))))
    (if (eq (car-safe hooks) 'quote)
        hook-list
      (cl-loop for hook in hook-list
               if (eq (car-safe hook) 'quote)
               collect (cadr hook)
               else collect (intern (format "%s-hook" (symbol-name hook)))))))

(defun doom--assert-stage-p (stage macro)
  (unless (or (bound-and-true-p byte-compile-current-file)
              ;; Don't complain if we're being evaluated on-the-fly. Since forms
              ;; are often evaluated (by `eval-region') or expanded (by
              ;; macroexpand) in a temp buffer in `emacs-lisp-mode'...
              (eq major-mode 'emacs-lisp-mode))
    (cl-assert (eq stage doom--stage)
               nil
               "Found %s call in non-%s.el file (%s)"
               macro (symbol-name stage)
               (let ((path (FILE!)))
                 (if (file-in-directory-p path doom-emacs-dir)
                     (file-relative-name path doom-emacs-dir)
                   (abbreviate-file-name path))))))


;;
;;; Public library

(defun doom-unquote (exp)
  "Return EXP unquoted."
  (declare (pure t) (side-effect-free t))
  (while (memq (car-safe exp) '(quote function))
    (setq exp (cadr exp)))
  exp)

(defun doom-enlist (exp)
  "Return EXP wrapped in a list, or as-is if already a list."
  (declare (pure t) (side-effect-free t))
  (if (listp exp) exp (list exp)))

(defun doom-keyword-intern (str)
  "Converts STR (a string) into a keyword (`keywordp')."
  (declare (pure t) (side-effect-free t))
  (cl-check-type str string)
  (intern (concat ":" str)))

(defun doom-keyword-name (keyword)
  "Returns the string name of KEYWORD (`keywordp') minus the leading colon."
  (declare (pure t) (side-effect-free t))
  (cl-check-type :test keyword)
  (substring (symbol-name keyword) 1))

(defmacro doom-log (format-string &rest args)
  "Log to *Messages* if `doom-debug-mode' is on.
Does not interrupt the minibuffer if it is in use, but still logs to *Messages*.
Accepts the same arguments as `message'."
  `(when doom-debug-mode
     (let ((inhibit-message (active-minibuffer-window)))
       (message
        ,(concat (propertize "DOOM " 'face 'font-lock-comment-face)
                 (when (bound-and-true-p doom--current-module)
                   (propertize
                    (format "[%s/%s] "
                            (doom-keyword-name (car doom--current-module))
                            (cdr doom--current-module))
                    'face 'warning))
                 format-string)
        ,@args))))

(defun FILE! ()
  "Return the emacs lisp file this macro is called from."
  (cond ((bound-and-true-p byte-compile-current-file))
        (load-file-name)
        (buffer-file-name)
        ((stringp (car-safe current-load-list)) (car current-load-list))))

(defun DIR! ()
  "Returns the directory of the emacs lisp file this macro is called from."
  (let ((file (FILE!)))
    (and file (file-name-directory file))))


;;
;; Macros

(defmacro λ! (&rest body)
  "Expands to (lambda () (interactive) ,@body)."
  (declare (doc-string 1))
  `(lambda () (interactive) ,@body))

(defmacro λ!! (command &optional arg)
  "Expands to a command that interactively calls COMMAND with prefix ARG."
  (declare (doc-string 1))
  `(lambda () (interactive)
     (let ((current-prefix-arg ,arg))
       (call-interactively ,command))))

(defalias 'lambda! 'λ!)
(defalias 'lambda!! 'λ!!)

(defmacro pushnew! (place &rest values)
  "Like `cl-pushnew', but will prepend VALUES to PLACE.
The order VALUES is preserved."
  `(dolist (--value-- (nreverse (list ,@values)))
     (cl-pushnew --value-- ,place)))

(defmacro delq! (elt list &optional fetcher)
  "Delete ELT from LIST in-place."
  `(setq ,list
         (delq ,(if fetcher
                    `(funcall ,fetcher ,elt ,list)
                  elt)
               ,list)))

(defmacro cond! (&rest clauses)
  "An anaphoric `cond', which stores the conditional value in `it'."
  `(let (it)
     (cond ,@(cl-loop for (cond . body) in clauses
                      collect `((setq it ,cond)
                                ,@body)))))

(defmacro defer-until! (condition &rest body)
  "Run BODY when CONDITION is true (checks on `after-load-functions'). Meant to
serve as a predicated alternative to `after!'."
  (declare (indent defun) (debug t))
  `(if ,condition
       (progn ,@body)
     ,(let ((fun (make-symbol "doom|delay-form-")))
        `(progn
           (fset ',fun (lambda (&rest args)
                         (when ,(or condition t)
                           (remove-hook 'after-load-functions #',fun)
                           (unintern ',fun nil)
                           (ignore args)
                           ,@body)))
           (put ',fun 'permanent-local-hook t)
           (add-hook 'after-load-functions #',fun)))))

(defmacro defer-feature! (feature &optional mode)
  "Pretend FEATURE hasn't been loaded yet, until FEATURE-hook is triggered.

Some packages (like `elisp-mode' and `lisp-mode') are loaded immediately at
startup, which will prematurely trigger `after!' (and `with-eval-after-load')
blocks. To get around this we make Emacs believe FEATURE hasn't been loaded yet,
then wait until FEATURE-hook (or MODE-hook, if MODE is provided) is triggered to
reverse this and trigger `after!' blocks at a more reasonable time."
  (let ((advice-fn (intern (format "doom|defer-feature-%s" feature)))
        (mode (or mode feature)))
    `(progn
       (setq features (delq ',feature features))
       (advice-add #',mode :before #',advice-fn)
       (defun ,advice-fn (&rest _)
         ;; Some plugins (like yasnippet) will invoke a mode early to parse
         ;; code, which would prematurely trigger this. In those cases, well
         ;; behaved plugins will use `delay-mode-hooks', which we can check for:
         (when (and ,(intern (format "%s-hook" mode))
                    (not delay-mode-hooks))
           ;; ...Otherwise, announce to the world this package has been loaded,
           ;; so `after!' handlers can react.
           (provide ',feature)
           (advice-remove #',mode #',advice-fn))))))

(defmacro quiet! (&rest forms)
  "Run FORMS without generating any output.

This silences calls to `message', `load-file', `write-region' and anything that
writes to `standard-output'."
  `(cond (noninteractive
          (let ((old-fn (symbol-function 'write-region)))
            (cl-letf ((standard-output (lambda (&rest _)))
                      ((symbol-function 'load-file) (lambda (file) (load file nil t)))
                      ((symbol-function 'message) (lambda (&rest _)))
                      ((symbol-function 'write-region)
                       (lambda (start end filename &optional append visit lockname mustbenew)
                         (unless visit (setq visit 'no-message))
                         (funcall old-fn start end filename append visit lockname mustbenew))))
              ,@forms)))
         ((or doom-debug-mode debug-on-error debug-on-quit)
          ,@forms)
         ((let ((inhibit-message t)
                (save-silently t))
            (prog1 ,@forms (message ""))))))

(defmacro add-transient-hook! (hook-or-function &rest forms)
  "Attaches a self-removing function to HOOK-OR-FUNCTION.

FORMS are evaluated once, when that function/hook is first invoked, then never
again.

HOOK-OR-FUNCTION can be a quoted hook or a sharp-quoted function (which will be
advised)."
  (declare (indent 1))
  (let ((append (if (eq (car forms) :after) (pop forms)))
        (fn (if (symbolp (car forms))
                (intern (format "doom|transient-hook-%s" (pop forms)))
              (make-symbol "doom|transient-hook"))))
    `(let ((sym ,hook-or-function))
       (fset ',fn
             (lambda (&rest _)
               ,@forms
               (let ((sym ,hook-or-function))
                 (cond ((functionp sym) (advice-remove sym #',fn))
                       ((symbolp sym)   (remove-hook sym #',fn))))
               (unintern ',fn nil)))
       (cond ((functionp sym)
              (advice-add ,hook-or-function ,(if append :after :before) #',fn))
             ((symbolp sym)
              (put ',fn 'permanent-local-hook t)
              (add-hook sym #',fn ,append))))))

(defmacro add-hook! (&rest args)
  "A convenience macro for adding N functions to M hooks.

If N and M = 1, there's no benefit to using this macro over `add-hook'.

This macro accepts, in order:

  1. Optional properties :local and/or :append, which will make the hook
     buffer-local or append to the list of hooks (respectively),
  2. The hook(s) to be added to: either an unquoted mode, an unquoted list of
     modes, a quoted hook variable or a quoted list of hook variables. If
     unquoted, '-hook' will be appended to each symbol.
  3. The function(s) to be added: this can be one function, a list thereof, or
     body forms (implicitly wrapped in a closure).

Examples:
    (add-hook! 'some-mode-hook 'enable-something)   (same as `add-hook')
    (add-hook! some-mode '(enable-something and-another))
    (add-hook! '(one-mode-hook second-mode-hook) 'enable-something)
    (add-hook! (one-mode second-mode) 'enable-something)
    (add-hook! :append (one-mode second-mode) 'enable-something)
    (add-hook! :local (one-mode second-mode) 'enable-something)
    (add-hook! (one-mode second-mode) (setq v 5) (setq a 2))
    (add-hook! :append :local (one-mode second-mode) (setq v 5) (setq a 2))

\(fn [:append :local] HOOKS FUNCTIONS)"
  (declare (indent defun) (debug t))
  (let ((hook-fn 'add-hook)
        append-p local-p)
    (while (keywordp (car args))
      (pcase (pop args)
        (:append (setq append-p t))
        (:local  (setq local-p t))
        (:remove (setq hook-fn 'remove-hook))))
    (let ((hooks (doom--resolve-hook-forms (pop args)))
          (funcs
           (let ((val (car args)))
             (if (memq (car-safe val) '(quote function))
                 (if (cdr-safe (cadr val))
                     (cadr val)
                   (list (cadr val)))
               (list args))))
          forms)
      (dolist (fn funcs)
        (setq fn (if (symbolp fn)
                     `(function ,fn)
                   `(lambda (&rest _) ,@args)))
        (dolist (hook hooks)
          (push (if (eq hook-fn 'remove-hook)
                    `(remove-hook ',hook ,fn ,local-p)
                  `(add-hook ',hook ,fn ,append-p ,local-p))
                forms)))
      `(progn ,@(if append-p (nreverse forms) forms)))))

(defmacro remove-hook! (&rest args)
  "A convenience macro for removing N functions from M hooks.

Takes the same arguments as `add-hook!'.

If N and M = 1, there's no benefit to using this macro over `remove-hook'.

\(fn [:append :local] HOOKS FUNCTIONS)"
  (declare (indent defun) (debug t))
  `(add-hook! :remove ,@args))

(defmacro setq-hook! (hooks &rest rest)
  "Sets buffer-local variables on HOOKS.

  (setq-hook! 'markdown-mode-hook
    line-spacing 2
    fill-column 80)

\(fn HOOKS &rest SYM VAL...)"
  (declare (indent 1))
  (unless (= 0 (% (length rest) 2))
    (signal 'wrong-number-of-arguments (list #'evenp (length rest))))
  (let ((vars (let ((args rest)
                    vars)
                (while args
                  (push (symbol-name (car args)) vars)
                  (setq args (cddr args)))
                (string-join (sort vars #'string-lessp) "-"))))
    (macroexp-progn
     (cl-loop for hook in (doom--resolve-hook-forms hooks)
              for mode = (string-remove-suffix "-hook" (symbol-name hook))
              for fn = (intern (format "doom|setq-%s-for-%s" vars mode))
              collect `(fset ',fn
                             (lambda (&rest _)
                               ,@(let (forms)
                                   (while rest
                                     (let ((var (pop rest))
                                           (val (pop rest)))
                                       (push `(setq-local ,var ,val) forms)))
                                   (nreverse forms))))
              collect `(add-hook ',hook #',fn 'append)))))

(defun advice-add! (symbols where functions)
  "Variadic version of `advice-add'.

SYMBOLS and FUNCTIONS can be lists of functions."
  (let ((functions (if (functionp functions)
                       (list functions)
                     functions)))
    (dolist (s (doom-enlist symbols))
      (dolist (f (doom-enlist functions))
        (advice-add s where f)))))

(defun advice-remove! (symbols where-or-fns &optional functions)
  "Variadic version of `advice-remove'.

WHERE-OR-FNS is ignored if FUNCTIONS is provided. This lets you substitute
advice-add with advice-remove and evaluate them without having to modify every
statement."
  (unless functions
    (setq functions where-or-fns
          where-or-fns nil))
  (let ((functions (if (functionp functions)
                       (list functions)
                     functions)))
    (dolist (s (doom-enlist symbols))
      (dolist (f (doom-enlist functions))
        (advice-remove s f)))))

(cl-defmacro associate! (mode &key modes match files when)
  "Enables a minor mode if certain conditions are met.

The available conditions are:

  :modes SYMBOL_LIST
    A list of major/minor modes in which this minor mode may apply.
  :match REGEXP
    A regexp to be tested against the current file path.
  :files SPEC
    Accepts what `project-file-exists-p!' accepts. Checks if certain files or
    directories exist relative to the project root.
  :when FORM
    Whenever FORM returns non-nil."
  (declare (indent 1))
  (unless noninteractive
    (cond ((or files modes when)
           (when (and files
                      (not (or (listp files)
                               (stringp files))))
             (user-error "associate! :files expects a string or list of strings"))
           (let ((hook-name (intern (format "doom--init-mode-%s" mode))))
             `(progn
                (fset ',hook-name
                      (lambda ()
                        (and (fboundp ',mode)
                             (not (bound-and-true-p ,mode))
                             (and buffer-file-name (not (file-remote-p buffer-file-name)))
                             ,(or (not match)
                                  `(if buffer-file-name (string-match-p ,match buffer-file-name)))
                             ,(or (not files)
                                  (doom--resolve-path-forms
                                   (if (stringp (car files)) (cons 'and files) files)
                                   '(doom-project-root)))
                             ,(or when t)
                             (,mode 1))))
                ,@(if (and modes (listp modes))
                      (cl-loop for hook in (doom--resolve-hook-forms modes)
                               collect `(add-hook ',hook #',hook-name))
                    `((add-hook 'after-change-major-mode-hook #',hook-name))))))
          (match
           `(add-to-list 'doom-auto-minor-mode-alist '(,match . ,mode)))
          ((user-error "Invalid `associate!' rules for mode [%s] (:modes %s :match %s :files %s :when %s)"
                       mode modes match files when)))))

(defmacro file-exists-p! (spec &optional directory)
  "Returns non-nil if the files in SPEC all exist.

Returns the last file found to meet the rules set by SPEC. SPEC can be a single
file or a list of forms/files. It understands nested (and ...) and (or ...), as
well.

DIRECTORY is where to look for the files in SPEC if they aren't absolute.

For example:
  (file-exists-p! (or doom-core-dir \"~/.config\" \"some-file\") \"~\")"
  (if directory
      `(let ((--directory-- ,directory))
         ,(doom--resolve-path-forms spec '--directory--))
    (doom--resolve-path-forms spec)))

(defmacro load! (filename &optional path noerror)
  "Load a file relative to the current executing file (`load-file-name').

FILENAME is either a file path string or a form that should evaluate to such a
string at run time. PATH is where to look for the file (a string representing a
directory path). If omitted, the lookup is relative to either `load-file-name',
`byte-compile-current-file' or `buffer-file-name' (checked in that order).

If NOERROR is non-nil, don't throw an error if the file doesn't exist."
  (unless path
    (setq path (or (DIR!)
                   (error "Could not detect path to look for '%s' in"
                          filename))))
  (let ((file (if path `(expand-file-name ,filename ,path) filename)))
    `(condition-case e
         (load ,file ,noerror ,(not doom-debug-mode))
       ((debug doom-error) (signal (car e) (cdr e)))
       ((debug error)
        (let* ((source (file-name-sans-extension ,file))
               (err (cond ((file-in-directory-p source doom-core-dir)
                           (cons 'doom-error doom-core-dir))
                          ((file-in-directory-p source doom-private-dir)
                           (cons 'doom-private-error doom-private-dir))
                          ((cons 'doom-module-error doom-emacs-dir)))))
          (signal (car err)
                  (list (file-relative-name
                         (concat source ".el")
                         (cdr err))
                        e)))))))

(defmacro custom-theme-set-faces! (theme &rest specs)
  "Apply a list of face specs as user customizations for THEME.

THEME can be a single symbol or list thereof. If nil, apply these settings to
all themes. It will apply to all themes once they are loaded.

  (custom-theme-set-faces! '(doom-one doom-one-light)
   `(mode-line :foreground ,(doom-color 'blue))
   `(mode-line-buffer-id :foreground ,(doom-color 'fg) :background \"#000000\")
   '(mode-line-success-highlight :background \"#00FF00\")
   '(org-tag :background \"#4499FF\")
   '(org-ellipsis :inherit org-tag)
   '(which-key-docstring-face :inherit font-lock-comment-face))"
  `(let* ((themes (doom-enlist (or ,theme 'user)))
          (fn (gensym (format "doom|customize-%s-" (mapconcat #'symbol-name themes "-")))))
     (fset fn
           (lambda ()
             (dolist (theme themes)
               (when (or (eq theme 'user)
                         (custom-theme-enabled-p theme))
                 (apply #'custom-theme-set-faces 'user
                        (cl-loop for (face . spec) in (list ,@specs)
                                 if (keywordp (car spec))
                                 collect `(,face ((t ,spec)))
                                 else collect `(,face ,spec)))))))
     (funcall fn)
     (add-hook 'doom-load-theme-hook fn)))

(defmacro custom-set-faces! (&rest specs)
  "Apply a list of face specs as user customizations.

SPECS is a list of face specs.

This is a drop-in replacement for `custom-set-face' that allows for a simplified
face format, e.g.

  (custom-set-faces!
   `(mode-line :foreground ,(doom-color 'blue))
   `(mode-line-buffer-id :foreground ,(doom-color 'fg) :background \"#000000\")
   '(mode-line-success-highlight :background \"#00FF00\")
   '(org-tag :background \"#4499FF\")
   '(org-ellipsis :inherit org-tag)
   '(which-key-docstring-face :inherit font-lock-comment-face))"
  `(custom-theme-set-faces! 'user ,@specs))

              
(defun +evil*fix-dabbrev-in-minibuffer ()
  "Make `try-expand-dabbrev' from `hippie-expand' work in minibuffer. See
`he-dabbrev-beg', so we need to redefine syntax for '/'."
  (set-syntax-table (let* ((table (make-syntax-table)))
                      (modify-syntax-entry ?/ "." table)
                      table)))


(defmacro pushnew! (place &rest values)
  "Like `cl-pushnew', but will prepend VALUES to PLACE.
The order VALUES is preserved."
  `(dolist (--value-- (nreverse (list ,@values)))
     (cl-pushnew --value-- ,place)))


;;;###autoload
(defun doom-fallback-buffer ()
  "Returns the fallback buffer, creating it if necessary. By default this is the
scratch buffer. See `doom-fallback-buffer-name' to change this."
  (let (buffer-list-update-hook)
    (get-buffer-create doom-fallback-buffer-name)))

(defun doom--resolve-path-forms (spec &optional directory)
  "Converts a simple nested series of or/and forms into a series of
`file-exists-p' checks.

For example

  (doom--resolve-path-forms
    '(or A (and B C))
    \"~\")

Returns (approximately):

  '(let* ((_directory \"~\")
          (A (expand-file-name A _directory))
          (B (expand-file-name B _directory))
          (C (expand-file-name C _directory)))
     (or (and (file-exists-p A) A)
         (and (if (file-exists-p B) B)
              (if (file-exists-p C) C))))

This is used by `associate!', `file-exists-p!' and `project-file-exists-p!'."
  (declare (pure t) (side-effect-free t))
  (cond ((stringp spec)
         `(let ((--file-- ,(if (file-name-absolute-p spec)
                             spec
                           `(expand-file-name ,spec ,directory))))
            (and (file-exists-p --file--)
                 --file--)))
        ((and (listp spec)
              (memq (car spec) '(or and)))
         `(,(car spec)
           ,@(cl-loop for i in (cdr spec)
                      collect (doom--resolve-path-forms i directory))))
        ((or (symbolp spec)
             (listp spec))
         `(let ((--file-- ,(if (and directory
                                    (or (not (stringp directory))
                                        (file-name-absolute-p directory)))
                               `(expand-file-name ,spec ,directory)
                             spec)))
            (and (file-exists-p --file--)
                 --file--)))
        (spec)))


(defmacro file-exists-p! (spec &optional directory)
  "Returns non-nil if the files in SPEC all exist.

Returns the last file found to meet the rules set by SPEC. SPEC can be a single
file or a list of forms/files. It understands nested (and ...) and (or ...), as
well.

DIRECTORY is where to look for the files in SPEC if they aren't absolute.

For example:
  (file-exists-p! (or doom-core-dir \"~/.config\" \"some-file\") \"~\")"
  (if directory
      `(let ((--directory-- ,directory))
         ,(doom--resolve-path-forms spec '--directory--))
    (doom--resolve-path-forms spec)))

(defun FILE! ()
  "Return the emacs lisp file this macro is called from."
  (cond ((bound-and-true-p byte-compile-current-file))
        (load-file-name)
        (buffer-file-name)
        ((stringp (car-safe current-load-list)) (car current-load-list))))

(defun DIR! ()
  "Returns the directory of the emacs lisp file this macro is called from."
  (let ((file (FILE!)))
    (and file (file-name-directory file))))

(defun doom-unquote (exp)
  "Return EXP unquoted."
  (declare (pure t) (side-effect-free t))
  (while (memq (car-safe exp) '(quote function))
    (setq exp (cadr exp)))
  exp)

(defun doom-enlist (exp)
  "Return EXP wrapped in a list, or as-is if already a list."
  (declare (pure t) (side-effect-free t))
  (if (listp exp) exp (list exp)))

(defun doom--resolve-hook-forms (hooks)
  "Converts a list of modes into a list of hook symbols.

If a mode is quoted, it is left as is. If the entire HOOKS list is quoted, the
list is returned as-is."
  (declare (pure t) (side-effect-free t))
  (let ((hook-list (doom-enlist (doom-unquote hooks))))
    (if (eq (car-safe hooks) 'quote)
        hook-list
      (cl-loop for hook in hook-list
               if (eq (car-safe hook) 'quote)
               collect (cadr hook)
               else collect (intern (format "%s-hook" (symbol-name hook)))))))


(defmacro setq-hook! (hooks &rest rest)
  "Sets buffer-local variables on HOOKS.

  (setq-hook! 'markdown-mode-hook
    line-spacing 2
    fill-column 80)

\(fn HOOKS &rest SYM VAL...)"
  (declare (indent 1))
  (unless (= 0 (% (length rest) 2))
    (signal 'wrong-number-of-arguments (list #'evenp (length rest))))
  (let ((vars (let ((args rest)
                    vars)
                (while args
                  (push (symbol-name (car args)) vars)
                  (setq args (cddr args)))
                (string-join (sort vars #'string-lessp) "-"))))
    (macroexp-progn
     (cl-loop for hook in (doom--resolve-hook-forms hooks)
              for mode = (string-remove-suffix "-hook" (symbol-name hook))
              for fn = (intern (format "doom|setq-%s-for-%s" vars mode))
              collect `(fset ',fn
                             (lambda (&rest _)
                               ,@(let (forms)
                                   (while rest
                                     (let ((var (pop rest))
                                           (val (pop rest)))
                                       (push `(setq-local ,var ,val) forms)))
                                   (nreverse forms))))
              collect `(add-hook ',hook #',fn 'append)))))




(defmacro after! (targets &rest body)
  "Evaluate BODY after TARGETS (packages) have loaded.

This is a wrapper around `with-eval-after-load' that:

1. Suppresses warnings for disabled packages at compile-time
2. No-ops for TARGETS that are disabled by the user (via `package!')
3. Supports compound TARGETS statements (see below)

TARGETS is a list of packages in one of these formats:

- An unquoted package symbol (the name of a package)
    (after! helm BODY...)
- An unquoted list of package symbols (i.e. BODY is evaluated once both magit
  and git-gutter have loaded)
    (after! (magit git-gutter) BODY...)
- An unquoted, nested list of compound package lists, using :or/:any and/or
  :and/:all
    (after! (:or package-a package-b ...)  BODY...)
    (after! (:and package-a package-b ...) BODY...)
    (after! (:and package-a (:or package-b package-c) ...) BODY...)

Note that:
- :or and :any are equivalent
- :and and :all are equivalent
- If these are omitted, :and is implied."
  (declare (indent defun) (debug t))
  (unless (and (symbolp targets)
               (memq targets (bound-and-true-p doom-disabled-packages)))
    (list (if (or (not (bound-and-true-p byte-compile-current-file))
                  (dolist (next (doom-enlist targets))
                    (unless (keywordp next)
                      (if (symbolp next)
                          (require next nil :no-error)
                        (load next :no-message :no-error)))))
              #'progn
            #'with-no-warnings)
          (if (symbolp targets)
              `(with-eval-after-load ',targets ,@body)
            (pcase (car-safe targets)
              ((or :or :any)
               (macroexp-progn
                (cl-loop for next in (cdr targets)
                         collect `(after! ,next ,@body))))
              ((or :and :all)
               (dolist (next (cdr targets))
                 (setq body `((after! ,next ,@body))))
               (car body))
              (_ `(after! (:and ,@targets) ,@body)))))))

;;; `map!' macro

(defvar doom-evil-state-alist
  '((?n . normal)
    (?v . visual)
    (?i . insert)
    (?e . emacs)
    (?o . operator)
    (?m . motion)
    (?r . replace)
    (?g . global))
  "A list of cons cells that map a letter to a evil state symbol.")

(defun doom--keyword-to-states (keyword)
  "Convert a KEYWORD into a list of evil state symbols.

For example, :nvi will map to (list 'normal 'visual 'insert). See
`doom-evil-state-alist' to customize this."
  (cl-loop for l across (substring (symbol-name keyword) 1)
           if (cdr (assq l doom-evil-state-alist)) collect it
           else do (error "not a valid state: %s" l)))


;; Register keywords for proper indentation (see `map!')
(put :after        'lisp-indent-function 'defun)
(put :desc         'lisp-indent-function 'defun)
(put :leader       'lisp-indent-function 'defun)
(put :localleader  'lisp-indent-function 'defun)
(put :map          'lisp-indent-function 'defun)
(put :keymap       'lisp-indent-function 'defun)
(put :mode         'lisp-indent-function 'defun)
(put :prefix       'lisp-indent-function 'defun)
(put :prefix-map   'lisp-indent-function 'defun)
(put :unless       'lisp-indent-function 'defun)
(put :when         'lisp-indent-function 'defun)

;; specials
(defvar doom--map-forms nil)
(defvar doom--map-fn nil)
(defvar doom--map-batch-forms nil)
(defvar doom--map-state '(:dummy t))
(defvar doom--map-parent-state nil)
(defvar doom--map-evil-p nil)
(with-eval-after-load 'evil (setq doom--map-evil-p t))

(defun doom-keyword-name (keyword)
  "Returns the string name of KEYWORD (`keywordp') minus the leading colon."
  (declare (pure t) (side-effect-free t))
  (cl-check-type :test keyword)
  (substring (symbol-name keyword) 1))

(defun doom--map-process (rest)
  (let ((doom--map-fn doom--map-fn)
        doom--map-state
        doom--map-forms
        desc)
    (while rest
      (let ((key (pop rest)))
        (cond ((listp key)
               (doom--map-nested nil key))

              ((keywordp key)
               (pcase key
                 (:leader
                  (doom--map-commit)
                  (setq doom--map-fn 'doom--define-leader-key))
                 (:localleader
                  (doom--map-commit)
                  (setq doom--map-fn 'define-localleader-key!))
                 (:after
                  (doom--map-nested (list 'after! (pop rest)) rest)
                  (setq rest nil))
                 (:desc
                  (setq desc (pop rest)))
                 ((or :map :map* :keymap)
                  (doom--map-set :keymaps `(quote ,(doom-enlist (pop rest)))))
                 (:mode
                  (push (cl-loop for m in (doom-enlist (pop rest))
                                 collect (intern (concat (symbol-name m) "-map")))
                        rest)
                  (push :map rest))
                 ((or :when :unless)
                  (doom--map-nested (list (intern (doom-keyword-name key)) (pop rest)) rest)
                  (setq rest nil))
                 (:prefix-map
                  (cl-destructuring-bind (prefix . desc)
                      (doom-enlist (pop rest))
                    (let ((keymap (intern (format "doom-leader-%s-map" desc))))
                      (setq rest
                            (append (list :desc desc prefix keymap
                                          :prefix prefix)
                                    rest))
                      (push `(defvar ,keymap (make-sparse-keymap))
                            doom--map-forms))))
                 (:prefix
                  (cl-destructuring-bind (prefix . desc)
                      (doom-enlist (pop rest))
                    (doom--map-set (if doom--map-fn :infix :prefix)
                                   prefix)
                    (when (stringp desc)
                      (setq rest (append (list :desc desc "" nil) rest)))))
                 (:textobj
                  (let* ((key (pop rest))
                         (inner (pop rest))
                         (outer (pop rest)))
                    (push `(map! (:map evil-inner-text-objects-map ,key ,inner)
                                 (:map evil-outer-text-objects-map ,key ,outer))
                          doom--map-forms)))
                 (_
                  (condition-case _
                      (doom--map-def (pop rest) (pop rest) (doom--keyword-to-states key) desc)
                    (error
                     (error "Not a valid `map!' property: %s" key)))
                  (setq desc nil))))

              ((doom--map-def key (pop rest) nil desc)
               (setq desc nil)))))

    (doom--map-commit)
    (macroexp-progn (nreverse (delq nil doom--map-forms)))))

(defun doom--map-append-keys (prop)
  (let ((a (plist-get doom--map-parent-state prop))
        (b (plist-get doom--map-state prop)))
    (if (and a b)
        `(general--concat nil ,a ,b)
      (or a b))))

(defun doom--map-nested (wrapper rest)
  (doom--map-commit)
  (let ((doom--map-parent-state (doom--map-state)))
    (push (if wrapper
              (append wrapper (list (doom--map-process rest)))
            (doom--map-process rest))
          doom--map-forms)))

(defun doom--map-set (prop &optional value)
  (unless (equal (plist-get doom--map-state prop) value)
    (doom--map-commit))
  (setq doom--map-state (plist-put doom--map-state prop value)))

(defun doom--map-def (key def &optional states desc)
  (when (or (memq 'global states)
            (null states))
    (setq states (cons 'nil (delq 'global states))))
  (when desc
    (let (unquoted)
      (cond ((and (listp def)
                  (keywordp (car-safe (setq unquoted (doom-unquote def)))))
             (setq def (list 'quote (plist-put unquoted :which-key desc))))
            ((setq def (cons 'list
                             (if (and (equal key "")
                                      (null def))
                                 `(:ignore t :which-key ,desc)
                               (plist-put (general--normalize-extended-def def)
                                          :which-key desc))))))))
  (dolist (state states)
    (push (list key def)
          (alist-get state doom--map-batch-forms)))
  t)

(defun doom--map-commit ()
  (when doom--map-batch-forms
    (cl-loop with attrs = (doom--map-state)
             for (state . defs) in doom--map-batch-forms
             if (or doom--map-evil-p (not state))
             collect `(,(or doom--map-fn 'general-define-key)
                       ,@(if state `(:states ',state)) ,@attrs
                       ,@(mapcan #'identity (nreverse defs)))
             into forms
             finally do (push (macroexp-progn forms) doom--map-forms))
    (setq doom--map-batch-forms nil)))

(defun doom--map-state ()
  (let ((plist
         (append (list :prefix (doom--map-append-keys :prefix)
                       :infix  (doom--map-append-keys :infix)
                       :keymaps
                       (append (plist-get doom--map-parent-state :keymaps)
                               (plist-get doom--map-state :keymaps)))
                 doom--map-state
                 nil))
        newplist)
    (while plist
      (let ((key (pop plist))
            (val (pop plist)))
        (when (and val (not (plist-member newplist key)))
          (push val newplist)
          (push key newplist))))
    newplist))

;;
(defmacro map! (&rest rest)
  "A convenience macro for defining keybinds, powered by `general'.

If evil isn't loaded, evil-specific bindings are ignored.

States
  :n  normal
  :v  visual
  :i  insert
  :e  emacs
  :o  operator
  :m  motion
  :r  replace
  :g  global  (binds the key without evil `current-global-map')

  These can be combined in any order, e.g. :nvi will apply to normal, visual and
  insert mode. The state resets after the following key=>def pair. If states are
  omitted the keybind will be global (no emacs state; this is different from
  evil's Emacs state and will work in the absence of `evil-mode').

Properties
  :leader [...]                   an alias for (:prefix doom-leader-key ...)
  :localleader [...]              bind to localleader; requires a keymap
  :mode [MODE(s)] [...]           inner keybinds are applied to major MODE(s)
  :map [KEYMAP(s)] [...]          inner keybinds are applied to KEYMAP(S)
  :keymap [KEYMAP(s)] [...]       same as :map
  :prefix [PREFIX] [...]          set keybind prefix for following keys. PREFIX
                                  can be a cons cell: (PREFIX . DESCRIPTION)
  :prefix-map [PREFIX] [...]      same as :prefix, but defines a prefix keymap
                                  where the following keys will be bound. DO NOT
                                  USE THIS IN YOUR PRIVATE CONFIG.
  :after [FEATURE] [...]          apply keybinds when [FEATURE] loads
  :textobj KEY INNER-FN OUTER-FN  define a text object keybind pair
  :if [CONDITION] [...]
  :when [CONDITION] [...]
  :unless [CONDITION] [...]

  Any of the above properties may be nested, so that they only apply to a
  certain group of keybinds.

Example
  (map! :map magit-mode-map
        :m  \"C-r\" 'do-something           ; C-r in motion state
        :nv \"q\" 'magit-mode-quit-window   ; q in normal+visual states
        \"C-x C-r\" 'a-global-keybind
        :g \"C-x C-r\" 'another-global-keybind  ; same as above

        (:when IS-MAC
         :n \"M-s\" 'some-fn
         :i \"M-o\" (lambda (interactive) (message \"Hi\"))))"
  (doom--map-process rest))

  (provide 'badliveware-lib)
  ;;; badliveware-lib.el ends here
