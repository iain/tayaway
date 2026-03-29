# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module CompleteAuthentication
      class << self
        extend T::Sig
        include Result::Methods

        sig do
          params(
            challenge_token: T.nilable(String),
            credential: T.nilable(T::Hash[String, T.untyped]),
            ip: T.nilable(String),
            user_agent: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def call(challenge_token:, credential:, ip: nil, user_agent: nil)
          validate_inputs(challenge_token, credential)
            .bind { |challenge| verify_assertion(T.must(credential), challenge) }
            .bind { |verified| create_session(verified[:user_id], verified[:credential_id], ip: ip, user_agent: user_agent) }
        end

        private

        sig do
          params(challenge_token: T.nilable(String), credential: T.nilable(T::Hash[String, T.untyped]))
            .returns(Result[String, ServiceError])
        end
        def validate_inputs(challenge_token, credential)
          if challenge_token.nil? || challenge_token.empty?
            return T.cast(Failure(ServiceError.validation("Challenge token is required")), Result[String, ServiceError])
          end

          if credential.nil? || credential.empty?
            return T.cast(Failure(ServiceError.validation("Credential is required")), Result[String, ServiceError])
          end

          decoded = Auth::Token.decode_webauthn_challenge(challenge_token)
          T.cast(Success(decoded[:challenge]), Result[String, ServiceError])
        rescue JWT::DecodeError
          T.cast(Failure(ServiceError.unauthorized("Invalid or expired challenge")), Result[String, ServiceError])
        end

        sig do
          params(credential: T::Hash[String, T.untyped], challenge: String)
            .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def verify_assertion(credential, challenge)
          webauthn_credential = WebAuthn::Credential.from_get(credential)

          stored = PasskeyCredential.find_by_external_id(webauthn_credential.id)
          unless stored
            return T.cast(
              Failure(ServiceError.unauthorized("Passkey not recognized")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          webauthn_credential.verify(
            challenge,
            public_key: stored.public_key,
            sign_count: stored.sign_count
          )

          # Update sign count
          DB[:passkey_credentials]
            .where(id: stored.id.to_s)
            .update(sign_count: webauthn_credential.sign_count.to_i)

          T.cast(Success({
            user_id: stored.user_id.to_s,
            credential_id: stored.id.to_s
          }
                        ), Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        rescue WebAuthn::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Authentication verification failed: #{e.class}" }
          T.cast(
            Failure(ServiceError.unauthorized("Passkey authentication failed")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        sig do
          params(user_id: String, _credential_id: String, ip: T.nilable(String), user_agent: T.nilable(String))
            .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def create_session(user_id, _credential_id, ip: nil, user_agent: nil)
          user = User.find(user_id)
          unless user
            return T.cast(
              Failure(ServiceError.unauthorized("User not found")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          now = Time.now
          id = SecureRandom.uuid
          token = SecureRandom.hex(32)
          expires_at = now + Session::EXPIRY_SECONDS

          geo = ip ? GeoIP.lookup(ip) : nil
          browser_info = user_agent ? parse_user_agent(user_agent) : nil

          DB[:sessions].insert(
            id: id,
            user_id: user_id,
            token: Auth::Token.digest(token),
            expires_at: expires_at,
            created_at: now,
            ip_address: ip && IPAddr.new(ip),
            city: geo&.dig(:city),
            country: geo&.dig(:country),
            browser_name: browser_info&.dig(:browser_name),
            os_name: browser_info&.dig(:os_name)
          )

          APP_LOGGER.info { "[Auth::Passkeys] Session created for user #{user_id} via passkey" }
          T.cast(Success({
            session_token: token,
            user_id: user_id
          }
                        ), Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        sig { params(user_agent: String).returns(T::Hash[Symbol, T.nilable(String)]) }
        def parse_user_agent(user_agent)
          b = Browser.new(user_agent)
          {
            browser_name: b.name.empty? ? nil : b.name,
            os_name: b.platform.name.empty? ? nil : b.platform.name
          }
        rescue StandardError
          { browser_name: nil, os_name: nil }
        end
      end
    end
  end
end
