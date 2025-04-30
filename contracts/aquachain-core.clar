;; AquaChain Water Resource Management - Core Contract
;; This contract manages water rights, allocations, usage tracking, and quota enforcement
;; for community water resources. It serves as the central registry for water management
;; within a community, enabling transparent and accountable resource governance.

;; =========================================================================
;; Error Constants
;; =========================================================================
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-ADMIN (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-NOT-REGISTERED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-QUOTA-EXCEEDED (err u105))
(define-constant ERR-INVALID-SOURCE (err u106))
(define-constant ERR-SOURCE-EXISTS (err u107))
(define-constant ERR-INVALID-ALLOCATION (err u108))
(define-constant ERR-INVALID-USER (err u109))
(define-constant ERR-SOURCE-IN-USE (err u110))

;; =========================================================================
;; Data Maps and Variables
;; =========================================================================

;; Contract administrator(s) authorized to manage the system
(define-map administrators principal bool)

;; Water sources registered in the system
(define-map water-sources 
  uint 
  {
    name: (string-ascii 50),
    location: (string-ascii 100),
    capacity: uint,
    active: bool,
    created-at: uint
  }
)

;; Tracks the next available source ID
(define-data-var next-source-id uint u1)

;; Water rights - associates users with their water rights
(define-map water-rights 
  principal 
  {
    registered: bool,
    total-allocation: uint,        ;; Total allocated in liters
    current-usage: uint,           ;; Current usage in liters
    last-updated: uint,            ;; Block height of last update
    registration-date: uint        ;; Block height of registration
  }
)

;; Usage history for each user
(define-map usage-history 
  { user: principal, period: uint } 
  {
    amount: uint,                  ;; Amount used in liters
    timestamp: uint                ;; Block height when recorded
  }
)

;; Water source allocations - tracks how much each source is allocated to users
(define-map source-allocations 
  { source-id: uint, user: principal } 
  {
    allocation: uint,              ;; Allocation from this source in liters
    active: bool                   ;; Whether this allocation is currently active
  }
)

;; Community-wide allocation and usage
(define-data-var total-community-allocation uint u0)
(define-data-var total-community-usage uint u0)

;; Current allocation period (could be month/season identifier)
(define-data-var current-period uint u1)

;; =========================================================================
;; Private Functions
;; =========================================================================

;; Check if caller is an administrator
(define-private (is-admin)
  (default-to false (map-get? administrators tx-sender))
)

;; Check if a water source exists and is active
(define-private (is-valid-source (source-id uint))
  (match (map-get? water-sources source-id)
    source (get active source)
    false
  )
)

;; Check if a user is registered
(define-private (is-registered-user (user principal))
  (match (map-get? water-rights user)
    rights (get registered rights)
    false
  )
)

;; Update total usage stats
(define-private (update-total-usage (amount uint))
  (begin
    (var-set total-community-usage (+ (var-get total-community-usage) amount))
    (ok true)
  )
)

;; Record usage history for a user in the current period
(define-private (record-usage-history (user principal) (amount uint))
  (map-set usage-history 
    { user: user, period: (var-get current-period) }
    { 
      amount: amount, 
      timestamp: block-height 
    }
  )
)

;; =========================================================================
;; Read-Only Functions
;; =========================================================================

;; Get water source details
(define-read-only (get-water-source (source-id uint))
  (map-get? water-sources source-id)
)

;; Get water rights for a user
(define-read-only (get-water-rights (user principal))
  (map-get? water-rights user)
)

;; Get allocation from a specific source for a user
(define-read-only (get-source-allocation (source-id uint) (user principal))
  (map-get? source-allocations { source-id: source-id, user: user })
)

;; Get usage history for a user in a specific period
(define-read-only (get-usage-history (user principal) (period uint))
  (map-get? usage-history { user: user, period: period })
)

;; Get community-wide stats
(define-read-only (get-community-stats)
  {
    total-allocation: (var-get total-community-allocation),
    total-usage: (var-get total-community-usage),
    current-period: (var-get current-period)
  }
)

;; Get remaining quota for a user
(define-read-only (get-remaining-quota (user principal))
  (match (map-get? water-rights user)
    rights (- (get total-allocation rights) (get current-usage rights))
    u0
  )
)

;; Check if a user is authorized as admin
(define-read-only (check-is-admin (user principal))
  (default-to false (map-get? administrators user))
)

;; =========================================================================
;; Public Functions
;; =========================================================================

;; Initialize contract with first admin (contract deployer)
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
    (map-set administrators tx-sender true)
    (ok true)
  )
)

;; Add a new administrator
(define-public (add-administrator (new-admin principal))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (map-set administrators new-admin true)
    (ok true)
  )
)

;; Remove an administrator
(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (not (is-eq tx-sender admin)) ERR-NOT-AUTHORIZED)
    (map-delete administrators admin)
    (ok true)
  )
)

;; Register a new water source
(define-public (register-water-source (name (string-ascii 50)) (location (string-ascii 100)) (capacity uint))
  (let 
    (
      (source-id (var-get next-source-id))
    )
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (> capacity u0) ERR-INVALID-AMOUNT)
    
    (var-set next-source-id (+ source-id u1))
    
    (map-set water-sources source-id
      {
        name: name,
        location: location,
        capacity: capacity,
        active: true,
        created-at: block-height
      }
    )
    
    (ok source-id)
  )
)

