{
  config,
  lib,
  pkgs,
  ...
}: let
  # Use builtins.path to create a more reliable path reference
  # Adjust this path to point to the actual location of fasm-mode.el
  fasm-mode-path = builtins.path {
    name = "fasm-mode";
    path = ../modules/emacs-files/fasm-mode.el; # Adjust based on your directory structure
  };
in {
  # Rest of your config...
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29;

    extraConfig = ''
       ;; Load required packages early to avoid free variable warnings
       (require 'evil)
       (require 'display-line-numbers)
       (require 'dired)

       ;; Basic UI settings
       (setq ring-bell-function 'ignore
             evil-insert-state-cursor 'box
             initial-buffer-choice t
             display-line-numbers-type 'relative)

       (setq dired-dwim-target t)
       (winner-mode 1)
       (menu-bar-mode 0)
       (tool-bar-mode 0)
       (scroll-bar-mode 0)
       (column-number-mode 1)
       (fringe-mode 0)
       (global-display-line-numbers-mode)
       (set-face-attribute 'default nil :height 170)

       ;; IDO mode
       (ido-mode 1)
       (ido-everywhere 1)

       ;; Backup settings
       (setq-default make-backup-files nil
                     auto-save-default nil
                     compile-command "")

       ;; Compilation functions
       (defun my-compile-without-history ()
         "Run compile command with an empty initial prompt but preserve history."
         (interactive)
         (let ((current-prefix-arg '(4))
               (compilation-read-command t))
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

       (advice-add 'recompile :after
                   (lambda (&rest _)
                     (with-current-buffer "*compilation*"
                       (evil-normal-state))))

       (advice-add 'compile :around
                   (lambda (orig-fun &rest args)
                     (let ((compile-command ""))
                       (apply orig-fun args))))

       (global-set-key [remap compile] 'my-compile-without-history)

       ;; Compilation window settings
      (setq display-buffer-alist
          `((,(rx bos "*compilation*" eos)
              (display-buffer-reuse-window display-buffer-at-bottom)
              (window-height . 0.4)
              (preserve-size . (nil . t))
              (select . t))))


       (setq compilation-finish-functions
             (list (lambda (_buf _str)
                     (let ((win (get-buffer-window "*compilation*")))
                       (when win
                         (select-window win)
                         (evil-normal-state))))))

       ;; Buffer cleanup functions
       (defun my/cleanup-deleted-file-buffers ()
         "Close buffers of files that no longer exist."
         (dolist (buf (buffer-list))
           (let ((filename (buffer-file-name buf)))
             (when (and filename
                        (not (file-exists-p filename)))
               (kill-buffer buf)))))

       ;; Dired create-file helper
       (defun my/dired-create-file (filename)
         "Create a new file in the current dired directory."
         (interactive
          (list (read-string "Create file: " (dired-current-directory))))
         (let* ((filepath (expand-file-name filename (dired-current-directory)))
                (dir (file-name-directory filepath)))
           (when (and (not (file-exists-p dir))
                      (yes-or-no-p (format "Directory %s does not exist. Create it? " dir)))
             (make-directory dir t))
           (when (file-exists-p dir)
             (write-region "" nil filepath)
             (dired-add-file filepath)
             (revert-buffer)
             (dired-goto-file (expand-file-name filepath)))))

       (with-eval-after-load 'dired
         (evil-set-initial-state 'dired-mode 'emacs)  ; This will use Emacs default keybindings
         (define-key dired-mode-map (kbd "%") 'my/dired-create-file)
         (define-key dired-mode-map ":"
           (lambda ()
             (interactive)
             (evil-ex)))
         (define-key dired-mode-map "/" 'evil-search-forward))

       ;; Make sure use-package is available at compile time
       (eval-when-compile
         (require 'use-package))

       ;; Evil
       (use-package evil
         :ensure t
         :init
         ;; Must be set *before* Evil loads
         (setq evil-want-integration t
               evil-want-keybinding nil
               evil-want-C-u-scroll t
               evil-want-C-i-jump t
               evil-undo-system 'undo-tree)
         :config
         ;; Actually enable Evil
         (evil-mode 1)

         ;; Make delete operations use the black hole register
         (evil-define-operator evil-delete-blackhole (beg end type register yank-handler)
           "Delete text from BEG to END using black hole register."
           (interactive "<R><x><y>")
           (evil-delete beg end type ?_ yank-handler))

         ;; Remap d to use black hole register
         (define-key evil-normal-state-map "d" 'evil-delete-blackhole)
         (define-key evil-visual-state-map "d" 'evil-delete-blackhole)

         ;; Evil ex commands
         (evil-ex-define-cmd "Man" 'man)
         (evil-set-initial-state 'Man-mode 'normal)
         (evil-ex-define-cmd "compile" 'my-compile-without-history)
         (evil-ex-define-cmd "recompile" 'my-recompile)

         ;; Evil key bindings
         (evil-define-key '(normal insert) 'global (kbd "C-v") 'evil-paste-after)
         (evil-define-key '(normal insert) 'global (kbd "C-S-v") 'evil-paste-after)
         (evil-define-key 'normal dired-mode-map (kbd "RET") 'dired-find-file))

       ;; Undo-tree
       (use-package undo-tree
         :ensure t
         :config
         (global-undo-tree-mode))

       ;; Direnv
       (use-package direnv
         :ensure t
         :config
         (direnv-mode))

       ;; Gruber-darker theme
       (use-package gruber-darker-theme
         :ensure t
         :config
         (load-theme 'gruber-darker t))

       ;; Zig mode
       (use-package zig-mode
         :ensure t
         :mode ("\\.zig\\'" . zig-mode))

       ;; Nix mode
       (use-package nix-mode
         :ensure t
         :mode ("\\.nix\\'" . nix-mode))

       ;; C# mode
       (use-package csharp-mode
         :ensure t
         :mode ("\\.cs\\'" . csharp-mode))

       ;; FASM Mode configuration
       ;; Add the directory containing fasm-mode.el to load-path
       ;; This is crucial: we need to ensure Emacs can find the file
       (add-to-list 'load-path "~/.emacs.d/lisp/")

       ;; Load fasm-mode only if the file exists
       (if (file-exists-p "~/.emacs.d/lisp/fasm-mode.el")
           (progn
             (require 'fasm-mode)
             ;; Associate .asm files with fasm-mode
             (add-to-list 'auto-mode-alist '("\\.asm\\'" . fasm-mode))
             ;; Setup whitespace handling for fasm-mode
             (add-hook 'fasm-mode-hook
                     (lambda ()
                       ;; Enable whitespace mode
                       (whitespace-mode 1)
                       ;; Delete trailing whitespace on save
                       (add-to-list 'write-file-functions 'delete-trailing-whitespace))))
         (message "Warning: fasm-mode.el not found"))
    '';

    # Install these packages via Nix. Emacs sees them at runtime:
    extraPackages = epkgs:
      with epkgs; [
        direnv
        use-package
        undo-tree
        evil
        gruber-darker-theme
        zig-mode
        nix-mode
      ];
  };

  # Combine both file configurations in the same home.file block
  home.file = {
    # Evil mode early-init overrides (existing)
    ".emacs.d/early-init.el".text = ''
      ;; Disable package.el initialization so use-package can control it
      (setq package-enable-at-startup nil)

      ;; Pre-load Evil settings
      (setq evil-want-integration t
            evil-want-keybinding nil
            evil-want-C-u-scroll t
            evil-want-C-i-jump t
            evil-undo-system 'undo-tree)
    '';

    # Add FASM mode file (new)
    ".emacs.d/lisp/fasm-mode.el".source = fasm-mode-path;
  };
}
