;;; bbdb-vcard.el --- import vCards (RFC2426) into BBDB

;; Copyright (c) 2010 Bert Burgemeister

;; Author: Bert Burgemeister <trebbu@googlemail.com>
;; Keywords: data calendar mail news

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Commentary:
;; 
;; Purpose
;; -------
;; 
;; Import of data from VCARDs as defined in RFC2425 and RFC2426 into
;; The Insidious Big Brother Database (BBDB).
;; 
;; Usage
;; -----
;;
;; On a file, a buffer or a region containing one or more vcards, use
;; `bbdb-vcard-import-file', `bbdb-vcard-import-buffer', or
;; `bbdb-vcard-import-region' respectively to import them into BBDB.
;;
;; There are a few customization variables grouped under `bbdb-vcard'.
;;
;; Installation
;; ------------
;;
;; Implementation
;; --------------
;;
;; An existing BBDB entry is extended by new information from a vcard
;; 
;;   (a) if name and company and an email address match
;;   (b) or if name and company match
;;   (c) or if name and an email address match.
;;
;; Otherwise, a fresh BBDB entry is created.
;;
;; In case (c), if the vcard has ORG defined, this ORG would overwrite
;; an existing Company in BBDB.
;;
;; Any vcard type prefixes (A.ADR:..., B.ADR:... etc.) are stripped
;; off and discarded.
;;
;; For vcard types that have more or less direct counterparts in BBDB,
;; labels and parameters are translated and structured values
;; (lastname; firstname; additional names; prefixes etc.) are
;; converted appropriately with the risk of some (hopefully
;; unessential) information loss. For labels of the vcard types ADR
;; and TEL, translation is defined in bbdb-vcard-translation-table.
;;
;; All remaining vcard types that don't match the regexp in
;; `bbdb-vcard-skip' are stored unaltered in the BBDB Notes alist
;; where, for instance, `TZ;VALUE=text:-05:00' is stored as
;; `(tz\;value=text . "-05:00")'.
;;
;; From the BBDB data fields AKA, Phones, Addresses, Net Addresses,
;; and Notes, duplicates are removed, respectively.
;;
;;
;; Handling of the individual types defined in RFC2426 (assuming
;; default label translation and no vcard type exclusion):
;;
;; "
;; |-------------+----------------+------------------------|
;; | TYPE FROM   | VCARD          | STORAGE IN BBDB        |
;; | VCARD       | PARAMETERS     |                        |
;; |             |                |                        |
;; |-------------+----------------+------------------------|
;; | VERSION     |                | -                      |
;; |-------------+----------------+------------------------|
;; | N           |                | First entry:           |
;; |             |                | Firstname              |
;; |             |                | Lastname               |
;; |             |                |                        |
;; |             |                | Rest:                  |
;; |             |                | AKAs (append)          |
;; |-------------+----------------+------------------------|
;; | FN          |                | AKAs (append)          |
;; | NICKNAME    |                | AKAs (append)          |
;; |-------------+----------------+------------------------|
;; | ORG         |                | First entry:           |
;; |             |                | Company                |
;; |             |                |                        |
;; |             |                | Rest:                  |
;; |             |                | Notes<org              |
;; |             |                | (repeatedly)           |
;; |-------------+----------------+------------------------|
;; | ADR         | ;TYPE=x,HOME,y | Addresses<Home         |
;; |             | ;TYPE=x,WORK,y | Addresses<Office       |
;; |             | ;TYPE=x,y,z    | Addresses<x,y,z        |
;; |             | (none)         | Addresses<Office       |
;; |-------------+----------------+------------------------|
;; | TEL         | ;TYPE=x,HOME,y | Phones<Home (append)   |
;; |             | ;TYPE=x,WORK,y | Phones<Office (append) |
;; |             | ;TYPE=x,CELL,y | Phones<Mobile (append) |
;; |             | ;TYPE=x,y,z    | Phones<x,y,z (append)  |
;; |             | (none)         | Phones<Office (append) |
;; |-------------+----------------+------------------------|
;; | EMAIL       | ;TYPE=x,y,z    | Net-Addresses (append) |
;; | URL         |                | Notes<www              |
;; | BDAY        |                | Notes<anniversary      |
;; |-------------+----------------+------------------------|
;; | NOTE        |                | First time:            |
;; |             |                | Notes<notes            |
;; |             |                |                        |
;; |             |                | Later:                 |
;; |             |                | Notes<vcard-notes      |
;; |-------------+----------------+------------------------|
;; | CATEGORIES  |                | Notes<categories       |
;; | SORT-STRING |                | Notes<sort-string      |
;; | KEY         |                | Notes<key              |
;; | GEO         |                | Notes<geo              |
;; | TZ          |                | Notes<tz               |
;; | PHOTO       |                | Notes<photo            |
;; | LABEL       |                | Notes<label            |
;; | LOGO        |                | Notes<logo             |
;; | SOUND       |                | Notes<sound            |
;; | TITLE       |                | Notes<title            |
;; | ROLE        |                | Notes<role             |
;; | AGENT       |                | Notes<agent            |
;; | MAILER      |                | Notes<mailer           |
;; | UID         |                | Notes<uid              |
;; | PRODID      |                | Notes<prodid           |
;; | CLASS       |                | Notes<class            |
;; | X-foo       |                | Notes<x-foo            |
;; | REV         |                | Notes<rev              |
;; |-------------+----------------+------------------------|
;; | anyJunK     | ;a=x;b=y       | Notes<anyjunk;a=x;b=y  |
;; |-------------+----------------+------------------------|
;; "

;;; Code:

;; Don't mess up our real BBDB yet
(setq bbdb-file "test-bbdb")

(require 'bbdb)
(require 'cl)

;;;; User Variables

(defcustom bbdb-vcard-skip
  ""
  "Regexp describing vcard entry types are to be discarded.
Example: `\"X-GSM-\"'."
  :group 'bbdb-vcard
  :type 'regexp)