;; Update water source details
(define-public (update-water-source (source-id uint) (name (string-ascii 50)) (location (string-ascii 100)) (capacity uint) (active bool))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (> capacity u0) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? water-sources source-id)) ERR-INVALID-SOURCE)
    
    (map-set water-sources source-id
      {
        name: name,
        location: location,
        capacity: capacity,
        active: active,
        created-at: (get created-at (unwrap-panic (map-get? water-sources source-id)))
      }
    )
    
    (ok true)
  )
)

;; Deactivate a water source
(define-public (deactivate-water-source (source-id uint))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (is-some (map-get? water-sources source-id)) ERR-INVALID-SOURCE)
    
    (map-set water-sources source-id
      (merge (unwrap-panic (map-get? water-sources source-id)) { active: false })
    )
    
    (ok true)
  )
)

;; Register a new user with water rights
(define-public (register-user (user principal) (initial-allocation uint))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (> initial-allocation u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-registered-user user)) ERR-ALREADY-REGISTERED)
    
    (map-set water-rights user
      {
        registered: true,
        total-allocation: initial-allocation,
        current-usage: u0,
        last-updated: block-height,
        registration-date: block-height
      }
    )
    
    ;; Update community total allocation
    (var-set total-community-allocation (+ (var-get total-community-allocation) initial-allocation))
    
    (ok true)
  )
)

;; Update user allocation
(define-public (update-user-allocation (user principal) (new-allocation uint))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (> new-allocation u0) ERR-INVALID-AMOUNT)
    (asserts! (is-registered-user user) ERR-NOT-REGISTERED)
    
    (let 
      (
        (current-rights (unwrap-panic (map-get? water-rights user)))
        (current-allocation (get total-allocation current-rights))
      )
      
      ;; Update community total allocation
      (var-set total-community-allocation 
        (+ (- (var-get total-community-allocation) current-allocation) new-allocation)
      )
      
      (map-set water-rights user
        (merge current-rights { total-allocation: new-allocation, last-updated: block-height })
      )
      
      (ok true)
    )
  )
)

;; Allocate water from a specific source to a user
(define-public (allocate-from-source (source-id uint) (user principal) (amount uint))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (is-valid-source source-id) ERR-INVALID-SOURCE)
    (asserts! (is-registered-user user) ERR-NOT-REGISTERED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (map-set source-allocations 
      { source-id: source-id, user: user }
      {
        allocation: amount,
        active: true
      }
    )
    
    (ok true)
  )
)

;; Record water usage for a user
(define-public (record-usage (user principal) (amount uint))
  (begin
    (asserts! (or (is-admin) (is-eq tx-sender user)) ERR-NOT-AUTHORIZED)
    (asserts! (is-registered-user user) ERR-NOT-REGISTERED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let 
      (
        (current-rights (unwrap-panic (map-get? water-rights user)))
        (new-usage (+ (get current-usage current-rights) amount))
      )
      
      ;; Check if usage exceeds allocation
      (asserts! (<= new-usage (get total-allocation current-rights)) ERR-QUOTA-EXCEEDED)
      
      ;; Update user's water rights
      (map-set water-rights user
        (merge current-rights 
          { 
            current-usage: new-usage,
            last-updated: block-height
          }
        )
      )
      
      ;; Record the usage history
      (record-usage-history user amount)
      
      ;; Update community usage total
      (update-total-usage amount)
      
      (ok true)
    )
  )
)

;; Start a new allocation period (e.g., new month/season)
(define-public (start-new-period)
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    
    ;; Increment the current period
    (var-set current-period (+ (var-get current-period) u1))
    
    ;; Reset community usage
    (var-set total-community-usage u0)
    
    ;; Reset all users' current usage
    ;; Note: In Clarity, we cannot iterate through maps.
    ;; In a real implementation, this would require off-chain tracking
    ;; or a different approach like having users reset their own usage.
    
    (ok (var-get current-period))
  )
)

;; Reset user's usage for a new period
(define-public (reset-user-usage (user principal))
  (begin
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (is-registered-user user) ERR-NOT-REGISTERED)
    
    (let 
      (
        (current-rights (unwrap-panic (map-get? water-rights user)))
      )
      
      (map-set water-rights user
        (merge current-rights 
          { 
            current-usage: u0,
            last-updated: block-height
          }
        )
      )
      
      (ok true)
    )
  )
)

;; Transfer water allocation from one user to another
(define-public (transfer-allocation (recipient principal) (amount uint))
  (begin
    (asserts! (is-registered-user tx-sender) ERR-NOT-REGISTERED)
    (asserts! (is-registered-user recipient) ERR-NOT-REGISTERED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let 
      (
        (sender-rights (unwrap-panic (map-get? water-rights tx-sender)))
        (recipient-rights (unwrap-panic (map-get? water-rights recipient)))
        (available-quota (- (get total-allocation sender-rights) (get current-usage sender-rights)))
      )
      
      ;; Check if sender has enough available quota
      (asserts! (>= available-quota amount) ERR-QUOTA-EXCEEDED)
      
      ;; Update sender's allocation
      (map-set water-rights tx-sender
        (merge sender-rights 
          { 
            total-allocation: (- (get total-allocation sender-rights) amount),
            last-updated: block-height
          }
        )
      )
      
      ;; Update recipient's allocation
      (map-set water-rights recipient
        (merge recipient-rights 
          { 
            total-allocation: (+ (get total-allocation recipient-rights) amount),
            last-updated: block-height
          }
        )
      )
      
      (ok true)
    )
  )
)