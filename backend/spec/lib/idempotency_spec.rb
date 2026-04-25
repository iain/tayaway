# frozen_string_literal: true

require "spec_helper"

RSpec.describe Idempotency do
  let(:user) { TestFactories.user.then { |u| Struct.new(:id).new(u[:id]) } }
  let(:key) { SecureRandom.uuid }
  let(:request) { fake_request(method: "POST", path: "/api/things", params: { "a" => 1 }, key: key) }

  def fake_request(method:, path:, params:, key:)
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "HTTP_IDEMPOTENCY_KEY" => key
    }
    instance_double(Rack::Request).tap do |r|
      allow(r).to receive_messages(env: env, request_method: method, path_info: path, params: params)
    end
  end

  describe ".wrap (bypass cases)" do
    it "skips when no user is authenticated" do
      called = false
      result = described_class.wrap(request: request, user: nil) do
        called = true
        :passthrough
      end

      expect(called).to be true
      expect(result).to eq(:passthrough)
      expect(DB[:idempotency_keys].count).to eq(0)
    end

    it "skips for non-mutating methods" do
      get_request = fake_request(method: "GET", path: "/api/things", params: {}, key: key)

      described_class.wrap(request: get_request, user: user) { :ok }

      expect(DB[:idempotency_keys].count).to eq(0)
    end

    it "skips when no Idempotency-Key header is present" do
      no_header = fake_request(method: "POST", path: "/api/things", params: {}, key: nil)
      no_header.env.delete("HTTP_IDEMPOTENCY_KEY")

      described_class.wrap(request: no_header, user: user) { :ok }

      expect(DB[:idempotency_keys].count).to eq(0)
    end

    it "skips when the key is whitespace-only" do
      blank = fake_request(method: "POST", path: "/api/things", params: {}, key: "   ")

      described_class.wrap(request: blank, user: user) { :ok }

      expect(DB[:idempotency_keys].count).to eq(0)
    end

    it "skips when the key exceeds MAX_KEY_LENGTH" do
      oversize = fake_request(method: "POST", path: "/api/things", params: {}, key: "x" * 256)

      described_class.wrap(request: oversize, user: user) { :ok }

      expect(DB[:idempotency_keys].count).to eq(0)
    end
  end

  describe ".wrap (transactional invariant)" do
    it "rolls back the cache row when the route raises after a DB write" do
      initial = DB[:rate_limits].count

      expect {
        described_class.wrap(request: request, user: user) do
          DB[:rate_limits].insert(key: "probe", count: 1, expires_at: Time.now + 60)
          raise "boom"
        end
      }.to raise_error("boom")

      expect(DB[:rate_limits].count).to eq(initial)
      expect(DB[:idempotency_keys].count).to eq(0)
    end

    it "commits both the route's DB writes and the cache row when the route halts" do
      probe = "probe-#{SecureRandom.hex(4)}"
      catch(:halt) do
        described_class.wrap(request: request, user: user) do
          DB[:rate_limits].insert(key: probe, count: 1, expires_at: Time.now + 60)
          throw :halt, [201, { "Content-Type" => "application/json" }, ['{"ok":true}']]
        end
      end

      expect(DB[:rate_limits].where(key: probe).count).to eq(1)
      cached = DB[:idempotency_keys].where(user_id: user.id, idempotency_key: key).first
      expect(cached[:response_status]).to eq(201)
      expect(cached[:response_body]).to eq('{"ok":true}')
    end
  end

  describe ".wrap (replay)" do
    it "returns the cached response without invoking the block on a second call" do
      catch(:halt) do
        described_class.wrap(request: request, user: user) do
          throw :halt, [201, { "Content-Type" => "application/json" }, ['{"id":1}']]
        end
      end

      block_calls = 0
      replayed = catch(:halt) do
        described_class.wrap(request: request, user: user) do
          block_calls += 1
          throw :halt, [201, {}, ['{"id":1}']]
        end
      end

      expect(block_calls).to eq(0)
      status, _headers, body = replayed
      expect(status).to eq(201)
      expect(body.first).to eq('{"id":1}')
    end

    it "is insensitive to JSON key order in the request body" do
      catch(:halt) do
        described_class.wrap(
          request: fake_request(method: "POST", path: "/api/things", params: { "a" => 1, "b" => 2 }, key: key),
          user: user
        ) { throw :halt, [201, {}, ['{"ok":1}']] }
      end

      block_calls = 0
      replay = catch(:halt) do
        described_class.wrap(
          request: fake_request(method: "POST", path: "/api/things", params: { "b" => 2, "a" => 1 }, key: key),
          user: user
        ) do
          block_calls += 1
          throw :halt, [201, {}, ['{"ok":1}']]
        end
      end

      expect(block_calls).to eq(0)
      expect(replay[0]).to eq(201)
    end

    it "rejects a same-key replay with a different request body" do
      catch(:halt) do
        described_class.wrap(
          request: fake_request(method: "POST", path: "/api/things", params: { "a" => 1 }, key: key),
          user: user
        ) { throw :halt, [201, {}, ['{"ok":1}']] }
      end

      conflict = catch(:halt) do
        described_class.wrap(
          request: fake_request(method: "POST", path: "/api/things", params: { "a" => 2 }, key: key),
          user: user
        ) { throw :halt, [201, {}, ['{"ok":2}']] }
      end

      expect(conflict[0]).to eq(422)
    end
  end

  describe ".wrap (in-flight conflict)" do
    it "raises ConflictError when the cache insert conflicts but the winning row is still invisible" do
      # Force the insert to fall into the lost-race branch without actually
      # pre-seeding a row, so the post-rollback lookup also misses.
      # `insert_conflict` is a Postgres-adapter method and not on the generic
      # Sequel::Dataset class, so an instance_double can't verify it — use a
      # plain double here.
      conflicting_dataset = double("idempotency_keys dataset") # rubocop:disable RSpec/VerifiedDoubles
      allow(DB).to receive(:[]).and_call_original
      allow(DB).to receive(:[]).with(:idempotency_keys).and_return(conflicting_dataset)
      allow(conflicting_dataset).to receive_messages(
        insert_conflict: conflicting_dataset,
        insert: nil,
        where: conflicting_dataset,
        first: nil
      )

      expect {
        described_class.wrap(request: request, user: user) do
          throw :halt, [201, {}, ['{"ok":1}']]
        end
      }.to raise_error(described_class::ConflictError)
    end
  end

  describe ".wrap (concurrent retry)" do
    it "rolls back its own mutation and replays when the cache insert conflicts" do
      # Pre-seed a winning row from a "concurrent" request.
      winning_body = '{"winner":true}'
      DB[:idempotency_keys].insert(
        user_id: user.id,
        idempotency_key: key,
        request_fingerprint: described_class.fingerprint_for(request),
        response_status: 201,
        response_body: winning_body,
        created_at: Time.now
      )

      # Force the lookup-before-transaction to miss so we exercise the
      # ON CONFLICT branch rather than the early replay branch.
      allow(described_class).to receive(:lookup).and_call_original
      allow(described_class).to receive(:lookup).with(user.id, key).and_return(nil, DB[:idempotency_keys].where(user_id: user.id, idempotency_key: key).first)

      probe = "probe-#{SecureRandom.hex(4)}"
      replayed = catch(:halt) do
        described_class.wrap(request: request, user: user) do
          DB[:rate_limits].insert(key: probe, count: 1, expires_at: Time.now + 60)
          throw :halt, [201, {}, ['{"loser":true}']]
        end
      end

      # Loser's mutation rolled back...
      expect(DB[:rate_limits].where(key: probe).count).to eq(0)
      # ...and the replayed response is the winner's, not the loser's.
      expect(replayed[0]).to eq(201)
      expect(replayed[2].first).to eq(winning_body)
    end
  end
end
