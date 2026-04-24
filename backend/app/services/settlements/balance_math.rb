# frozen_string_literal: true

module Settlements
  # Pure-function balance and transfer math shared by Create and Preview.
  module BalanceMath
    # Raised when balance inputs are inconsistent (e.g. zero total factor on
    # an expense with participants, malformed snapshot dates). Callers should
    # catch and surface as a ServiceError so the user sees a real message
    # instead of a 500.
    class InputError < StandardError; end

    BALANCE_EPSILON = 0.005

    module_function

    # Resolve each RSVP to concrete effective dates. The settlement stores this
    # as an audit snapshot of who was attending when the settlement locked in;
    # the math itself always uses the *current* snapshot so that drift since the
    # last settlement is absorbed into the next top-up naturally.
    def snapshot_rsvps(rsvps, event)
      rsvps.map do |rsvp|
        start_date = (rsvp.start_date || event.start_date).to_s
        end_date = (rsvp.end_date || event.end_date).to_s
        {
          "user_id" => rsvp.user_id.to_s,
          "start_date" => start_date,
          "end_date" => end_date
        }
      end
    end

    # Compute per-user balance for the *entire* event from current state.
    #
    # balance[u] = share[u] − paid_oop[u] − sent[u] + received[u]
    #
    # Positive = u still owes, negative = u is still owed. The caller decides
    # which transfers count as "already happened": for computing the fresh
    # transfer set, only paid/non-superseded transfers qualify (unpaid
    # obligations will be superseded and reissued); for checking whether
    # anything new is needed, all non-superseded transfers qualify (existing
    # obligations are assumed adequate if they already cover the balance).
    def compute_balances(expenses:, current_snapshot:, participants_by_expense:, paid_transfers: [])
      share_by_user = Hash.new(0.0)
      paid_by_user = Hash.new(0.0)

      expenses.each do |expense|
        if expense[:user_id]
          paid_by_user[expense[:user_id].to_s] += expense[:amount].to_f
        end
        accumulate_shares(share_by_user, expense, participants_by_expense, current_snapshot)
      end

      transfer_net = Hash.new(0.0)
      paid_transfers.each do |t|
        sender = t[:from_user_id]&.to_s
        recipient = t[:to_user_id]&.to_s
        amount = t[:amount].to_f
        transfer_net[sender] -= amount if sender
        transfer_net[recipient] += amount if recipient
      end

      balances = {}
      all_users = (share_by_user.keys + paid_by_user.keys + transfer_net.keys).uniq
      all_users.each do |uid|
        raw = share_by_user[uid] - paid_by_user[uid] + transfer_net[uid]
        balance = raw.round(2).to_f
        balances[uid] = balance if balance.abs >= BALANCE_EPSILON
      end

      balances
    end

    def accumulate_shares(share_by_user, expense, participants_by_expense, rsvp_snapshot)
      expense_id = expense[:id].to_s
      amount = expense[:amount].to_f
      participants = participants_by_expense[expense_id] || []

      if participants.any?
        total_factor = participants.sum(&:factor).to_f
        if total_factor <= 0
          raise InputError,
                "Expense #{expense_id} has participants with total_factor=#{total_factor}; cannot distribute shares"
        end

        participants.each do |p|
          share = (p.factor / total_factor) * amount
          share_by_user[p.user_id.to_s] += share
        end
        return
      end

      expense_start = expense[:start_date]
      expense_end = expense[:end_date]

      overlaps = []
      rsvp_snapshot.each do |rd|
        rd_start = date_from(rd["start_date"])
        rd_end = date_from(rd["end_date"])

        overlap_start = [expense_start, rd_start].max
        overlap_end = [expense_end, rd_end].min
        next if overlap_start > overlap_end

        overlap_days = (overlap_end - overlap_start).to_i + 1
        next if overlap_days <= 0

        overlaps << { user_id: rd["user_id"], days: overlap_days }
      end

      total = overlaps.sum { |o| o[:days] }
      return if total == 0

      overlaps.each do |o|
        share = (o[:days].to_f / total) * amount
        share_by_user[o[:user_id]] += share
      end
    end

    def date_from(value)
      return value if value.is_a?(Date)
      raise InputError, "Snapshot date is missing or malformed: #{value.inspect}" if value.nil? || value.to_s.empty?

      Date.strptime(value.to_s, "%Y-%m-%d")
    rescue Date::Error => e
      raise InputError, "Snapshot date #{value.inspect} is not YYYY-MM-DD: #{e.message}"
    end

    def minimize_transfers(balances)
      debtors = balances.select { |_, v| v > 0 }.sort_by { |_, v| -v }.map { |k, v| [k, v] }
      creditors = balances.select { |_, v| v < 0 }.sort_by { |_, v| v }.map { |k, v| [k, -v] }

      transfers = []
      d_idx = 0
      c_idx = 0

      while d_idx < debtors.length && c_idx < creditors.length
        debtor_id, debt = debtors[d_idx]
        creditor_id, credit = creditors[c_idx]

        amount = [debt, credit].min.round(2).to_f

        if amount > BALANCE_EPSILON
          transfers << {
            from_user_id: debtor_id,
            to_user_id: creditor_id,
            amount: amount
          }
        end

        remaining_debt = (debt - amount).round(2).to_f
        remaining_credit = (credit - amount).round(2).to_f
        debtors[d_idx] = [debtor_id, remaining_debt]
        creditors[c_idx] = [creditor_id, remaining_credit]

        d_idx += 1 if remaining_debt < BALANCE_EPSILON
        c_idx += 1 if remaining_credit < BALANCE_EPSILON
      end

      transfers
    end
  end
end
