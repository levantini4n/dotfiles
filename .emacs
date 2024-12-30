;; I can't even begin to believe that people use doom emacs by the way
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                        ("org" . "https://orgmode.org/elpa/")
                        ("gnu" . "https://elpa.gnu.org/packages/")))
(package-initialize)

(require 'use-package)
(setq use-package-always-ensure t)  ; Auto-install packages

(setq ring-bell-function 'ignore)   
(setq evil-insert-state-cursor 'box)
(menu-bar-mode 0)
(tool-bar-mode 0)
(scroll-bar-mode 0)
(column-number-mode 1)
(fringe-mode 0)
(global-display-line-numbers-mode)
(setq display-line-numbers-type 'relative)
(setq initial-buffer-choice t)
(set-face-attribute 'default nil :height 170)  

;; Enable ido
(ido-mode 1)
(ido-everywhere 1)

(setq-default
 make-backup-files nil
 auto-save-default nil)

;; Modify compile command to always start with empty prompt
(setq-default compile-command "")

(defun my-compile-without-history ()
  "Run compile command with an empty initial prompt but preserve history."
  (interactive)
  (let ((current-prefix-arg '(4))
        (compilation-read-command t))  ; Always read command
    (setq-default compile-command "")
    (setq compile-command "")
    (call-interactively 'compile)
    (with-current-buffer "*compilation*"
      (evil-normal-state))))

(defun my-recompile ()
  "Recompile and ensure normal mode in compilation buffer."
  (interactive)
  (recompile)
  (with-current-buffer "*compilation*"
    (evil-normal-state)))

;; Advise the standard recompile command
(advice-add 'recompile :after
            (lambda (&rest _)
              (with-current-buffer "*compilation*"
                (evil-normal-state))))

(advice-add 'compile :around
            (lambda (orig-fun &rest args)
              (let ((compile-command ""))
                (apply orig-fun args))))

;; Replace the standard compile command
(global-set-key [remap compile] 'my-compile-without-history)

;; State variable to track window configuration
(defvar my/window-state 'normal
  "Track window state: 'normal or 'maximized")

(defvar my/saved-window-configuration nil
  "Store window configuration when maximizing window")

(defun my/toggle-window ()
  "Toggle current window between normal and maximized states."
  (interactive)
  (if-let ((win (selected-window)))
      (if (eq my/window-state 'normal)
          (progn
            (setq my/saved-window-configuration (current-window-configuration))
            (setq my/window-state 'maximized)
            ;; Save window parameters before changing them
            (let ((window-parameters (window-parameters win)))
              ;; Temporarily remove side window parameters
              (set-window-parameter win 'window-side nil)
              (set-window-parameter win 'window-slot nil)
              (delete-other-windows win)
              ;; Restore original parameters if it was a side window
              (dolist (param window-parameters)
                (set-window-parameter win (car param) (cdr param)))))
        (progn
          (when my/saved-window-configuration
            (set-window-configuration my/saved-window-configuration))
          (setq my/window-state 'normal)))))

;; Compilation window configuration
(setq display-buffer-alist
      `((,(rx bos "*compilation*" eos)
         (display-buffer-in-side-window)
         (side . bottom)
         (slot . 0)
         (window-height . 0.4)
         (preserve-size . (nil . t))
         (dedicated . t)
         (select . t))))

;; Keep focus in compilation window after command finishes
(setq compilation-finish-functions
      (list (lambda (_buf _str)
              (let ((win (get-buffer-window "*compilation*")))
                (when win
                  (select-window win)
                  (evil-normal-state))))))

;; Optional: Prevent other windows from displaying in the compilation window's space
(setq window-sides-slots '(nil nil 1 nil)) ; Only allow one window at bottom

;; Buffer cleanup for deleted files
(defun my/cleanup-deleted-file-buffers ()
  "Close buffers of files that no longer exist."
  (dolist (buf (buffer-list))
    (let ((filename (buffer-file-name buf)))
      (when (and filename
                 (not (file-exists-p filename)))
        (kill-buffer buf)))))

;; Advice dired-do-delete to cleanup buffers after file deletion
(defun my/after-dired-delete-advice (&rest _)
  "Cleanup buffers after dired deletion."
  (my/cleanup-deleted-file-buffers))

(advice-add 'dired-do-delete :after #'my/after-dired-delete-advice)

;; Define function to create a file and optionally create parent directories
(defun my/dired-create-file (filename)
  "Create a new file in the current dired directory.
If parent directories don't exist, offer to create them."
  (interactive
   (list (read-string "Create file: " (dired-current-directory))))
  (let* ((filepath (expand-file-name filename (dired-current-directory)))
         (dir (file-name-directory filepath)))
    
    ;; Check if we need to create parent directories
    (when (and (not (file-exists-p dir))
               (yes-or-no-p (format "Directory %s does not exist. Create it? " dir)))
      (make-directory dir t))
    
    ;; Create the file if parent directory exists
    (when (file-exists-p dir)
      (write-region "" nil filepath)
      (dired-add-file filepath)
      (revert-buffer)
      (dired-goto-file (expand-file-name filepath)))))

;; Add keybinding in dired-mode
(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "%") 'my/dired-create-file)
    (define-key dired-mode-map ":" 'evil-ex)
  (define-key dired-mode-map "/" 'evil-search-forward))

;; Undo-tree configuration
(use-package undo-tree
  :ensure t
  :config
  (global-undo-tree-mode)
  (setq undo-tree-auto-save-history nil))

;; Evil mode configuration
(use-package evil
  :after undo-tree
  :init
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  (setq evil-want-C-u-scroll t)
  (setq evil-want-C-i-jump t)
  (setq evil-undo-system 'undo-tree)
  :config
  (evil-mode 1)
  (evil-set-initial-state 'term-mode 'normal)
  (evil-set-initial-state 'dired-mode 'emacs)

  ;; Define no-copy delete operator that uses black hole register
  (evil-define-operator evil-delete-no-copy (beg end type register yank-handler)
    "Delete text without copying to clipboard."
    :move-point nil
    (evil-delete beg end type ?_ yank-handler))  ; Use black hole register

  ;; Replace default 'd' and 'D' with no-copy versions
  (define-key evil-normal-state-map "d" 'evil-delete-no-copy)
  (define-key evil-normal-state-map "D" 'evil-delete-no-copy-line)
  
  ;; Define the line deletion version
  (evil-define-operator evil-delete-no-copy-line (beg end type register yank-handler)
    "Delete to end of line without copying to clipboard."
    :motion evil-end-of-line
    (evil-delete-no-copy beg end type ?_ yank-handler)))

(with-eval-after-load 'evil
  ;; Add woman and man commands
  (evil-ex-define-cmd "Man" 'man)
  (evil-set-initial-state 'Man-mode 'normal)
  
  ;; Add the :on command for window toggle
  (evil-ex-define-cmd "on" 'my/toggle-window)

  ;; Add the compile and recompile commands
  (evil-ex-define-cmd "compile" 'my-compile-without-history)
  (evil-ex-define-cmd "recompile" 'my-recompile)
  
  (evil-define-key '(normal insert) 'global (kbd "C-v") 'evil-paste-after)
  (evil-define-key '(normal insert) 'global (kbd "C-S-v") 'evil-paste-after)

  (evil-define-key 'normal dired-mode-map
    (kbd "RET") 'dired-find-file))

;; Direnv integration
(use-package direnv
  :config
  (direnv-mode))

;; Theme configuration - placed AFTER package initialization
(use-package gruber-darker-theme
  :ensure t
  :init
  (setq custom-safe-themes t))

;; Load theme after package setup is complete
(with-eval-after-load 'gruber-darker-theme
  (load-theme 'gruber-darker t))

(use-package zig-mode
  :ensure t
  :mode "\\.zig\\'")

(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'")
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(nix-mode zig-mode gruber-darker-theme direnv evil undo-tree)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
