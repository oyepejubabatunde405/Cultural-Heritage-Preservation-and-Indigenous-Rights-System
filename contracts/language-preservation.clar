;; Language Preservation Support Contract
;; Supports efforts to maintain endangered languages and cultures

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROJECT-EXISTS (err u301))
(define-constant ERR-PROJECT-NOT-FOUND (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-INSUFFICIENT-FUNDS (err u304))
(define-constant ERR-INVALID-STATUS (err u305))

;; Project Status Constants
(define-constant PROJECT-ACTIVE u1)
(define-constant PROJECT-COMPLETED u2)
(define-constant PROJECT-SUSPENDED u3)
(define-constant PROJECT-CANCELLED u4)

;; Language Status Constants
(define-constant CRITICALLY-ENDANGERED u1)
(define-constant SEVERELY-ENDANGERED u2)
(define-constant DEFINITELY-ENDANGERED u3)
(define-constant VULNERABLE u4)
(define-constant SAFE u5)

;; Data Variables
(define-data-var project-counter uint u0)
(define-data-var total-funding-allocated uint u0)
(define-data-var active-projects uint u0)

;; Data Maps
(define-map language-projects
  { project-id: uint }
  {
    language-name: (string-ascii 100),
    community: principal,
    project-type: (string-ascii 50),
    description: (string-ascii 300),
    funding-requested: uint,
    funding-received: uint,
    start-date: uint,
    expected-duration: uint,
    status: uint,
    speaker-count: uint
  }
)

(define-map language-registry
  { language-name: (string-ascii 100) }
  {
    community: principal,
    endangerment-level: uint,
    speaker-count: uint,
    documentation-status: (string-ascii 100),
    preservation-priority: uint,
    last-updated: uint
  }
)

(define-map project-milestones
  { project-id: uint, milestone-id: uint }
  {
    description: (string-ascii 200),
    target-date: uint,
    completion-date: uint,
    is-completed: bool,
    funding-released: uint
  }
)

(define-map community-projects
  { community: principal }
  { project-ids: (list 20 uint) }
)

(define-map funding-pool
  { pool-id: uint }
  {
    total-amount: uint,
    allocated-amount: uint,
    contributor: principal,
    purpose: (string-ascii 100)
  }
)

;; Public Functions

;; Register endangered language
(define-public (register-language
  (language-name (string-ascii 100))
  (endangerment-level uint)
  (speaker-count uint)
  (documentation-status (string-ascii 100))
  (preservation-priority uint))
  (begin
    (asserts! (> (len language-name) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= endangerment-level u1) (<= endangerment-level u5)) ERR-INVALID-INPUT)
    (asserts! (and (>= preservation-priority u1) (<= preservation-priority u5)) ERR-INVALID-INPUT)

    (map-set language-registry
      { language-name: language-name }
      {
        community: tx-sender,
        endangerment-level: endangerment-level,
        speaker-count: speaker-count,
        documentation-status: documentation-status,
        preservation-priority: preservation-priority,
        last-updated: burn-block-height
      }
    )

    (ok true)
  )
)

