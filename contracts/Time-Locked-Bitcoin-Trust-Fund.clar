(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-TRUST-NOT-FOUND (err u404))
(define-constant ERR-TRUST-LOCKED (err u403))
(define-constant ERR-TRUST-EXPIRED (err u410))
(define-constant ERR-INSUFFICIENT-BALANCE (err u400))
(define-constant ERR-TRUST-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-UNLOCK-TIME (err u422))
(define-constant ERR-INVALID-AMOUNT (err u423))
(define-constant ERR-TRUST-ALREADY-WITHDRAWN (err u424))
(define-constant ERR-EMERGENCY-LOCKED (err u425))

(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-unlock-enabled bool false)
(define-data-var total-trusts uint u0)
(define-data-var total-value-locked uint u0)

(define-constant ERR-NO-BACKUP-BENEFICIARY (err u426))
(define-constant ERR-INACTIVITY-PERIOD-NOT-MET (err u427))
(define-constant ERR-BACKUP-ALREADY-NOMINATED (err u428))

(define-map trusts
  { trust-id: uint }
  {
    grantor: principal,
    beneficiary: principal,
    amount: uint,
    unlock-block-height: uint,
    created-at: uint,
    withdrawn: bool,
    trust-name: (string-ascii 64)
  }
)

(define-map user-trusts
  { user: principal }
  { trust-ids: (list 50 uint) }
)

(define-map grantor-trusts
  { grantor: principal }
  { trust-ids: (list 50 uint) }
)

(define-read-only (get-trust-info (trust-id uint))
  (map-get? trusts { trust-id: trust-id })
)

(define-read-only (get-user-trusts (user principal))
  (default-to 
    { trust-ids: (list) }
    (map-get? user-trusts { user: user })
  )
)

(define-read-only (get-grantor-trusts (grantor principal))
  (default-to 
    { trust-ids: (list) }
    (map-get? grantor-trusts { grantor: grantor })
  )
)

(define-read-only (get-contract-stats)
  {
    total-trusts: (var-get total-trusts),
    total-value-locked: (var-get total-value-locked),
    emergency-unlock-enabled: (var-get emergency-unlock-enabled)
  }
)

(define-read-only (is-trust-unlocked (trust-id uint))
  (match (get-trust-info trust-id)
    trust-data 
      (>= stacks-block-height (get unlock-block-height trust-data))
    false
  )
)

(define-read-only (get-blocks-until-unlock (trust-id uint))
  (match (get-trust-info trust-id)
    trust-data
      (if (>= stacks-block-height (get unlock-block-height trust-data))
        u0
        (- (get unlock-block-height trust-data) stacks-block-height)
      )
    u0
  )
)

(define-read-only (get-trust-status (trust-id uint))
  (match (get-trust-info trust-id)
    trust-data
      {
        exists: true,
        withdrawn: (get withdrawn trust-data),
        unlocked: (>= stacks-block-height (get unlock-block-height trust-data)),
        blocks-remaining: (if (>= stacks-block-height (get unlock-block-height trust-data))
                           u0
                           (- (get unlock-block-height trust-data) stacks-block-height))
      }
    {
      exists: false,
      withdrawn: false,
      unlocked: false,
      blocks-remaining: u0
    }
  )
)

(define-private (add-trust-to-user (user principal) (trust-id uint))
  (let ((current-trusts (get trust-ids (get-user-trusts user))))
    (map-set user-trusts
      { user: user }
      { trust-ids: (unwrap-panic (as-max-len? (append current-trusts trust-id) u50)) }
    )
  )
)

(define-private (add-trust-to-grantor (grantor principal) (trust-id uint))
  (let ((current-trusts (get trust-ids (get-grantor-trusts grantor))))
    (map-set grantor-trusts
      { grantor: grantor }
      { trust-ids: (unwrap-panic (as-max-len? (append current-trusts trust-id) u50)) }
    )
  )
)

(define-public (create-trust 
  (beneficiary principal)
  (amount uint)
  (unlock-block-height uint)
  (trust-name (string-ascii 64))
)
  (let 
    (
      (trust-id (+ (var-get total-trusts) u1))
      (current-block stacks-block-height)
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> unlock-block-height current-block) ERR-INVALID-UNLOCK-TIME)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-BALANCE)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set trusts
      { trust-id: trust-id }
      {
        grantor: tx-sender,
        beneficiary: beneficiary,
        amount: amount,
        unlock-block-height: unlock-block-height,
        created-at: current-block,
        withdrawn: false,
        trust-name: trust-name
      }
    )
    
    (add-trust-to-user beneficiary trust-id)
    (add-trust-to-grantor tx-sender trust-id)
    
    (var-set total-trusts trust-id)
    (var-set total-value-locked (+ (var-get total-value-locked) amount))
    
    (ok trust-id)
  )
)

(define-public (withdraw-trust (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (beneficiary (get beneficiary trust-data))
      (amount (get amount trust-data))
      (unlock-block (get unlock-block-height trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (>= stacks-block-height unlock-block) ERR-TRUST-LOCKED)
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { withdrawn: true })
    )
    
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    
    (as-contract (stx-transfer? amount tx-sender beneficiary))
  )
)

