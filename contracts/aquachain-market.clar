;; AquaChain Water Resource Management - Water Market Contract
;; Contract: aquachain-market
;; Purpose: Facilitates trading of water allocation credits between users
;; Version: 1.0.0

;; ===================
;; Constants & Errors
;; ===================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-LISTING-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-PRICE (err u103))
(define-constant ERR-ALREADY-LISTED (err u104))
(define-constant ERR-INSUFFICIENT-CREDITS (err u105))
(define-constant ERR-BID-NOT-FOUND (err u106))
(define-constant ERR-BID-ALREADY-ACCEPTED (err u107))
(define-constant ERR-LISTING-CLOSED (err u108))
(define-constant ERR-INSUFFICIENT-FUNDS (err u109))
(define-constant ERR-SELF-TRADING (err u110))
(define-constant ERR-ADMIN-ONLY (err u111))

;; Other constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant DEFAULT-COMMISSION-RATE u50) ;; 0.5% (in basis points)

;; ===================
;; Data Maps & Vars
;; ===================

;; Track the core AquaChain contract to interact with
(define-data-var core-contract principal 'SPNWZ5V2TPWGQGVDR6T7B6RQ4XMGZ4PXTEE0VQ0S.aquachain-core)

;; Commission rate in basis points (1/100 of a percent)
(define-data-var commission-rate uint DEFAULT-COMMISSION-RATE)

;; Track the next listing ID
(define-data-var next-listing-id uint u1)

;; Track the next bid ID
(define-data-var next-bid-id uint u1)

;; Represents a water credit listing on the marketplace
(define-map listings
  uint  ;; listing-id
  {
    seller: principal,
    amount: uint,
    price-per-unit: uint,
    description: (string-utf8 100),
    active: bool,
    created-at: uint
  }
)

;; Represents a bid on a listing
(define-map bids
  uint  ;; bid-id
  {
    listing-id: uint,
    bidder: principal,
    amount: uint,
    price-per-unit: uint,
    status: (string-utf8 20),  ;; "pending", "accepted", "rejected", "cancelled"
    created-at: uint
  }
)

;; Maps listing IDs to all bids for that listing
(define-map listing-bids
  uint  ;; listing-id
  (list 50 uint)  ;; List of bid IDs, max 50 bids per listing
)

;; Maps users to their active listings
(define-map user-listings
  principal
  (list 50 uint)  ;; List of listing IDs, max 50 listings per user
)

;; Maps users to their active bids
(define-map user-bids
  principal
  (list 50 uint)  ;; List of bid IDs, max 50 bids per user
)

;; Track completed trades for history
(define-map trade-history
  uint  ;; trade-id
  {
    seller: principal,
    buyer: principal,
    amount: uint,
    price-per-unit: uint,
    total-price: uint,
    commission: uint,
    timestamp: uint
  }
)

;; Track the next trade history ID
(define-data-var next-trade-id uint u1)

;; ===================
;; Private Functions
;; ===================

;; Helper function to calculate the commission amount for a trade
(define-private (calculate-commission (total-price uint))
  (let
    (
      (rate (var-get commission-rate))
    )
    ;; Commission = price * rate / 10000 (basis points)
    (/ (* total-price rate) u10000)
  )
)

;; Helper to add a bid ID to a listing's bids
(define-private (add-bid-to-listing (listing-id uint) (bid-id uint))
  (let
    (
      (current-bids (default-to (list) (map-get? listing-bids listing-id)))
    )
    (map-set listing-bids listing-id (append current-bids bid-id))
  )
)

;; Helper to add a listing ID to user's listings
(define-private (add-listing-to-user (user principal) (listing-id uint))
  (let
    (
      (current-listings (default-to (list) (map-get? user-listings user)))
    )
    (map-set user-listings user (append current-listings listing-id))
  )
)

;; Helper to add a bid ID to user's bids
(define-private (add-bid-to-user (user principal) (bid-id uint))
  (let
    (
      (current-bids (default-to (list) (map-get? user-bids user)))
    )
    (map-set user-bids user (append current-bids bid-id))
  )
)

;; Helper to check if user has sufficient water credits
(define-private (has-sufficient-credits (user principal) (amount uint))
  (let
    (
      (core (var-get core-contract))
      (result (contract-call? core get-user-balance user))
    )
    (if (is-err result)
      false
      (>= (unwrap-panic result) amount)
    )
  )
)

;; Helper to transfer water credits between users
(define-private (transfer-water-credits (from principal) (to principal) (amount uint))
  (contract-call? (var-get core-contract) transfer-credits from to amount)
)

;; Helper to record a completed trade in history
(define-private (record-trade (seller principal) (buyer principal) (amount uint) (price-per-unit uint))
  (let
    (
      (trade-id (var-get next-trade-id))
      (total-price (* amount price-per-unit))
      (commission (calculate-commission total-price))
    )
    (map-set trade-history trade-id {
      seller: seller,
      buyer: buyer,
      amount: amount,
      price-per-unit: price-per-unit,
      total-price: total-price,
      commission: commission,
      timestamp: block-height
    })
    (var-set next-trade-id (+ trade-id u1))
    trade-id
  )
)

;; ===================
;; Read-Only Functions
;; ===================

;; Get a listing by ID
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

;; Get a bid by ID
(define-read-only (get-bid (bid-id uint))
  (map-get? bids bid-id)
)

;; Get all bids for a listing
(define-read-only (get-listing-bids (listing-id uint))
  (default-to (list) (map-get? listing-bids listing-id))
)

;; Get all listings for a user
(define-read-only (get-user-listings (user principal))
  (default-to (list) (map-get? user-listings user))
)

;; Get all bids made by a user
(define-read-only (get-user-bids (user principal))
  (default-to (list) (map-get? user-bids user))
)

;; Get trade details by ID
(define-read-only (get-trade (trade-id uint))
  (map-get? trade-history trade-id)
)

;; Get the current commission rate
(define-read-only (get-commission-rate)
  (var-get commission-rate)
)

;; Check if a listing is active
(define-read-only (is-listing-active (listing-id uint))
  (let
    (
      (listing (map-get? listings listing-id))
    )
    (if (is-none listing)
      false
      (get active (unwrap-panic listing)))
  )
)

;; ===================
;; Public Functions
;; ===================

;; Set the core contract address (admin only)
(define-public (set-core-contract (new-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-ADMIN-ONLY)
    (ok (var-set core-contract new-contract))
  )
)

;; Update the commission rate (admin only)
(define-public (set-commission-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-ADMIN-ONLY)
    (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT) ;; Max 10%
    (ok (var-set commission-rate new-rate))
  )
)

