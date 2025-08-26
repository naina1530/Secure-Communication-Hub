;; SecureCommunication Hub Contract
;; Encrypted messaging with blockchain key management and forward secrecy

;; Define the contract
(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-unauthorized (err u100))
(define-constant err-key-not-found (err u101))
(define-constant err-invalid-message (err u102))
(define-constant err-key-expired (err u103))

;; Data structures for key management
(define-map user-public-keys 
  principal 
  {
    key: (buff 64),
    timestamp: uint,
    rotation-count: uint
  })

;; Data structure for encrypted messages
(define-map encrypted-messages
  {sender: principal, recipient: principal, message-id: uint}
  {
    encrypted-content: (buff 512),
    timestamp: uint,
    key-rotation-id: uint
  })

;; Message counter for unique IDs
(define-data-var message-counter uint u0)

;; Key expiration time (in blocks - approximately 24 hours)
(define-constant key-expiration-blocks u144)

;; Function 1: Register or rotate public key for forward secrecy
(define-public (register-public-key (public-key (buff 64)))
  (let (
    (current-key (map-get? user-public-keys tx-sender))
    (current-block stacks-block-height)
  )
    ;; Validate key format (simplified validation)
    (asserts! (> (len public-key) u0) err-invalid-message)
    
    ;; Update or create key entry with rotation tracking
    (map-set user-public-keys tx-sender
      {
        key: public-key,
        timestamp: current-block,
        rotation-count: (+ (get rotation-count (default-to {key: 0x00, timestamp: u0, rotation-count: u0} current-key)) u1)
      })
    
    ;; Print event for off-chain indexing
    (print {
      action: "key-registered",
      user: tx-sender,
      timestamp: current-block,
      rotation-count: (get rotation-count (map-get? user-public-keys tx-sender))
    })
    
    (ok true)))

;; Function 2: Send encrypted message with forward secrecy
(define-public (send-encrypted-message 
  (recipient principal) 
  (encrypted-content (buff 512)))
  (let (
    (recipient-key-data (map-get? user-public-keys recipient))
    (message-id (+ (var-get message-counter) u1))
    (current-block stacks-block-height)
  )
    ;; Check if recipient has registered a public key
    (asserts! (is-some recipient-key-data) err-key-not-found)
    
    ;; Check if recipient's key is not expired (for forward secrecy)
    (asserts! 
      (< (- current-block (get timestamp (unwrap-panic recipient-key-data))) key-expiration-blocks) 
      err-key-expired)
    
    ;; Validate encrypted content
    (asserts! (> (len encrypted-content) u0) err-invalid-message)
    
    ;; Store the encrypted message
    (map-set encrypted-messages 
      {sender: tx-sender, recipient: recipient, message-id: message-id}
      {
        encrypted-content: encrypted-content,
        timestamp: current-block,
        key-rotation-id: (get rotation-count (unwrap-panic recipient-key-data))
      })
    
    ;; Increment message counter
    (var-set message-counter message-id)
    
    ;; Print event for off-chain notification
    (print {
      action: "message-sent",
      sender: tx-sender,
      recipient: recipient,
      message-id: message-id,
      timestamp: current-block
    })
    
    (ok message-id)))

;; Read-only functions for querying data

;; Get user's current public key
(define-read-only (get-public-key (user principal))
  (ok (map-get? user-public-keys user)))

;; Get encrypted message
(define-read-only (get-message (sender principal) (recipient principal) (message-id uint))
  (ok (map-get? encrypted-messages {sender: sender, recipient: recipient, message-id: message-id})))

;; Get current message counter
(define-read-only (get-message-counter)
  (ok (var-get message-counter)))

;; Check if a key is expired
(define-read-only (is-key-expired (user principal))
  (let (
    (key-data (map-get? user-public-keys user))
  )
    (match key-data
      some-key (ok (> (- stacks-block-height (get timestamp some-key)) key-expiration-blocks))
      (ok true))))