(define-public (emergency-withdraw (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (grantor (get grantor trust-data))
      (amount (get amount trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (var-get emergency-unlock-enabled) ERR-EMERGENCY-LOCKED)
    (asserts! (is-eq tx-sender grantor) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { withdrawn: true })
    )
    
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    
    (as-contract (stx-transfer? amount tx-sender grantor))
  )
)

(define-public (extend-lock-time (trust-id uint) (new-unlock-block uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (grantor (get grantor trust-data))
      (current-unlock (get unlock-block-height trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender grantor) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (> new-unlock-block current-unlock) ERR-INVALID-UNLOCK-TIME)
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { unlock-block-height: new-unlock-block })
    )
    
    (ok true)
  )
)

(define-public (add-funds-to-trust (trust-id uint) (additional-amount uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (grantor (get grantor trust-data))
      (current-amount (get amount trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender grantor) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (> additional-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) additional-amount) ERR-INSUFFICIENT-BALANCE)
    
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { amount: (+ current-amount additional-amount) })
    )
    
    (var-set total-value-locked (+ (var-get total-value-locked) additional-amount))
    
    (ok true)
  )
)

(define-public (toggle-emergency-unlock)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set emergency-unlock-enabled (not (var-get emergency-unlock-enabled)))
    (ok (var-get emergency-unlock-enabled))
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-map trust-delegations
  { trust-id: uint }
  { 
    delegate: principal,
    delegated-at: uint,
    active: bool
  }
)

(define-public (delegate-trust (trust-id uint) (delegate principal))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (beneficiary (get beneficiary trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (not (is-eq delegate beneficiary)) ERR-INVALID-AMOUNT)
    
    (map-set trust-delegations
      { trust-id: trust-id }
      {
        delegate: delegate,
        delegated-at: stacks-block-height,
        active: true
      }
    )
    
    (ok true)
  )
)

(define-public (revoke-delegation (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (beneficiary (get beneficiary trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    
    (map-delete trust-delegations { trust-id: trust-id })
    
    (ok true)
  )
)

(define-public (withdraw-as-delegate (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (delegation (unwrap! (map-get? trust-delegations { trust-id: trust-id }) ERR-UNAUTHORIZED))
      (delegate (get delegate delegation))
      (amount (get amount trust-data))
      (unlock-block (get unlock-block-height trust-data))
      (withdrawn (get withdrawn trust-data))
      (active (get active delegation))
    )
    (asserts! (is-eq tx-sender delegate) ERR-UNAUTHORIZED)
    (asserts! active ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (>= stacks-block-height unlock-block) ERR-TRUST-LOCKED)
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { withdrawn: true })
    )
    
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    
    (as-contract (stx-transfer? amount tx-sender delegate))
  )
)

(define-read-only (get-trust-delegation (trust-id uint))
  (map-get? trust-delegations { trust-id: trust-id })
)

(define-read-only (is-delegated (trust-id uint))
  (match (get-trust-delegation trust-id)
    delegation (get active delegation)
    false
  )
)


(define-map backup-beneficiaries
  { trust-id: uint }
  {
    backup-beneficiary: principal,
    inactivity-blocks: uint,
    nominated-at: uint,
    last-primary-activity: uint
  }
)

(define-public (nominate-backup-beneficiary 
  (trust-id uint) 
  (backup-beneficiary principal) 
  (inactivity-blocks uint)
)
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (grantor (get grantor trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender grantor) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (> inactivity-blocks u0) ERR-INVALID-UNLOCK-TIME)
    (asserts! (is-none (map-get? backup-beneficiaries { trust-id: trust-id })) 
              ERR-BACKUP-ALREADY-NOMINATED)
    
    (map-set backup-beneficiaries
      { trust-id: trust-id }
      {
        backup-beneficiary: backup-beneficiary,
        inactivity-blocks: inactivity-blocks,
        nominated-at: stacks-block-height,
        last-primary-activity: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-public (update-primary-activity (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (beneficiary (get beneficiary trust-data))
      (backup-data (map-get? backup-beneficiaries { trust-id: trust-id }))
    )
    (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
    
    (match backup-data
      data (map-set backup-beneficiaries
             { trust-id: trust-id }
             (merge data { last-primary-activity: stacks-block-height }))
      true
    )
    
    (ok true)
  )
)

(define-public (claim-as-backup-beneficiary (trust-id uint))
  (let 
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (backup-data (unwrap! (map-get? backup-beneficiaries { trust-id: trust-id }) 
                            ERR-NO-BACKUP-BENEFICIARY))
      (backup-beneficiary (get backup-beneficiary backup-data))
      (inactivity-blocks (get inactivity-blocks backup-data))
      (last-activity (get last-primary-activity backup-data))
      (amount (get amount trust-data))
      (unlock-block (get unlock-block-height trust-data))
      (withdrawn (get withdrawn trust-data))
    )
    (asserts! (is-eq tx-sender backup-beneficiary) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (>= stacks-block-height unlock-block) ERR-TRUST-LOCKED)
    (asserts! (>= (- stacks-block-height last-activity) inactivity-blocks) 
              ERR-INACTIVITY-PERIOD-NOT-MET)
    
    (map-set trusts
      { trust-id: trust-id }
      (merge trust-data { withdrawn: true })
    )
    
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    
    (as-contract (stx-transfer? amount tx-sender backup-beneficiary))
  )
)

(define-read-only (get-backup-beneficiary-info (trust-id uint))
  (map-get? backup-beneficiaries { trust-id: trust-id })
)