;; Create a new listing to sell water credits
(define-public (create-listing (amount uint) (price-per-unit uint) (description (string-utf8 100)))
  (let
    (
      (listing-id (var-get next-listing-id))
      (seller tx-sender)
    )
    ;; Validate inputs
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-unit u0) ERR-INVALID-PRICE)
    (asserts! (has-sufficient-credits seller amount) ERR-INSUFFICIENT-CREDITS)

    ;; Create the listing
    (map-set listings listing-id {
      seller: seller,
      amount: amount,
      price-per-unit: price-per-unit,
      description: description,
      active: true,
      created-at: block-height
    })

    ;; Update user's listings
    (add-listing-to-user seller listing-id)

    ;; Increment the listing ID counter
    (var-set next-listing-id (+ listing-id u1))

    (ok listing-id)
  )
)

;; Update an existing listing
(define-public (update-listing (listing-id uint) (new-amount (optional uint)) (new-price (optional uint)) (new-description (optional (string-utf8 100))))
  (let
    (
      (listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND))
      (seller (get seller listing))
    )
    ;; Check authorization
    (asserts! (is-eq tx-sender seller) ERR-NOT-AUTHORIZED)
    (asserts! (get active listing) ERR-LISTING-CLOSED)

    ;; Apply updates
    (let
      (
        (updated-amount (default-to (get amount listing) new-amount))
        (updated-price (default-to (get price-per-unit listing) new-price))
        (updated-description (default-to (get description listing) new-description))
      )
      ;; Validate new values
      (asserts! (> updated-amount u0) ERR-INVALID-AMOUNT)
      (asserts! (> updated-price u0) ERR-INVALID-PRICE)
      (asserts! (has-sufficient-credits seller updated-amount) ERR-INSUFFICIENT-CREDITS)

      ;; Update the listing
      (map-set listings listing-id 
        (merge listing {
          amount: updated-amount,
          price-per-unit: updated-price,
          description: updated-description
        })
      )

      (ok true)
    )
  )
)

;; Close a listing (deactivate)
(define-public (close-listing (listing-id uint))
  (let
    (
      (listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND))
      (seller (get seller listing))
    )
    ;; Check authorization
    (asserts! (is-eq tx-sender seller) ERR-NOT-AUTHORIZED)
    (asserts! (get active listing) ERR-LISTING-CLOSED)

    ;; Deactivate the listing
    (map-set listings listing-id 
      (merge listing { active: false })
    )

    (ok true)
  )
)

