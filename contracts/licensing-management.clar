;; Licensing Management Contract
;; Handles usage permissions and licensing agreements

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_LICENSE_NOT_FOUND (err u301))
(define-constant ERR_INVALID_INPUT (err u302))
(define-constant ERR_LICENSE_EXPIRED (err u303))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u304))

;; Data Variables
(define-data-var next-license-id uint u1)
(define-data-var platform-fee-percentage uint u5) ;; 5%

;; Data Maps
(define-map licenses
  { license-id: uint }
  {
    licensor: principal,
    licensee: principal,
    patent-id: uint,
    license-type: (string-ascii 50),
    fee-amount: uint,
    start-date: uint,
    end-date: uint,
    status: (string-ascii 20),
    terms: (string-ascii 1024)
  }
)

(define-map patent-licenses
  { patent-id: uint }
  { license-count: uint, license-ids: (list 100 uint) }
)

(define-map licensee-licenses
  { licensee: principal }
  { license-count: uint, active-licenses: uint }
)

(define-map license-payments
  { license-id: uint }
  {
    total-paid: uint,
    last-payment-date: uint,
    payment-status: (string-ascii 20)
  }
)

(define-map license-terms
  { license-id: uint }
  {
    usage-restrictions: (string-ascii 512),
    territory: (string-ascii 100),
    exclusivity: bool,
    sublicensing-allowed: bool
  }
)

;; Public Functions
(define-public (create-license
  (patent-id uint)
  (licensee principal)
  (license-type (string-ascii 50))
  (fee-amount uint)
  (duration-days uint)
  (terms (string-ascii 1024)))
  (let
    (
      (license-id (var-get next-license-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (end-time (+ current-time (* duration-days u86400))) ;; seconds in a day
    )
    (asserts! (> fee-amount u0) ERR_INVALID_INPUT)
    (asserts! (> duration-days u0) ERR_INVALID_INPUT)
    (asserts! (not (is-eq tx-sender licensee)) ERR_INVALID_INPUT)

    ;; Store license details
    (map-set licenses
      { license-id: license-id }
      {
        licensor: tx-sender,
        licensee: licensee,
        patent-id: patent-id,
        license-type: license-type,
        fee-amount: fee-amount,
        start-date: current-time,
        end-date: end-time,
        status: "pending",
        terms: terms
      }
    )

    ;; Update patent licenses
    (let
      (
        (current-patent-data (default-to
          { license-count: u0, license-ids: (list) }
          (map-get? patent-licenses { patent-id: patent-id })
        ))
      )
      (map-set patent-licenses
        { patent-id: patent-id }
        {
          license-count: (+ (get license-count current-patent-data) u1),
          license-ids: (unwrap-panic (as-max-len?
            (append (get license-ids current-patent-data) license-id) u100))
        }
      )
    )

    ;; Update licensee licenses
    (let
      (
        (current-licensee-data (default-to
          { license-count: u0, active-licenses: u0 }
          (map-get? licensee-licenses { licensee: licensee })
        ))
      )
      (map-set licensee-licenses
        { licensee: licensee }
        {
          license-count: (+ (get license-count current-licensee-data) u1),
          active-licenses: (get active-licenses current-licensee-data)
        }
      )
    )

    ;; Initialize payment tracking
    (map-set license-payments
      { license-id: license-id }
      {
        total-paid: u0,
        last-payment-date: u0,
        payment-status: "pending"
      }
    )

    ;; Increment license ID counter
    (var-set next-license-id (+ license-id u1))

    (ok license-id)
  )
)

(define-public (accept-license (license-id uint))
  (let
    (
      (license-data (unwrap! (map-get? licenses { license-id: license-id }) ERR_LICENSE_NOT_FOUND))
      (fee-amount (get fee-amount license-data))
      (platform-fee (/ (* fee-amount (var-get platform-fee-percentage)) u100))
      (licensor-amount (- fee-amount platform-fee))
    )
    (asserts! (is-eq tx-sender (get licensee license-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status license-data) "pending") ERR_INVALID_INPUT)

    ;; Transfer payment (simplified - in real implementation would use STX transfer)
    ;; (try! (stx-transfer? fee-amount tx-sender (get licensor license-data)))

    ;; Update license status
    (map-set licenses
      { license-id: license-id }
      (merge license-data { status: "active" })
    )

    ;; Update payment record
    (map-set license-payments
      { license-id: license-id }
      {
        total-paid: fee-amount,
        last-payment-date: (unwrap-panic (get-block-info? time (- block-height u1))),
        payment-status: "paid"
      }
    )

    ;; Update active licenses count
    (let
      (
        (licensee-data (unwrap-panic (map-get? licensee-licenses { licensee: tx-sender })))
      )
      (map-set licensee-licenses
        { licensee: tx-sender }
        (merge licensee-data { active-licenses: (+ (get active-licenses licensee-data) u1) })
      )
    )

    (ok true)
  )
)

(define-public (revoke-license (license-id uint))
  (let
    (
      (license-data (unwrap! (map-get? licenses { license-id: license-id }) ERR_LICENSE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get licensor license-data)) ERR_UNAUTHORIZED)

    (map-set licenses
      { license-id: license-id }
      (merge license-data { status: "revoked" })
    )

    (ok true)
  )
)

(define-public (set-license-terms
  (license-id uint)
  (usage-restrictions (string-ascii 512))
  (territory (string-ascii 100))
  (exclusivity bool)
  (sublicensing-allowed bool))
  (let
    (
      (license-data (unwrap! (map-get? licenses { license-id: license-id }) ERR_LICENSE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get licensor license-data)) ERR_UNAUTHORIZED)

    (map-set license-terms
      { license-id: license-id }
      {
        usage-restrictions: usage-restrictions,
        territory: territory,
        exclusivity: exclusivity,
        sublicensing-allowed: sublicensing-allowed
      }
    )

    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-license (license-id uint))
  (map-get? licenses { license-id: license-id })
)

(define-read-only (get-patent-licenses (patent-id uint))
  (map-get? patent-licenses { patent-id: patent-id })
)

(define-read-only (get-licensee-licenses (licensee principal))
  (map-get? licensee-licenses { licensee: licensee })
)

(define-read-only (get-license-payments (license-id uint))
  (map-get? license-payments { license-id: license-id })
)

(define-read-only (get-license-terms (license-id uint))
  (map-get? license-terms { license-id: license-id })
)

(define-read-only (is-license-active (license-id uint))
  (match (map-get? licenses { license-id: license-id })
    license-data
    (let
      (
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (end-date (get end-date license-data))
        (status (get status license-data))
      )
      (and
        (is-eq status "active")
        (< current-time end-date)
      )
    )
    false
  )
)

(define-read-only (get-next-license-id)
  (var-get next-license-id)
)
