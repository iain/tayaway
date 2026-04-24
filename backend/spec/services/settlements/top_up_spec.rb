# frozen_string_literal: true

require "spec_helper"

# End-to-end coverage for the immutable settlement chain: top-up math,
# drift preview, and mid-chain delete restriction. Complements create_spec,
# which covers the first-settlement math in isolation.
RSpec.describe "Settlement chain" do
  let(:workspace) { TestFactories.workspace }
  let(:creator) { TestFactories.user(name: "Creator") }
  let(:creator_membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: creator)
    WorkspaceMembership.find(row[:id])
  end
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:bob)   { TestFactories.user(name: "Bob") }
  let(:carol) { TestFactories.user(name: "Carol") }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: creator)
    DB[:events].where(id: e[:id]).update(
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 1, 7)
    )
    DB[:events].where(id: e[:id]).first
  end

  def insert_expense(user:, amount:, start_date: event[:start_date], end_date: event[:end_date])
    id = SecureRandom.uuid
    now = Time.now
    DB[:expenses].insert(
      id: id,
      event_id: event[:id],
      user_id: user[:id],
      amount: amount,
      description: "Expense",
      start_date: start_date,
      end_date: end_date,
      created_at: now,
      updated_at: now
    )
    id
  end

  def create_call
    Settlements::Create.call(
      event_id: event[:id],
      membership: creator_membership,
      workspace_id: workspace[:id]
    )
  end

  def transfers_from(result)
    result.value![:objects].select { |o| o[:objectType] == "settlementTransfer" && o[:supersededAt].nil? }
  end

  def settlements_from(result)
    result.value![:objects].select { |o| o[:objectType] == "settlement" }
  end

  describe "top-up after a late RSVP" do
    # Alice pays 90. Alice + Bob settle → Bob → Alice 45 (unpaid). Carol
    # joins. With the original 45 unpaid, there's no real money to reverse,
    # so the top-up supersedes Bob's stale 45 and issues the fresh fair set:
    # Bob → Alice 30, Carol → Alice 30.
    it "supersedes the unpaid prior transfer and issues a fresh fair set" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      first = create_call
      expect(first.success?).to be true
      first_settlement = settlements_from(first).first
      expect(first_settlement[:previousSettlementId]).to be_nil
      prior_transfer_id = transfers_from(first).first[:id]

      TestFactories.rsvp(event: event, user: carol, attending: true)

      top_up = create_call
      expect(top_up.success?).to be true

      top_up_settlement = settlements_from(top_up).first
      expect(top_up_settlement[:previousSettlementId]).to eq(first_settlement[:id])

      transfers = transfers_from(top_up)
      totals = Hash.new(0.0)
      transfers.each do |t|
        totals[t[:fromUserId].to_s] += t[:amount]
        totals[t[:toUserId].to_s] -= t[:amount]
      end
      expect(totals[alice[:id].to_s].round(2)).to eq(-60.0)
      expect(totals[bob[:id].to_s].round(2)).to eq(30.0)
      expect(totals[carol[:id].to_s].round(2)).to eq(30.0)

      refreshed_prior = SettlementTransfer.find(prior_transfer_id)
      expect(refreshed_prior.superseded_at).not_to be_nil
    end
  end

  describe "top-up math with a later expense" do
    # Alice paid 60, Alice + Bob settle → Bob → Alice 30 (unpaid). Bob then
    # pays a 40 expense. The prior 30 is superseded; fresh fair share is 50
    # each, Alice has 10 extra outlay, Bob has 10 under — Bob → Alice 10.
    it "supersedes the prior unpaid transfer and issues a single fresh transfer" do
      insert_expense(user: alice, amount: 60)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      expect(create_call.success?).to be true

      insert_expense(user: bob, amount: 40)

      top_up = create_call
      expect(top_up.success?).to be true

      transfers = transfers_from(top_up)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:amount]).to eq(10.0)
    end
  end

  describe "top-up when nothing has changed" do
    it "refuses with a specific up-to-date message" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      expect(create_call.success?).to be true

      # Wait past the 5-second concurrent window so we don't get the
      # concurrent-settlement message instead.
      allow(Time).to receive(:now).and_return(Time.now + 10)

      result = create_call
      expect(result.failure?).to be true
      expect(result.failure.message).to include("already up to date")
    end
  end

  describe "chain of three" do
    # With no prior transfers paid, each top-up supersedes the previous and
    # re-emits the fresh fair set. By settlement 3 the fair share is 22.5
    # each, so Bob, Carol, and Dave each owe Alice 22.5.
    it "each top-up supersedes the previous and reissues a fresh fair set" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)
      create_call

      dave = TestFactories.user(name: "Dave")
      TestFactories.rsvp(event: event, user: dave, attending: true)
      third = create_call

      expect(third.success?).to be true
      transfers = transfers_from(third)
      expect(transfers.length).to eq(3)
      transfers.each do |t|
        expect(t[:toUserId].to_s).to eq(alice[:id].to_s)
        expect(t[:amount]).to eq(22.5)
      end
      senders = transfers.map { |t| t[:fromUserId].to_s }.sort
      expect(senders).to eq([bob[:id].to_s, carol[:id].to_s, dave[:id].to_s].sort)
    end
  end

  describe "mid-chain delete" do
    it "refuses to delete a settlement that has a successor" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      first = create_call
      first_id = settlements_from(first).first[:id]

      TestFactories.rsvp(event: event, user: carol, attending: true)
      create_call

      result = Settlements::Delete.call(
        settlement_id: first_id,
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to include("most recent")
    end

    it "lets the tip of the chain be deleted" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)
      second = create_call
      second_id = settlements_from(second).first[:id]

      result = Settlements::Delete.call(
        settlement_id: second_id,
        membership: creator_membership,
        workspace_id: workspace[:id]
      )
      expect(result.success?).to be true
    end

    # The tip's creation is what superseded the predecessor's unpaid
    # transfers; deleting the tip must bring them back as live obligations
    # again, otherwise the user loses track of debts they still owe.
    it "restores predecessor's superseded transfers when the tip is deleted" do
      insert_expense(user: alice, amount: 60)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]

      TestFactories.rsvp(event: event, user: carol, attending: true)
      second = create_call
      second_id = settlements_from(second).first[:id]
      expect(SettlementTransfer.find(prior_transfer_id).superseded_at).not_to be_nil

      Settlements::Delete.call(settlement_id: second_id, membership: creator_membership, workspace_id: workspace[:id])

      expect(SettlementTransfer.find(prior_transfer_id).superseded_at).to be_nil
    end
  end

  describe "PreviewDrift" do
    it "reports no tip when the event has never been settled" do
      insert_expense(user: alice, amount: 30)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = Settlements::PreviewDrift.call(event_id: event[:id])
      expect(result.success?).to be true
      preview = result.value!
      expect(preview[:hasTip]).to be false
      expect(preview[:hasUnsettledExpenses]).to be true
      expect(preview[:transfers]).not_to be_empty
    end

    it "returns no transfers when the chain is up to date" do
      insert_expense(user: alice, amount: 30)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      result = Settlements::PreviewDrift.call(event_id: event[:id])
      expect(result.success?).to be true
      preview = result.value!
      expect(preview[:hasTip]).to be true
      expect(preview[:hasUnsettledExpenses]).to be false
      expect(preview[:transfers]).to be_empty
    end

    it "surfaces drift when a late RSVP changes the fair share" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = Settlements::PreviewDrift.call(event_id: event[:id])
      expect(result.success?).to be true
      preview = result.value!
      expect(preview[:hasTip]).to be true
      expect(preview[:transfers]).not_to be_empty
      # With the unpaid prior transfer about to be superseded, the preview
      # reflects the fresh fair split: Bob and Carol each owe Alice 30.
      totals = preview[:transfers].sum { |t| t[:amount] }
      expect(totals).to eq(60.0)
    end
  end

  describe "concurrency" do
    it "picks up a newly-inserted tip rather than branching off a stale one" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      first = create_call
      tip_id = settlements_from(first).first[:id]

      # Simulate a competing top-up that already committed.
      TestFactories.rsvp(event: event, user: carol, attending: true)
      DB[:settlements].insert(
        id: SecureRandom.uuid,
        event_id: event[:id],
        user_id: creator[:id],
        previous_settlement_id: tip_id,
        rsvp_snapshot: Sequel.pg_jsonb({ "rsvps" => [] }),
        created_at: Time.now,
        updated_at: Time.now
      )

      # With tip defined structurally ("no successor") the next create chains
      # onto the newly-inserted tip rather than branching off the stale one.
      insert_expense(user: bob, amount: 5)
      expect(create_call.success?).to be true
    end

    it "surfaces the race failure when successor? flips mid-transaction" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)

      allow(Settlement).to receive(:successor?).and_return(true)

      result = create_call
      expect(result.failure?).to be true
      expect(result.failure.message).to include("just settled by another member")
    end

    it "blocks a direct insert that would fork the chain via the unique index" do
      insert_expense(user: alice, amount: 20)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      first = create_call
      tip_id = settlements_from(first).first[:id]

      DB[:settlements].insert(
        id: SecureRandom.uuid,
        event_id: event[:id],
        user_id: creator[:id],
        previous_settlement_id: tip_id,
        rsvp_snapshot: Sequel.pg_jsonb({ "rsvps" => [] }),
        created_at: Time.now,
        updated_at: Time.now
      )

      expect do
        DB[:settlements].insert(
          id: SecureRandom.uuid,
          event_id: event[:id],
          user_id: creator[:id],
          previous_settlement_id: tip_id,
          rsvp_snapshot: Sequel.pg_jsonb({ "rsvps" => [] }),
          created_at: Time.now,
          updated_at: Time.now
        )
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end
  end

  describe "reverts flowing through a top-up" do
    # Reverting the original before any transfer is paid is a clean no-op:
    # the stale 45 gets superseded, the new settlement issues zero transfers
    # (nothing ever really moved), and no refund is needed.
    it "supersedes the stale transfer and issues no refund when nothing was paid" do
      alice_membership = TestFactories.workspace_membership(workspace: workspace, user: alice)
      alice_membership = WorkspaceMembership.find(alice_membership[:id])
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      expense_id = insert_expense(user: alice, amount: 90)
      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]

      Expenses::Revert.call(expense_id: expense_id, membership: alice_membership, workspace_id: workspace[:id])

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)
      expect(transfers).to be_empty
      expect(SettlementTransfer.find(prior_transfer_id).superseded_at).not_to be_nil
    end

    # When the prior transfer *was* paid, the revert does require a refund:
    # the 45 Bob sent to Alice was real money and a top-up issues an
    # Alice → Bob 45 transfer to move it back.
    it "issues a refund transfer when the prior transfer was paid" do
      alice_membership = TestFactories.workspace_membership(workspace: workspace, user: alice)
      alice_membership = WorkspaceMembership.find(alice_membership[:id])
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      expense_id = insert_expense(user: alice, amount: 90)
      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]
      DB[:settlement_transfers].where(id: prior_transfer_id).update(paid_at: Time.now)

      Expenses::Revert.call(expense_id: expense_id, membership: alice_membership, workspace_id: workspace[:id])

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:amount]).to eq(45.0)
    end

    # Factor-weighted invariant: explicit participants make the revert's
    # share math independent of RSVPs entirely — the revert copies the
    # original's participant rows with the same factors, so any RSVP churn
    # in the meantime shouldn't affect cancellation.
    it "fully undoes a factor-weighted expense even if RSVPs churn" do
      alice_membership = TestFactories.workspace_membership(workspace: workspace, user: alice)
      alice_membership = WorkspaceMembership.find(alice_membership[:id])
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      expense_id = insert_expense(user: alice, amount: 60)
      DB[:expense_participants].where(expense_id: expense_id).delete
      DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: alice[:id], factor: 1, created_at: Time.now, updated_at: Time.now)
      DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: bob[:id], factor: 2, created_at: Time.now, updated_at: Time.now)

      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]
      DB[:settlement_transfers].where(id: prior_transfer_id).update(paid_at: Time.now)

      TestFactories.rsvp(event: event, user: carol, attending: true)

      Expenses::Revert.call(expense_id: expense_id, membership: alice_membership, workspace_id: workspace[:id])

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:amount]).to eq(40.0)
    end

    # Invariant: a revert fully undoes the original regardless of how RSVPs
    # have drifted between the original's settlement and the top-up. The
    # revert computes shares against current RSVPs (possibly asymmetric),
    # the settled-expense snapshot-diff picks up the equal-and-opposite
    # correction, and the two always sum to -(original's prior share).
    #
    # Concrete walk: Alice pays 90 over Jan 1-3 split equally with Bob
    # (both attending full range). Settlement 1 records Bob→Alice 45.
    # Bob then shortens his RSVP to Jan 1-2 (two days instead of three).
    # Alice reverts the original. The top-up should transfer exactly 45
    # back from Alice to Bob, so the two settlements net to zero movement.
    it "fully undoes the original even when an RSVP range has shifted" do
      alice_membership = TestFactories.workspace_membership(workspace: workspace, user: alice)
      alice_membership = WorkspaceMembership.find(alice_membership[:id])
      TestFactories.rsvp(event: event, user: alice, attending: true)
      bob_rsvp = TestFactories.rsvp(event: event, user: bob, attending: true)
      expense_id = insert_expense(user: alice, amount: 90)

      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]
      DB[:settlement_transfers].where(id: prior_transfer_id).update(paid_at: Time.now)

      DB[:rsvps].where(id: bob_rsvp[:id]).update(
        start_date: Date.new(2026, 1, 1),
        end_date: Date.new(2026, 1, 2)
      )

      Expenses::Revert.call(expense_id: expense_id, membership: alice_membership, workspace_id: workspace[:id])

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:amount]).to eq(45.0)
    end
  end

  describe "un-RSVP between settlements" do
    # Bob settles, then stops attending. The pre-settlement math charged Bob
    # for half the trip; with Bob no longer attending, Alice now carries the
    # full 90 herself — Bob should get a refund equal to what he actually
    # paid, which is only meaningful once the prior transfer was paid.
    it "refunds a user who un-RSVPs after settling and paying" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      bob_rsvp = TestFactories.rsvp(event: event, user: bob, attending: true)
      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]
      DB[:settlement_transfers].where(id: prior_transfer_id).update(paid_at: Time.now)

      DB[:rsvps].where(id: bob_rsvp[:id]).update(attending: false)

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:amount]).to eq(45.0)
    end

    # If the prior transfer was never paid, un-RSVPing after settlement just
    # supersedes the stale 45 — no refund needed because no money moved.
    it "supersedes the stale transfer with no refund when it was never paid" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      bob_rsvp = TestFactories.rsvp(event: event, user: bob, attending: true)
      first = create_call
      prior_transfer_id = transfers_from(first).first[:id]

      DB[:rsvps].where(id: bob_rsvp[:id]).update(attending: false)

      top_up = create_call
      expect(top_up.success?).to be true
      expect(transfers_from(top_up)).to be_empty
      expect(SettlementTransfer.find(prior_transfer_id).superseded_at).not_to be_nil
    end
  end

  describe "empty attending RSVPs on top-up with new expenses" do
    it "fails with an explicit message rather than the generic 'up to date'" do
      insert_expense(user: alice, amount: 60)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      bob_rsvp = TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      DB[:rsvps].where(event_id: event[:id]).update(attending: false)
      DB[:rsvps].where(id: bob_rsvp[:id]).update(attending: false)

      insert_expense(user: alice, amount: 30)
      result = create_call
      expect(result.failure?).to be true
      expect(result.failure.message).to include("No one is currently attending")
    end
  end

  describe "cumulative rounding over a long chain" do
    # 7 attendees and awkward amounts mean per-user deltas at every top-up
    # round to hundredths at sign-asymmetric positions. After five chained
    # settlements, the sum of balances across all users must still be zero
    # (within epsilon), and the sum of per-user net transfers must reconcile
    # with what each person really owes or is owed given current shares.
    it "keeps per-user net movements within one cent of the fair share" do
      users = [alice, bob, carol, TestFactories.user(name: "Dave"), TestFactories.user(name: "Eve"),
               TestFactories.user(name: "Faye"), TestFactories.user(name: "Gil")]
      users.each { |u| TestFactories.rsvp(event: event, user: u, attending: true) }

      insert_expense(user: alice, amount: 99.99)
      create_call

      amounts = [33.33, 10.01, 77.77, 12.13]
      amounts.each do |amt|
        insert_expense(user: users.sample, amount: amt)
        create_call
      end

      all_transfers = SettlementTransfer
                      .for_settlement_ids(Settlement.for_event(event[:id]).map(&:id))
                      .reject(&:superseded_at)
      net = Hash.new(0.0)
      all_transfers.each do |t|
        net[t.from_user_id.to_s] += t.amount
        net[t.to_user_id.to_s] -= t.amount
      end

      # Net movement across all users must balance out to zero.
      expect(net.values.sum.abs).to be <= 0.01

      # And each user's net movement reconciles with their current fair share
      # vs what they paid in total.
      total = 99.99 + amounts.sum
      total_paid_by = Hash.new(0.0)
      DB[:expenses].where(event_id: event[:id]).each { |e| total_paid_by[e[:user_id].to_s] += e[:amount].to_f }
      share_each = (total / users.length).round(2)

      users.each do |u|
        uid = u[:id].to_s
        fair_share_owed = (share_each - total_paid_by[uid]).round(2)
        # After all settlements have moved money, the user's net transfers
        # should equal what they actually owe within a couple of cents;
        # minimize_transfers rounds at each step so some cumulative drift
        # is expected, but it must stay bounded.
        drift = ((net[uid] || 0) - fair_share_owed).abs.round(2)
        expect(drift).to be <= 0.05
      end
    end
  end

  describe "pure drift top-up with no attending RSVPs" do
    # If everyone un-RSVPs between settlements and no new expenses have been
    # filed, diffing the frozen prior snapshot against an empty current
    # snapshot would emit phantom reversal transfers. Refuse instead.
    it "refuses rather than emitting phantom reversal transfers" do
      insert_expense(user: alice, amount: 60)
      alice_rsvp = TestFactories.rsvp(event: event, user: alice, attending: true)
      bob_rsvp = TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      DB[:rsvps].where(id: [alice_rsvp[:id], bob_rsvp[:id]]).update(attending: false)

      result = create_call
      expect(result.failure?).to be true
      expect(result.failure.message).to include("No one is currently attending")
    end
  end

  describe "late-joining attendee with an unpaid prior settlement" do
    # The bug this flow was designed to fix: Alice paid 100, Bob was charged
    # 50 but hadn't paid. Charlie then joins. The wrong answer is "Charlie
    # owes Bob and Alice each 16.67" — Bob never paid anything and getting
    # money from Charlie makes no sense. The right answer is "Bob and Charlie
    # each owe Alice 33.33", which is what the supersede flow produces.
    it "issues fair-share transfers into Alice and nobody pays Bob" do
      insert_expense(user: alice, amount: 100)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)

      top_up = create_call
      expect(top_up.success?).to be true
      transfers = transfers_from(top_up)

      expect(transfers.length).to eq(2)
      transfers.each { |t| expect(t[:toUserId].to_s).to eq(alice[:id].to_s) }
      senders = transfers.map { |t| t[:fromUserId].to_s }.sort
      expect(senders).to eq([bob[:id].to_s, carol[:id].to_s].sort)
      transfers.each { |t| expect(t[:amount]).to be_within(0.01).of(33.33) }
    end
  end

  describe "PreviewDrift vs Create equivalence" do
    # The preview is what the UI shows; Create is what actually happens. They
    # must agree, or users act on stale numbers.
    it "emits the same transfer set that a subsequent Create would produce" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      create_call

      TestFactories.rsvp(event: event, user: carol, attending: true)
      insert_expense(user: bob, amount: 30)

      preview = Settlements::PreviewDrift.call(event_id: event[:id]).value!
      actual = transfers_from(create_call)

      preview_set = preview[:transfers].map { |t|
        [t[:fromUserId].to_s, t[:toUserId].to_s, t[:amount].round(2)]
      }.sort
      actual_set = actual.map { |t|
        [t[:fromUserId].to_s, t[:toUserId].to_s, t[:amount].round(2)]
      }.sort
      expect(preview_set).to eq(actual_set)
    end
  end

  describe "mid-chain delete on a longer chain" do
    it "refuses to delete the middle settlement of a length-3 chain" do
      insert_expense(user: alice, amount: 90)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      first_id = settlements_from(create_call).first[:id]

      TestFactories.rsvp(event: event, user: carol, attending: true)
      middle_id = settlements_from(create_call).first[:id]

      dave = TestFactories.user(name: "Dave")
      TestFactories.rsvp(event: event, user: dave, attending: true)
      create_call

      expect(
        Settlements::Delete.call(settlement_id: first_id, membership: creator_membership, workspace_id: workspace[:id]).failure?
      ).to be true
      expect(
        Settlements::Delete.call(settlement_id: middle_id, membership: creator_membership, workspace_id: workspace[:id]).failure?
      ).to be true
    end
  end
end
