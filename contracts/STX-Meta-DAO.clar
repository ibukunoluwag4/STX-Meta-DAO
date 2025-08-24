;; Meta-DAO Contract - A DAO of DAOs
;; Manages multiple sub-DAOs under one umbrella contract

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-PROPOSAL (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))

;; Data Variables
(define-data-var next-dao-id uint u1)
(define-data-var next-proposal-id uint u1)

;; Sub-DAO Structure
(define-map sub-daos
  { dao-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    creator: principal,
    created-at: uint,
    is-active: bool,
    member-count: uint
  }
)

;; Meta-DAO Members
(define-map meta-members
  { member: principal }
  {
    joined-at: uint,
    voting-power: uint,
    is-active: bool
  }
)

;; Sub-DAO Members
(define-map dao-members
  { dao-id: uint, member: principal }
  {
    role: (string-ascii 20),
    joined-at: uint,
    is-admin: bool
  }
)

;; Proposals for Meta-DAO governance
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    target-dao-id: (optional uint),
    proposal-type: (string-ascii 30),
    created-at: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    is-executed: bool
  }
)

;; Proposal Votes
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voted-at: uint }
)

;; Public Functions

;; Join Meta-DAO as a member
(define-public (join-meta-dao)
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? meta-members { member: caller })) ERR-ALREADY-EXISTS)
    (map-set meta-members
      { member: caller }
      {
        joined-at: block-height,
        voting-power: u1,
        is-active: true
      }
    )
    (ok true)
  )
)

;; Create a new sub-DAO
(define-public (create-sub-dao (name (string-ascii 50)) (description (string-ascii 200)))
  (let 
    (
      (caller tx-sender)
      (dao-id (var-get next-dao-id))
    )
    (asserts! (is-some (map-get? meta-members { member: caller })) ERR-UNAUTHORIZED)

    (map-set sub-daos
      { dao-id: dao-id }
      {
        name: name,
        description: description,
        creator: caller,
        created-at: block-height,
        is-active: true,
        member-count: u1
      }
    )

    (map-set dao-members
      { dao-id: dao-id, member: caller }
      {
        role: "creator",
        joined-at: block-height,
        is-admin: true
      }
    )

    (var-set next-dao-id (+ dao-id u1))
    (ok dao-id)
  )
)

;; Join a sub-DAO
(define-public (join-sub-dao (dao-id uint))
  (let 
    (
      (caller tx-sender)
      (dao-info (unwrap! (map-get? sub-daos { dao-id: dao-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-some (map-get? meta-members { member: caller })) ERR-UNAUTHORIZED)
    (asserts! (get is-active dao-info) ERR-NOT-FOUND)
    (asserts! (is-none (map-get? dao-members { dao-id: dao-id, member: caller })) ERR-ALREADY-EXISTS)

    (map-set dao-members
      { dao-id: dao-id, member: caller }
      {
        role: "member",
        joined-at: block-height,
        is-admin: false
      }
    )

    (map-set sub-daos
      { dao-id: dao-id }
      (merge dao-info { member-count: (+ (get member-count dao-info) u1) })
    )

    (ok true)
  )
)

;; Create a proposal for Meta-DAO governance
(define-public (create-proposal 
  (title (string-ascii 100)) 
  (description (string-ascii 500))
  (target-dao-id (optional uint))
  (proposal-type (string-ascii 30))
  (voting-period uint)
)
  (let 
    (
      (caller tx-sender)
      (proposal-id (var-get next-proposal-id))
      (member-info (unwrap! (map-get? meta-members { member: caller }) ERR-UNAUTHORIZED))
    )
    (asserts! (get is-active member-info) ERR-UNAUTHORIZED)
    (asserts! (> voting-period u0) ERR-INVALID-PROPOSAL)

    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: caller,
        target-dao-id: target-dao-id,
        proposal-type: proposal-type,
        created-at: block-height,
        end-block: (+ block-height voting-period),
        yes-votes: u0,
        no-votes: u0,
        is-executed: false
      }
    )

    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let 
    (
      (caller tx-sender)
      (proposal-info (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-NOT-FOUND))
      (member-info (unwrap! (map-get? meta-members { member: caller }) ERR-UNAUTHORIZED))
      (voting-power (get voting-power member-info))
    )
    (asserts! (get is-active member-info) ERR-UNAUTHORIZED)
    (asserts! (<= block-height (get end-block proposal-info)) ERR-PROPOSAL-EXPIRED)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: caller })) ERR-ALREADY-VOTED)

    (map-set proposal-votes
      { proposal-id: proposal-id, voter: caller }
      { vote: vote, voted-at: block-height }
    )

    (map-set proposals
      { proposal-id: proposal-id }
      (if vote
        (merge proposal-info { yes-votes: (+ (get yes-votes proposal-info) voting-power) })
        (merge proposal-info { no-votes: (+ (get no-votes proposal-info) voting-power) })
      )
    )

    (ok true)
  )
)

;; Deactivate a sub-DAO (only by Meta-DAO governance)
(define-public (deactivate-sub-dao (dao-id uint))
  (let 
    (
      (caller tx-sender)
      (dao-info (unwrap! (map-get? sub-daos { dao-id: dao-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq caller CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (map-set sub-daos
      { dao-id: dao-id }
      (merge dao-info { is-active: false })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get sub-DAO information
(define-read-only (get-sub-dao (dao-id uint))
  (map-get? sub-daos { dao-id: dao-id })
)

;; Get Meta-DAO member information
(define-read-only (get-meta-member (member principal))
  (map-get? meta-members { member: member })
)

;; Get sub-DAO member information
(define-read-only (get-dao-member (dao-id uint) (member principal))
  (map-get? dao-members { dao-id: dao-id, member: member })
)

;; Get proposal information
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Get vote information
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; Check if user is Meta-DAO member
(define-read-only (is-meta-member (member principal))
  (match (map-get? meta-members { member: member })
    member-info (get is-active member-info)
    false
  )
)

;; Check if user is sub-DAO member
(define-read-only (is-dao-member (dao-id uint) (member principal))
  (is-some (map-get? dao-members { dao-id: dao-id, member: member }))
)

;; Get next DAO ID
(define-read-only (get-next-dao-id)
  (var-get next-dao-id)
)

;; Get next proposal ID
(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)