;; Cultural Artifact Repatriation Contract
;; Facilitates the return of cultural objects to origin communities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-REQUEST-EXISTS (err u201))
(define-constant ERR-REQUEST-NOT-FOUND (err u202))
(define-constant ERR-INVALID-INPUT (err u203))
(define-constant ERR-INVALID-STATUS (err u204))

;; Status Constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-UNDER-REVIEW u2)
(define-constant STATUS-APPROVED u3)
(define-constant STATUS-REJECTED u4)
(define-constant STATUS-COMPLETED u5)

;; Data Variables
(define-data-var request-counter uint u0)
(define-data-var total-requests uint u0)
(define-data-var completed-repatriations uint u0)

;; Data Maps
(define-map repatriation-requests
  { request-id: uint }
  {
    artifact-name: (string-ascii 100),
    current-holder: (string-ascii 100),
    requesting-community: principal,
    cultural-significance: (string-ascii 300),
    evidence-provided: (string-ascii 200),
    request-date: uint,
    status: uint,
    estimated-value: uint
  }
)

(define-map request-negotiations
  { request-id: uint }
  {
    negotiator: principal,
    terms: (string-ascii 300),
    compensation-offered: uint,
    timeline-proposed: uint,
    status: uint
  }
)

(define-map community-requests
  { community: principal }
  { request-ids: (list 50 uint) }
)

(define-map artifact-provenance
  { artifact-name: (string-ascii 100) }
  {
    origin-community: principal,
    historical-context: (string-ascii 300),
    cultural-protocols: (string-ascii 200),
    repatriation-priority: uint
  }
)

;; Public Functions

;; Submit repatriation request
(define-public (submit-repatriation-request
  (artifact-name (string-ascii 100))
  (current-holder (string-ascii 100))
  (cultural-significance (string-ascii 300))
  (evidence-provided (string-ascii 200))
  (estimated-value uint))
  (let
    (
      (request-id (+ (var-get request-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (> (len artifact-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len current-holder) u0) ERR-INVALID-INPUT)
    (asserts! (> (len cultural-significance) u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-value u0) ERR-INVALID-INPUT)

    ;; Store request information
    (map-set repatriation-requests
      { request-id: request-id }
      {
        artifact-name: artifact-name,
        current-holder: current-holder,
        requesting-community: tx-sender,
        cultural-significance: cultural-significance,
        evidence-provided: evidence-provided,
        request-date: current-block,
        status: STATUS-PENDING,
        estimated-value: estimated-value
      }
    )

    ;; Update community's request list
    (let
      (
        (current-list (default-to (list) (get request-ids (map-get? community-requests { community: tx-sender }))))
      )
      (map-set community-requests
        { community: tx-sender }
        { request-ids: (unwrap! (as-max-len? (append current-list request-id) u50) ERR-INVALID-INPUT) }
      )
    )

    ;; Update counters
    (var-set request-counter request-id)
    (var-set total-requests (+ (var-get total-requests) u1))

    (ok request-id)
  )
)

;; Update request status
(define-public (update-request-status (request-id uint) (new-status uint))
  (let
    (
      (request-info (unwrap! (map-get? repatriation-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get requesting-community request-info))) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u5)) ERR-INVALID-STATUS)

    (map-set repatriation-requests
      { request-id: request-id }
      (merge request-info { status: new-status })
    )

    ;; Update completed count if status is completed
    (if (is-eq new-status STATUS-COMPLETED)
      (var-set completed-repatriations (+ (var-get completed-repatriations) u1))
      true
    )

    (ok true)
  )
)

;; Submit negotiation terms
(define-public (submit-negotiation-terms
  (request-id uint)
  (terms (string-ascii 300))
  (compensation-offered uint)
  (timeline-proposed uint))
  (let
    (
      (request-info (unwrap! (map-get? repatriation-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
    )
    (asserts! (> (len terms) u0) ERR-INVALID-INPUT)
    (asserts! (> timeline-proposed u0) ERR-INVALID-INPUT)

    (map-set request-negotiations
      { request-id: request-id }
      {
        negotiator: tx-sender,
        terms: terms,
        compensation-offered: compensation-offered,
        timeline-proposed: timeline-proposed,
        status: STATUS-UNDER-REVIEW
      }
    )

    ;; Update request status to under review
    (map-set repatriation-requests
      { request-id: request-id }
      (merge request-info { status: STATUS-UNDER-REVIEW })
    )

    (ok true)
  )
)

;; Accept negotiation terms
(define-public (accept-negotiation-terms (request-id uint))
  (let
    (
      (request-info (unwrap! (map-get? repatriation-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (negotiation-info (unwrap! (map-get? request-negotiations { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get requesting-community request-info)) ERR-NOT-AUTHORIZED)

    ;; Update request status to approved
    (map-set repatriation-requests
      { request-id: request-id }
      (merge request-info { status: STATUS-APPROVED })
    )

    ;; Update negotiation status
    (map-set request-negotiations
      { request-id: request-id }
      (merge negotiation-info { status: STATUS-APPROVED })
    )

    (ok true)
  )
)

;; Register artifact provenance
(define-public (register-artifact-provenance
  (artifact-name (string-ascii 100))
  (historical-context (string-ascii 300))
  (cultural-protocols (string-ascii 200))
  (repatriation-priority uint))
  (begin
    (asserts! (> (len artifact-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len historical-context) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= repatriation-priority u1) (<= repatriation-priority u5)) ERR-INVALID-INPUT)

    (map-set artifact-provenance
      { artifact-name: artifact-name }
      {
        origin-community: tx-sender,
        historical-context: historical-context,
        cultural-protocols: cultural-protocols,
        repatriation-priority: repatriation-priority
      }
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get request information
(define-read-only (get-request-info (request-id uint))
  (map-get? repatriation-requests { request-id: request-id })
)

;; Get negotiation information
(define-read-only (get-negotiation-info (request-id uint))
  (map-get? request-negotiations { request-id: request-id })
)

;; Get community requests
(define-read-only (get-community-requests (community principal))
  (map-get? community-requests { community: community })
)

;; Get artifact provenance
(define-read-only (get-artifact-provenance (artifact-name (string-ascii 100)))
  (map-get? artifact-provenance { artifact-name: artifact-name })
)

;; Get total statistics
(define-read-only (get-repatriation-stats)
  {
    total-requests: (var-get total-requests),
    completed-repatriations: (var-get completed-repatriations),
    success-rate: (if (> (var-get total-requests) u0)
      (/ (* (var-get completed-repatriations) u100) (var-get total-requests))
      u0)
  }
)

;; Check request status
(define-read-only (get-request-status (request-id uint))
  (match (map-get? repatriation-requests { request-id: request-id })
    request-info (get status request-info)
    u0
  )
)
