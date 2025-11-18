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

(define-constant ERR-SCHEDULE-NOT-FOUND (err u404))
(define-constant ERR-INVALID-INTERVAL (err u432))
(define-constant ERR-SCHEDULE-PAUSED (err u433))
(define-constant ERR-TOO-EARLY (err u434))
(define-constant ERR-SCHEDULE-EXISTS (err u435))

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


(define-map trust-templates
  { template-id: uint }
  {
    name: (string-ascii 64),
    creator: principal,
    default-lock-blocks: uint,
    category: (string-ascii 32),
    description: (string-ascii 128),
    created-at: uint,
    usage-count: uint,
    is-public: bool
  }
)

(define-data-var total-templates uint u0)

(define-map template-categories
  { category: (string-ascii 32) }
  { template-ids: (list 20 uint) }
)

(define-public (create-template
  (name (string-ascii 64))
  (default-lock-blocks uint)
  (category (string-ascii 32))
  (description (string-ascii 128))
  (is-public bool)
)
  (let ((template-id (+ (var-get total-templates) u1)))
    (asserts! (> default-lock-blocks u0) ERR-INVALID-UNLOCK-TIME)
    (asserts! (> (len name) u0) ERR-INVALID-AMOUNT)
    
    (map-set trust-templates
      { template-id: template-id }
      {
        name: name,
        creator: tx-sender,
        default-lock-blocks: default-lock-blocks,
        category: category,
        description: description,
        created-at: stacks-block-height,
        usage-count: u0,
        is-public: is-public
      }
    )
    
    (let ((current-category-templates 
           (default-to (list) 
             (get template-ids 
               (map-get? template-categories { category: category })))))
      (map-set template-categories
        { category: category }
        { template-ids: (unwrap-panic (as-max-len? (append current-category-templates template-id) u20)) }
      )
    )
    
    (var-set total-templates template-id)
    (ok template-id)
  )
)

(define-public (create-trust-from-template
  (template-id uint)
  (beneficiary principal)
  (amount uint)
  (trust-name (string-ascii 64))
)
  (let ((template-data (unwrap! (map-get? trust-templates { template-id: template-id }) ERR-TRUST-NOT-FOUND)))
    (asserts! (or (get is-public template-data) (is-eq tx-sender (get creator template-data))) ERR-UNAUTHORIZED)
    
    (map-set trust-templates
      { template-id: template-id }
      (merge template-data { usage-count: (+ (get usage-count template-data) u1) })
    )
    
    (create-trust 
      beneficiary 
      amount 
      (+ stacks-block-height (get default-lock-blocks template-data))
      trust-name
    )
  )
)

(define-read-only (get-template-info (template-id uint))
  (map-get? trust-templates { template-id: template-id })
)

(define-read-only (get-templates-by-category (category (string-ascii 32)))
  (default-to 
    { template-ids: (list) }
    (map-get? template-categories { category: category })
  )
)

(define-read-only (get-template-stats)
  {
    total-templates: (var-get total-templates)
  }
)


(define-constant ERR-MILESTONE-NOT-REACHED (err u429))
(define-constant ERR-MILESTONE-ALREADY-CLAIMED (err u430))
(define-constant ERR-INVALID-MILESTONE-CONFIG (err u431))

(define-map trust-milestones
  { trust-id: uint }
  {
    total-milestones: uint,
    milestones-claimed: uint
  }
)

(define-map milestone-releases
  { trust-id: uint, milestone-index: uint }
  {
    unlock-block-height: uint,
    percentage: uint,
    claimed: bool,
    description: (string-ascii 64)
  }
)

(define-private (store-milestone-at-index
  (index uint)
  (context { trust-id: uint, blocks: (list 5 uint), percentages: (list 5 uint), descriptions: (list 5 (string-ascii 64)) })
)
  (begin
    (map-set milestone-releases
      { trust-id: (get trust-id context), milestone-index: index }
      {
        unlock-block-height: (default-to u0 (element-at? (get blocks context) index)),
        percentage: (default-to u0 (element-at? (get percentages context) index)),
        claimed: false,
        description: (default-to "" (element-at? (get descriptions context) index))
      }
    )
    context
  )
)

(define-public (configure-milestones
  (trust-id uint)
  (milestone-blocks (list 5 uint))
  (milestone-percentages (list 5 uint))
  (milestone-descriptions (list 5 (string-ascii 64)))
)
  (let
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (grantor (get grantor trust-data))
      (withdrawn (get withdrawn trust-data))
      (total-milestones (len milestone-blocks))
      (total-percentage (fold + milestone-percentages u0))
    )
    (asserts! (is-eq tx-sender grantor) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (is-eq (len milestone-blocks) (len milestone-percentages)) ERR-INVALID-MILESTONE-CONFIG)
    (asserts! (is-eq total-percentage u100) ERR-INVALID-MILESTONE-CONFIG)
    (asserts! (is-none (map-get? trust-milestones { trust-id: trust-id })) ERR-INVALID-MILESTONE-CONFIG)
    
    (map-set trust-milestones
      { trust-id: trust-id }
      { total-milestones: total-milestones, milestones-claimed: u0 }
    )
    
    (fold store-milestone-at-index
      (list u0 u1 u2 u3 u4)
      { trust-id: trust-id, blocks: milestone-blocks, percentages: milestone-percentages, descriptions: milestone-descriptions }
    )
    
    (ok true)
  )
)

