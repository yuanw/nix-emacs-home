;;; example-minor.el --- A mode built from a local file  -*- lexical-binding: t; -*-

;; Version: 0.1
;; Keywords: convenience

;;; Commentary:

;; Stands in for the packages a config keeps outside of nixpkgs.

;;; Code:

;;;###autoload
(define-minor-mode example-minor-mode
  "A minor mode that does nothing at all."
  :lighter " eg"
  :global t)

(provide 'example-minor)
;;; example-minor.el ends here
