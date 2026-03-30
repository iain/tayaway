# typed: true

module WebAuthn
  class FakeClient
    def initialize(origin = T.unsafe(nil), token_binding: nil, authenticator: T.unsafe(nil), encoding: T.unsafe(nil)); end
    def create(challenge: T.unsafe(nil), rp_id: nil, user_present: true, user_verified: false, backup_eligibility: false, backup_state: false, attested_credential_data: true, credential_algorithm: nil, extensions: nil); end
    def get(challenge: T.unsafe(nil), rp_id: nil, user_present: true, user_verified: false, backup_eligibility: false, backup_state: true, sign_count: nil, extensions: nil, user_handle: nil, allow_credentials: nil); end
  end
end