(define-public (claim-milestone (trust-id uint) (milestone-index uint))
  (let
    (
      (trust-data (unwrap! (get-trust-info trust-id) ERR-TRUST-NOT-FOUND))
      (beneficiary (get beneficiary trust-data))
      (trust-amount (get amount trust-data))
      (withdrawn (get withdrawn trust-data))
      (milestone-data (unwrap! (map-get? milestone-releases { trust-id: trust-id, milestone-index: milestone-index }) ERR-MILESTONE-NOT-REACHED))
      (unlock-block (get unlock-block-height milestone-data))
      (percentage (get percentage milestone-data))
      (already-claimed (get claimed milestone-data))
      (release-amount (/ (* trust-amount percentage) u100))
    )
    (asserts! (is-eq tx-sender beneficiary) ERR-UNAUTHORIZED)
    (asserts! (not withdrawn) ERR-TRUST-ALREADY-WITHDRAWN)
    (asserts! (not already-claimed) ERR-MILESTONE-ALREADY-CLAIMED)
    (asserts! (>= stacks-block-height unlock-block) ERR-MILESTONE-NOT-REACHED)
    
    (map-set milestone-releases
      { trust-id: trust-id, milestone-index: milestone-index }
      (merge milestone-data { claimed: true })
    )
    
    (let ((milestone-info (unwrap-panic (map-get? trust-milestones { trust-id: trust-id }))))
      (map-set trust-milestones
        { trust-id: trust-id }
        (merge milestone-info { milestones-claimed: (+ (get milestones-claimed milestone-info) u1) })
      )
    )
    
    (var-set total-value-locked (- (var-get total-value-locked) release-amount))
    (as-contract (stx-transfer? release-amount tx-sender beneficiary))
  )
)

(define-read-only (get-milestone-info (trust-id uint) (milestone-index uint))
  (map-get? milestone-releases { trust-id: trust-id, milestone-index: milestone-index })
)

(define-read-only (get-trust-milestone-progress (trust-id uint))
  (map-get? trust-milestones { trust-id: trust-id })
)


(define-map recurring-schedules
  { trust-id: uint }
  {
    grantor: principal,
    deposit-amount: uint,
    interval-blocks: uint,
    next-deposit-block: uint,
    total-deposits-made: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-read-only (get-schedule-info (trust-id uint))
  (map-get? recurring-schedules { trust-id: trust-id })
)

(define-read-only (is-deposit-due (trust-id uint))
  (match (get-schedule-info trust-id)
    schedule
      (and 
        (get is-active schedule)
        (>= stacks-block-height (get next-deposit-block schedule))
      )
    false
  )
)

(define-public (setup-recurring-deposit
  (trust-id uint)
  (deposit-amount uint)
  (interval-blocks uint)
)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-UNAUTHORIZED)
    (asserts! (> deposit-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> interval-blocks u0) ERR-INVALID-INTERVAL)
    (asserts! (is-none (get-schedule-info trust-id)) ERR-SCHEDULE-EXISTS)
    
    (map-set recurring-schedules
      { trust-id: trust-id }
      {
        grantor: tx-sender,
        deposit-amount: deposit-amount,
        interval-blocks: interval-blocks,
        next-deposit-block: (+ stacks-block-height interval-blocks),
        total-deposits-made: u0,
        is-active: true,
        created-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (execute-scheduled-deposit (trust-id uint))
  (let
    (
      (schedule (unwrap! (get-schedule-info trust-id) ERR-SCHEDULE-NOT-FOUND))
      (grantor (get grantor schedule))
      (amount (get deposit-amount schedule))
      (interval (get interval-blocks schedule))
      (is-active (get is-active schedule))
      (next-block (get next-deposit-block schedule))
    )
    (asserts! is-active ERR-SCHEDULE-PAUSED)
    (asserts! (>= stacks-block-height next-block) ERR-TOO-EARLY)
    (asserts! (>= (stx-get-balance grantor) amount) ERR-INSUFFICIENT-BALANCE)
    
    (map-set recurring-schedules
      { trust-id: trust-id }
      (merge schedule 
        { 
          next-deposit-block: (+ stacks-block-height interval),
          total-deposits-made: (+ (get total-deposits-made schedule) u1)
        }
      )
    )
    (ok true)
  )
)

(define-public (pause-schedule (trust-id uint))
  (let ((schedule (unwrap! (get-schedule-info trust-id) ERR-SCHEDULE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get grantor schedule)) ERR-UNAUTHORIZED)
    (map-set recurring-schedules { trust-id: trust-id } (merge schedule { is-active: false }))
    (ok true)
  )
)

(define-public (resume-schedule (trust-id uint))
  (let ((schedule (unwrap! (get-schedule-info trust-id) ERR-SCHEDULE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get grantor schedule)) ERR-UNAUTHORIZED)
    (map-set recurring-schedules 
      { trust-id: trust-id } 
      (merge schedule { is-active: true, next-deposit-block: (+ stacks-block-height (get interval-blocks schedule)) })
    )
    (ok true)
  )
)