;; Create preservation project
(define-public (create-preservation-project
  (language-name (string-ascii 100))
  (project-type (string-ascii 50))
  (description (string-ascii 300))
  (funding-requested uint)
  (expected-duration uint)
  (speaker-count uint))
  (let
    (
      (project-id (+ (var-get project-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (> (len language-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len project-type) u0) ERR-INVALID-INPUT)
    (asserts! (> funding-requested u0) ERR-INVALID-INPUT)
    (asserts! (> expected-duration u0) ERR-INVALID-INPUT)

    ;; Store project information
    (map-set language-projects
      { project-id: project-id }
      {
        language-name: language-name,
        community: tx-sender,
        project-type: project-type,
        description: description,
        funding-requested: funding-requested,
        funding-received: u0,
        start-date: current-block,
        expected-duration: expected-duration,
        status: PROJECT-ACTIVE,
        speaker-count: speaker-count
      }
    )

    ;; Update community's project list
    (let
      (
        (current-list (default-to (list) (get project-ids (map-get? community-projects { community: tx-sender }))))
      )
      (map-set community-projects
        { community: tx-sender }
        { project-ids: (unwrap! (as-max-len? (append current-list project-id) u20) ERR-INVALID-INPUT) }
      )
    )

    ;; Update counters
    (var-set project-counter project-id)
    (var-set active-projects (+ (var-get active-projects) u1))

    (ok project-id)
  )
)

;; Fund preservation project
(define-public (fund-project (project-id uint) (amount uint))
  (let
    (
      (project-info (unwrap! (map-get? language-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (new-funding (+ (get funding-received project-info) amount))
    )
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (is-eq (get status project-info) PROJECT-ACTIVE) ERR-INVALID-STATUS)

    ;; Transfer funds to project community
    (try! (stx-transfer? amount tx-sender (get community project-info)))

    ;; Update project funding
    (map-set language-projects
      { project-id: project-id }
      (merge project-info { funding-received: new-funding })
    )

    ;; Update total funding allocated
    (var-set total-funding-allocated (+ (var-get total-funding-allocated) amount))

    (ok true)
  )
)

;; Add project milestone
(define-public (add-milestone
  (project-id uint)
  (milestone-id uint)
  (description (string-ascii 200))
  (target-date uint))
  (let
    (
      (project-info (unwrap! (map-get? language-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get community project-info)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> target-date burn-block-height) ERR-INVALID-INPUT)

    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        description: description,
        target-date: target-date,
        completion-date: u0,
        is-completed: false,
        funding-released: u0
      }
    )

    (ok true)
  )
)

;; Complete milestone
(define-public (complete-milestone (project-id uint) (milestone-id uint) (funding-to-release uint))
  (let
    (
      (project-info (unwrap! (map-get? language-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (milestone-info (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get community project-info)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get is-completed milestone-info)) ERR-INVALID-STATUS)

    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone-info {
        completion-date: burn-block-height,
        is-completed: true,
        funding-released: funding-to-release
      })
    )

    (ok true)
  )
)

;; Update project status
(define-public (update-project-status (project-id uint) (new-status uint))
  (let
    (
      (project-info (unwrap! (map-get? language-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get community project-info)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u4)) ERR-INVALID-STATUS)

    ;; Update active projects counter
    (if (and (is-eq (get status project-info) PROJECT-ACTIVE) (not (is-eq new-status PROJECT-ACTIVE)))
      (var-set active-projects (- (var-get active-projects) u1))
      (if (and (not (is-eq (get status project-info) PROJECT-ACTIVE)) (is-eq new-status PROJECT-ACTIVE))
        (var-set active-projects (+ (var-get active-projects) u1))
        true
      )
    )

    (map-set language-projects
      { project-id: project-id }
      (merge project-info { status: new-status })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get project information
(define-read-only (get-project-info (project-id uint))
  (map-get? language-projects { project-id: project-id })
)

;; Get language information
(define-read-only (get-language-info (language-name (string-ascii 100)))
  (map-get? language-registry { language-name: language-name })
)

;; Get milestone information
(define-read-only (get-milestone-info (project-id uint) (milestone-id uint))
  (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Get community projects
(define-read-only (get-community-projects (community principal))
  (map-get? community-projects { community: community })
)

;; Get preservation statistics
(define-read-only (get-preservation-stats)
  {
    total-projects: (var-get project-counter),
    active-projects: (var-get active-projects),
    total-funding: (var-get total-funding-allocated)
  }
)

;; Calculate project progress
(define-read-only (get-project-progress (project-id uint))
  (match (map-get? language-projects { project-id: project-id })
    project-info
    (let
      (
        (funding-progress (if (> (get funding-requested project-info) u0)
          (/ (* (get funding-received project-info) u100) (get funding-requested project-info))
          u0))
      )
      {
        funding-progress: funding-progress,
        is-fully-funded: (>= (get funding-received project-info) (get funding-requested project-info))
      }
    )
    { funding-progress: u0, is-fully-funded: false }
  )
)