;; Place a bid on a listing
(define-public (place-bid (listing-id uint) (amount uint) (price-per-unit uint))
  (let
    (
      (listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND))
      (seller (get seller listing))
      (bidder tx-sender)
      (bid-id (var-get next-bid-id))
    )
    ;; Validate the listing and bid
    (asserts! (get active listing) ERR-LISTING-CLOSED)
    (asserts! (not (is-eq bidder seller)) ERR-SELF-TRADING)
    (asserts! (<= amount (get amount listing)) ERR-INVALID-AMOUNT)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-unit u0) ERR-INVALID-PRICE)
    
    ;; Calculate total price and validate funds
    (let
      (
        (total-price (* amount price-per-unit))
      )
      (asserts! (>= (stx-get-balance bidder) total-price) ERR-INSUFFICIENT-FUNDS)

      ;; Create the bid
      (map-set bids bid-id {
        listing-id: listing-id,
        bidder: bidder,
        amount: amount,
        price-per-unit: price-per-unit,
        status: "pending",
        created-at: block-height
      })

      ;; Update bid tracking
      (add-bid-to-listing listing-id bid-id)
      (add-bid-to-user bidder bid-id)

      ;; Increment the bid ID counter
      (var-set next-bid-id (+ bid-id u1))

      (ok bid-id)
    )
  )
)

;; Cancel a bid
(define-public (cancel-bid (bid-id uint))
  (let
    (
      (bid (unwrap! (map-get? bids bid-id) ERR-BID-NOT-FOUND))
      (bidder (get bidder bid))
    )
    ;; Check authorization
    (asserts! (is-eq tx-sender bidder) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status bid) "pending") ERR-BID-ALREADY-ACCEPTED)

    ;; Update bid status
    (map-set bids bid-id
      (merge bid { status: "cancelled" })
    )

    (ok true)
  )
)

;; Accept a bid and execute the trade
(define-public (accept-bid (bid-id uint))
  (let
    (
      (bid (unwrap! (map-get? bids bid-id) ERR-BID-NOT-FOUND))
      (listing-id (get listing-id bid))
      (listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND))
      (seller (get seller listing))
      (bidder (get bidder bid))
      (amount (get amount bid))
      (price-per-unit (get price-per-unit bid))
    )
    ;; Check authorization and status
    (asserts! (is-eq tx-sender seller) ERR-NOT-AUTHORIZED)
    (asserts! (get active listing) ERR-LISTING-CLOSED)
    (asserts! (is-eq (get status bid) "pending") ERR-BID-ALREADY-ACCEPTED)
    (asserts! (has-sufficient-credits seller amount) ERR-INSUFFICIENT-CREDITS)

    ;; Execute the trade
    (let
      (
        (total-price (* amount price-per-unit))
        (commission (calculate-commission total-price))
        (seller-receives (- total-price commission))
      )
      ;; 1. Transfer STX from buyer to seller (including commission to contract owner)
      (try! (stx-transfer? seller-receives bidder seller))
      (try! (stx-transfer? commission bidder CONTRACT-OWNER))

      ;; 2. Transfer water credits from seller to buyer
      (try! (transfer-water-credits seller bidder amount))

      ;; 3. Update bid status
      (map-set bids bid-id
        (merge bid { status: "accepted" })
      )

      ;; 4. Update listing amount (or close if fully sold)
      (if (is-eq amount (get amount listing))
        (map-set listings listing-id
          (merge listing { active: false })
        )
        (map-set listings listing-id
          (merge listing { amount: (- (get amount listing) amount) })
        )
      )

      ;; 5. Record the trade in history
      (let
        (
          (trade-id (record-trade seller bidder amount price-per-unit))
        )
        (ok trade-id)
      )
    )
  )
)

;; Reject a bid
(define-public (reject-bid (bid-id uint))
  (let
    (
      (bid (unwrap! (map-get? bids bid-id) ERR-BID-NOT-FOUND))
      (listing-id (get listing-id bid))
      (listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND))
      (seller (get seller listing))
    )
    ;; Check authorization
    (asserts! (is-eq tx-sender seller) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status bid) "pending") ERR-BID-ALREADY-ACCEPTED)

    ;; Update bid status
    (map-set bids bid-id
      (merge bid { status: "rejected" })
    )

    (ok true)
  )
)