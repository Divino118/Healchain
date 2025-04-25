;; HealChain Smart Contract
;; A decentralized system for managing medical device compliance

(define-trait device-tracking-trait
  (
    (register-device (uint uint) (response bool uint))
    (update-status (uint uint) (response bool uint))
    (get-history (uint) (response (list 5 {status: uint, time: uint}) uint))
    (add-cert (uint uint principal) (response bool uint))
    (verify-cert (uint uint) (response bool uint))
  )
)

;; Constants
(define-constant PHASE_MFG u1)
(define-constant PHASE_TEST u2)
(define-constant PHASE_DEPLOY u3)
(define-constant PHASE_MAINT u4)

(define-constant CERT_FDA u1)
(define-constant CERT_CE u2)
(define-constant CERT_ISO u3)
(define-constant CERT_SAFETY u4)

(define-constant ERR_AUTH (err u1))
(define-constant ERR_DEVICE (err u2))
(define-constant ERR_STATUS (err u3))
(define-constant ERR_CERT (err u4))
(define-constant ERR_DUP (err u5))

;; Data storage
(define-data-var admin principal tx-sender)
(define-data-var time-seq uint u0)

(define-map devices 
  {id: uint} 
  {
    owner: principal,
    status: uint,
    history: (list 5 {status: uint, time: uint})
  }
)

(define-map certs
  {id: uint, type: uint}
  {
    issuer: principal,
    time: uint,
    valid: bool
  }
)

(define-map regulators
  {entity: principal, type: uint}
  {approved: bool}
)

;; Utility functions
(define-private (next-time)
  (begin
    (var-set time-seq (+ (var-get time-seq) u1))
    (var-get time-seq)
  )
)

(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

(define-private (valid-phase? (phase uint))
  (or 
    (is-eq phase PHASE_MFG)
    (is-eq phase PHASE_TEST)
    (is-eq phase PHASE_DEPLOY)
    (is-eq phase PHASE_MAINT)
  )
)

(define-private (valid-cert? (cert uint))
  (or
    (is-eq cert CERT_FDA)
    (is-eq cert CERT_CE)
    (is-eq cert CERT_ISO)
    (is-eq cert CERT_SAFETY)
  )
)

(define-private (valid-id? (id uint))
  (and (> id u0) (<= id u1000000))
)

(define-private (is-regulator? (entity principal) (cert-type uint))
  (default-to false (get approved (map-get? regulators {entity: entity, type: cert-type})))
)

;; Public functions
(define-public (register-device (id uint) (status uint))
  (begin
    (asserts! (valid-id? id) ERR_DEVICE)
    (asserts! (valid-phase? status) ERR_STATUS)

    (map-set devices 
      {id: id}
      {
        owner: tx-sender,
        status: status,
        history: (list {status: status, time: (next-time)})
      }
    )
    (ok true)
  )
)

(define-public (update-status (id uint) (status uint))
  (let ((device (unwrap! (map-get? devices {id: id}) ERR_DEVICE)))
    (asserts! (valid-phase? status) ERR_STATUS)
    (asserts! (or (is-admin) (is-eq (get owner device) tx-sender)) ERR_AUTH)

    (map-set devices 
      {id: id}
      (merge device {
        status: status,
        history: (unwrap-panic 
          (as-max-len? 
            (append (get history device) {status: status, time: (next-time)}) 
            u5
          )
        )
      })
    )
    (ok true)
  )
)

(define-public (add-regulator (entity principal) (cert-type uint))
  (begin
    (asserts! (is-admin) ERR_AUTH)
    (asserts! (valid-cert? cert-type) ERR_CERT)
    (asserts! (not (is-eq entity (var-get admin))) ERR_AUTH)

    (map-set regulators
      {entity: entity, type: cert-type}
      {approved: true}
    )
    (ok true)
  )
)

(define-public (add-cert (id uint) (cert-type uint))
  (begin
    (asserts! (valid-id? id) ERR_DEVICE)
    (asserts! (valid-cert? cert-type) ERR_CERT)
    (asserts! (is-regulator? tx-sender cert-type) ERR_AUTH)
    (asserts! (is-none (map-get? certs {id: id, type: cert-type})) ERR_DUP)

    (map-set certs
      {id: id, type: cert-type}
      {
        issuer: tx-sender,
        time: (next-time),
        valid: true
      }
    )
    (ok true)
  )
)

(define-read-only (verify-cert (id uint) (cert-type uint))
  (ok (default-to false (get valid (map-get? certs {id: id, type: cert-type}))))
)

(define-public (revoke-cert (id uint) (cert-type uint))
  (let ((cert (unwrap! (map-get? certs {id: id, type: cert-type}) ERR_CERT)))
    (asserts! 
      (or (is-admin) (is-eq (get issuer cert) tx-sender))
      ERR_AUTH
    )

    (map-set certs
      {id: id, type: cert-type}
      (merge cert {valid: false})
    )
    (ok true)
  )
)

(define-read-only (get-history (id uint))
  (ok (get history (default-to 
    {owner: tx-sender, status: u0, history: (list)}
    (map-get? devices {id: id}))))
)

(define-read-only (get-status (id uint))
  (ok (get status (unwrap! (map-get? devices {id: id}) ERR_DEVICE)))
)

(define-read-only (get-cert-details (id uint) (cert-type uint))
  (ok (map-get? certs {id: id, type: cert-type}))
)