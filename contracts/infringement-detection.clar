;; Infringement Detection Contract
;; Monitors unauthorized usage of intellectual property

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_REPORT_NOT_FOUND (err u201))
(define-constant ERR_INVALID_INPUT (err u202))
(define-constant ERR_ALREADY_REPORTED (err u203))

;; Data Variables
(define-data-var next-report-id uint u1)
(define-data-var detection-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map infringement-reports
  { report-id: uint }
  {
    reporter: principal,
    patent-id: uint,
    alleged-infringer: principal,
    evidence-hash: (buff 32),
    description: (string-ascii 1024),
    report-date: uint,
    status: (string-ascii 20),
    severity: (string-ascii 10)
  }
)

(define-map patent-reports
  { patent-id: uint }
  { report-count: uint, report-ids: (list 50 uint) }
)

(define-map infringer-reports
  { infringer: principal }
  { report-count: uint, total-severity-score: uint }
)

(define-map report-evidence
  { report-id: uint }
  {
    evidence-type: (string-ascii 50),
    evidence-url: (string-ascii 256),
    verification-status: (string-ascii 20)
  }
)

;; Public Functions
(define-public (report-infringement
  (patent-id uint)
  (alleged-infringer principal)
  (evidence-hash (buff 32))
  (description (string-ascii 1024))
  (severity (string-ascii 10)))
  (let
    (
      (report-id (var-get next-report-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (> (len description) u0) ERR_INVALID_INPUT)
    (asserts! (not (is-eq tx-sender alleged-infringer)) ERR_INVALID_INPUT)

    ;; Store infringement report
    (map-set infringement-reports
      { report-id: report-id }
      {
        reporter: tx-sender,
        patent-id: patent-id,
        alleged-infringer: alleged-infringer,
        evidence-hash: evidence-hash,
        description: description,
        report-date: current-time,
        status: "pending",
        severity: severity
      }
    )

    ;; Update patent reports
    (let
      (
        (current-patent-data (default-to
          { report-count: u0, report-ids: (list) }
          (map-get? patent-reports { patent-id: patent-id })
        ))
      )
      (map-set patent-reports
        { patent-id: patent-id }
        {
          report-count: (+ (get report-count current-patent-data) u1),
          report-ids: (unwrap-panic (as-max-len?
            (append (get report-ids current-patent-data) report-id) u50))
        }
      )
    )

    ;; Update infringer reports
    (let
      (
        (current-infringer-data (default-to
          { report-count: u0, total-severity-score: u0 }
          (map-get? infringer-reports { infringer: alleged-infringer })
        ))
        (severity-score (if (is-eq severity "high") u3
                        (if (is-eq severity "medium") u2 u1)))
      )
      (map-set infringer-reports
        { infringer: alleged-infringer }
        {
          report-count: (+ (get report-count current-infringer-data) u1),
          total-severity-score: (+ (get total-severity-score current-infringer-data) severity-score)
        }
      )
    )

    ;; Increment report ID counter
    (var-set next-report-id (+ report-id u1))

    (ok report-id)
  )
)

(define-public (update-report-status (report-id uint) (new-status (string-ascii 20)))
  (let
    (
      (report-data (unwrap! (map-get? infringement-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get reporter report-data)) ERR_UNAUTHORIZED)

    (map-set infringement-reports
      { report-id: report-id }
      (merge report-data { status: new-status })
    )

    (ok true)
  )
)

(define-public (add-evidence
  (report-id uint)
  (evidence-type (string-ascii 50))
  (evidence-url (string-ascii 256)))
  (let
    (
      (report-data (unwrap! (map-get? infringement-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get reporter report-data)) ERR_UNAUTHORIZED)

    (map-set report-evidence
      { report-id: report-id }
      {
        evidence-type: evidence-type,
        evidence-url: evidence-url,
        verification-status: "pending"
      }
    )

    (ok true)
  )
)

(define-public (set-detection-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set detection-fee new-fee)
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-infringement-report (report-id uint))
  (map-get? infringement-reports { report-id: report-id })
)

(define-read-only (get-patent-reports (patent-id uint))
  (map-get? patent-reports { patent-id: patent-id })
)

(define-read-only (get-infringer-reports (infringer principal))
  (map-get? infringer-reports { infringer: infringer })
)

(define-read-only (get-report-evidence (report-id uint))
  (map-get? report-evidence { report-id: report-id })
)

(define-read-only (get-detection-fee)
  (var-get detection-fee)
)

(define-read-only (get-next-report-id)
  (var-get next-report-id)
)