(defcustom bbdb-vcard-translation-table
  '(("CELL\\|CAR" . "Mobile")
    ("WORK" . "Office")
    ("^$" . "Office"))    ; acts as a default parameterless ADR or TEL
  "Alist with translations of location labels for addresses and phone
numbers. Cells are (VCARD-LABEL-REGEXP . BBDB-LABEL). One entry should map
a default BBDB label to the empty string (`\"^$\"') which corresponds
to unlabelled vcard entries."
  :group 'bbdb-vcard
  :type '(alist :key-type
                (choice regexp (const :tag "Empty (as default)" "^$"))
                :value-type string))

;;;; User Functions

(defun bbdb-vcard-import-file (vcard-file)
  "Import vcards from VCARD-FILE into BBDB. Existing BBDB entries may
be altered."
  (interactive "fVcard file: ")
  (with-temp-buffer
    (insert-file-contents vcard-file)
    (bbdb-vcard-iterate-vcards (buffer-string) 'bbdb-vcard-process-vcard)))

(defun bbdb-vcard-import-buffer (vcard-buffer)
  "Import vcards from VCARD-BUFFER into BBDB. Existing BBDB entries may
be altered."
  (interactive "bVcard buffer: ")
  (set-buffer vcard-buffer)
  (bbdb-vcard-iterate-vcards (buffer-string) 'bbdb-vcard-process-vcard))

(defun bbdb-vcard-import-region (begin end)
  "Import the vcards between point and mark into BBDB. Existing BBDB
entries may be altered."
  (interactive "d \nm")
  (bbdb-vcard-iterate-vcards (buffer-substring begin end)
                             'bbdb-vcard-process-vcard))

(defgroup bbdb-vcard nil
  "Customizations for vcards"
  :group 'bbdb)

(defun bbdb-vcard-iterate-vcards (vcards vcard-processor)
  "Apply VCARD-PROCESSOR successively to each vcard in string VCARDS"
  (with-temp-buffer
    (insert vcards)
    (goto-char (point-min))
    ;; Change CR into CRLF if necessary, dealing with inconsitent line
    ;; endings.
    (while (re-search-forward "[^]\\(\n\\)" nil t)
      (replace-match "\n" nil nil nil 1))
    (goto-char (point-min))
    (while (re-search-forward "\n\\( \\|\t\\)" nil t)
      (replace-match "")) ; Unfold folded lines.
    (goto-char (point-min))
    (while (re-search-forward
            "^\\([[:alnum:]-]*\\.\\)?*BEGIN:VCARD\\([\n[:print:][:cntrl:]]*?\\)\\(^\\([[:alnum:]-]*\\.\\)?END:VCARD\\)"
            nil t)
      (funcall vcard-processor (match-string 2)))))

(defun bbdb-vcard-process-vcard (entry)
  "Store the vcard ENTRY (BEGIN:VCARD and END:VCARD delimiters stripped off)
in BBDB. Extend existing BBDB entries where possible."
  (with-temp-buffer
    (insert entry)
    (unless
        (string=
         (cdr (assoc "value"
                     (car (bbdb-vcard-entries-of-type "version")))) "3.0")
      (display-warning '(bbdb-vcard xy) "Not a version 3.0 vcard."))
    (let* ((raw-name
            (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "N" t)))))
           ;; Name suitable for storing in BBDB:
           (name
            (bbdb-vcard-unescape-strings (bbdb-vcard-convert-name raw-name)))
           ;; Name to search for in BBDB now:
           (name-to-search-for
            (when raw-name (if (stringp raw-name)
                               raw-name
                             (concat (nth 1 raw-name) ;given name
                                     " .*"
                                     (nth 0 raw-name))))) ; family name
           ;; Additional names from prefixed types like A.N, B.N etc.:
           (other-names
            (mapcar
             (lambda (element)
               (mapconcat 'identity (bbdb-vcard-convert-name
                                     (cdr (assoc "value" element)))
                          " "))
             (bbdb-vcard-entries-of-type "N")))
           (vcard-formatted-names
            (bbdb-vcard-unescape-strings
             (mapcar (lambda (element) (cdr (assoc "value" element)))
                     (bbdb-vcard-entries-of-type "FN"))))
           (vcard-nicknames
            (bbdb-vcard-unescape-strings
             (bbdb-vcard-split-structured-text
              (cdr (assoc "value"
                          (car (bbdb-vcard-entries-of-type "NICKNAME"))))
              "," t)))
           ;; Company suitable for storing in BBDB:
           (vcard-org
            (bbdb-vcard-unescape-strings
             (bbdb-vcard-convert-org
              (cdr (assoc "value"
                          (car (bbdb-vcard-entries-of-type "ORG" t)))))))
           ;; Company to search for in BBDB now:
           (org-to-search-for vcard-org)      ; sorry
           ;; Email suitable for storing in BBDB:
           (vcard-email
            (mapcar (lambda (element) (cdr (assoc "value" element)))
                    (bbdb-vcard-entries-of-type "EMAIL")))
           ;; Email to search for in BBDB now:
           (email-to-search-for
            (when vcard-email (concat "\\("
                                (mapconcat 'identity vcard-email "\\)\\|\\(")
                                "\\)")))
           ;; Phone numbers
           (vcard-tels
            (mapcar (lambda (element)
                      (vector (bbdb-vcard-translate
                               (or (cdr (assoc "type" element)) ""))
                              (cdr (assoc "value" element))))
                    (bbdb-vcard-entries-of-type "TEL")))
           ;; Addresses
           (vcard-adrs
            (mapcar
             (lambda (element)
               (vector (bbdb-vcard-translate
                        (or (cdr (assoc "type" element)) ""))
                       ;; Postbox, Extended, Streets
                       (remove-if (lambda (x) (zerop (length x)))
                                  (subseq (cdr (assoc "value" element)) 0 3))
                       (elt (cdr (assoc "value" element)) 3)   ; City
                       (elt (cdr (assoc "value" element)) 4)   ; State
                       (elt (cdr (assoc "value" element)) 5)   ; Zip
                       (elt (cdr (assoc "value" element)) 6))) ; Country
             (bbdb-vcard-entries-of-type "ADR")))
           (vcard-url
            (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "URL" t)))))
           (vcard-notes (bbdb-vcard-entries-of-type "NOTE"))
           (vcard-bday
            (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "BDAY" t)))))
           ;; The BBDB record to change:
           (record-freshness-info "BBDB record changed:") ; user information
           (bbdb-record
            (or
             ;; Try to find an existing one ...
             ;; (a) try company and net and name:
             (car (and name-to-search-for
                       (bbdb-search
                        (and email-to-search-for
                             (bbdb-search
                              (and org-to-search-for
                                   (bbdb-search (bbdb-records)
                                                nil org-to-search-for))
                              nil nil email-to-search-for))
                        name-to-search-for)))
             ;; (b) try company and name:
             (car (and name-to-search-for
                       (bbdb-search
                        (and org-to-search-for
                             (bbdb-search (bbdb-records)
                                          nil org-to-search-for)))
                       name-to-search-for))
             ;; (c) try net and name; we may change company here:
             (car (and name-to-search-for
                       (bbdb-search
                        (and email-to-search-for
                             (bbdb-search (bbdb-records)
                                          nil nil email-to-search-for))
                        name-to-search-for)))
             ;; No existing record found; make a fresh one:
             (let ((fresh-record (make-vector bbdb-record-length nil)))
               (bbdb-record-set-cache fresh-record
                                      (make-vector bbdb-cache-length nil))
               (bbdb-invoke-hook 'bbdb-create-hook fresh-record)
               (setq record-freshness-info "BBDB record added:") ; for user information
               fresh-record)))
           (bbdb-akas (when bbdb-record (bbdb-record-aka bbdb-record)))
           (bbdb-addresses (when bbdb-record
                             (bbdb-record-addresses bbdb-record)))
           (bbdb-phones (when bbdb-record
                          (bbdb-record-phones bbdb-record)))
           (bbdb-nets (when bbdb-record
                        (bbdb-record-net bbdb-record)))
           (bbdb-raw-notes (when bbdb-record
                             (bbdb-record-raw-notes bbdb-record)))
           notes
           other-vcard-type)
      (when name ; which should be the case as N is mandatory in vcard
        (bbdb-record-set-firstname bbdb-record (car name))
        (bbdb-record-set-lastname bbdb-record (cadr name)))
      (bbdb-record-set-aka bbdb-record
                           (reduce (lambda (x y) (union x y :test 'string=))
                                   (list vcard-nicknames
                                         other-names
                                         vcard-formatted-names
                                         bbdb-akas)))
      (when vcard-org (bbdb-record-set-company bbdb-record vcard-org))
      (bbdb-record-set-net bbdb-record
                           (union vcard-email bbdb-nets :test 'string=))
      (bbdb-record-set-addresses bbdb-record
                                 (union vcard-adrs bbdb-addresses :test 'equal))
      (bbdb-record-set-phones bbdb-record
                              (union vcard-tels bbdb-phones :test 'equal))
      ;; prepare bbdb's notes:
      (when vcard-url (push (cons 'www vcard-url) bbdb-raw-notes))
      (when vcard-notes
        ;; Put vcard NOTEs under key 'notes or, if key 'notes already
        ;; exists, under key 'vcard-notes.
        (push (cons (if (assoc 'notes bbdb-raw-notes)
                        'vcard-notes
                      'notes)
                    (bbdb-vcard-unescape-strings
                     (mapconcat (lambda (element)
                                  (cdr (assoc "value" element)))
                                vcard-notes
                                ";\n")))
              bbdb-raw-notes))
      (when vcard-bday
        (push (cons 'anniversary (concat vcard-bday " birthday"))
              bbdb-raw-notes))
      (while (setq other-vcard-type (bbdb-vcard-other-entry))
        (when (and bbdb-vcard-skip
                   (string-match bbdb-vcard-skip
                                 (symbol-name (car other-vcard-type))))
          (push other-vcard-type bbdb-raw-notes)))
      (bbdb-record-set-raw-notes
       bbdb-record
       (remove-duplicates bbdb-raw-notes
                          ;; equal refuses to recognise symbol equality here.
                          :key (lambda (x)
                                 (cons (symbol-name (car x)) (cdr x)))
                          :test 'equal
                          :from-end t))
      (bbdb-change-record bbdb-record t)
      ;; Tell the user what we've done.
      ;; (princ bbdb-record)
      (message "%s %s %s -- %s"
               record-freshness-info
               (bbdb-record-firstname bbdb-record)
               (bbdb-record-lastname bbdb-record)
               (replace-regexp-in-string 
                "\n" "; " (bbdb-record-company bbdb-record))))))

(defun bbdb-vcard-unescape-strings (escaped-strings)
  "Unescape escaped commas and semi-colons in ESCAPED-STRINGS.
ESCAPED-STRINGS may be a string or a sequence of strings."
  (flet ((unescape (x) (replace-regexp-in-string
                        "\\([\\\\]\\)\\(,\\|;\\)" "" x nil nil 1)))
    (if (stringp escaped-strings)
        (unescape escaped-strings)
      (mapcar 'unescape
          escaped-strings))))
  

(defun bbdb-vcard-convert-name (vcard-name)
  "Convert VCARD-NAME (type N) into (FIRSTNAME LASTNAME)."
  (if (stringp vcard-name)              ; unstructured N
      (bbdb-divide-name vcard-name)
    (let ((vcard-name
           (mapcar (lambda (x) (replace-regexp-in-string
                                "[^\\\\]\\(,\\)" " " x nil nil 1))
                   vcard-name)))               ; flatten comma-separated substructure
      (list (concat (nth 3 vcard-name)  ; honorific prefixes
                    (when (nth 3 vcard-name) " ")
                    (nth 1 vcard-name)  ; given name
                    (when (nth 2 vcard-name) " ")
                    (nth 2 vcard-name)) ; additional names
            (concat (nth 0 vcard-name)  ; family name
                    (when (nth 4 vcard-name) " ")
                    (nth 4 vcard-name)))))) ; honorific suffixes

(defun bbdb-vcard-convert-org (vcard-org)
  "Convert VCARD-ORG (type ORG), which may be a list, into a string."
  (if (stringp vcard-org)    ; unstructured ORG, probably non-standard
      vcard-org              ; Company, unit 1, unit 2...
    (mapconcat 'identity vcard-org "\n")))

(defun bbdb-vcard-entries-of-type (type &optional one-is-enough-p)
  "From current buffer containing a single vcard, read and delete the entries
of TYPE. If ONE-IS-ENOUGH-P is t, read and delete only the first entry of
TYPE."
  (goto-char (point-min))
  (let (values parameters read-enough)
    (while
        (and
         (not read-enough)
         (re-search-forward
          (concat
           "^\\([[:alnum:]-]*\\.\\)?\\(" type "\\)\\(;.*\\)?:\\(.*\\)$")
          nil t))
      (goto-char (match-end 2))
      (setq parameters nil)
      (push (cons "value" (bbdb-vcard-split-structured-text
                           (match-string 4) ";")) parameters)
      (while (re-search-forward "\\([^;:=]+\\)=\\([^;:]+\\)"
                                (line-end-position) t)
        (push (cons (downcase (match-string 1))
                    (downcase (match-string 2))) parameters))
      (push parameters values)
      (delete-region (line-end-position 0) (line-end-position))
      (when one-is-enough-p (setq read-enough t)))
    values))

(defun bbdb-vcard-other-entry ()
  "From current buffer containing a single vcard, read and delete the topmost
entry. Return (TYPE . ENTRY)."
  (goto-char (point-min))
  (when (re-search-forward "^\\([[:graph:]]*?\\):\\(.*\\)$" nil t)
    (let ((type (match-string 1))
          (value (match-string 2)))
      (delete-region (match-beginning 0) (match-end 0))
      (cons (make-symbol (downcase type)) value))))

(defun bbdb-vcard-split-structured-text
  (text separator &optional return-always-list-p)
  "Split TEXT at unescaped occurences of SEPARATOR; return parts in a list.
Return text unchanged if there aren't any separators and RETURN-ALWAYS-LIST-P
is nil."
  (when text
    (let ((string-elements
           (split-string
            (replace-regexp-in-string
             (concat "\\\\" separator) (concat "\\\\" separator)
             (replace-regexp-in-string separator (concat "" separator) text))
            (concat "" separator))))
      (if (and (null return-always-list-p)
               (= 1 (length string-elements)))
          (car string-elements)
        string-elements))))

(defun bbdb-vcard-translate (vcard-label)
  "Translate VCARD-LABEL into its bbdb counterpart as
defined in `bbdb-vcard-translation-table'."
  (upcase-initials
   (or (assoc-default vcard-label bbdb-vcard-translation-table 'string-match)
       vcard-label)))

(provide 'bbdb-vcard)

;;; bbdb-vcard.el ends here    
