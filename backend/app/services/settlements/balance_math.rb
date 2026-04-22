# frozen_string_literal: true

module Settlements
  # Pure-function balance and transfer math shared by Create and Preview.
  # Takes snapshots and expense rows as plain data; does not touch the DB.
  module BalanceMath
    # Minimum absolute balance (in euros) treated as zero. Balances and transfer
    # amounts below this threshold are ignored to avoid spurious micro-transfers
    # from floating-point rounding after two decimal places of precision.
    BALANCE_EPSILON = 0.005

    module_function

    # Resolve each RSVP to concrete effective dates at snapshot time so that
    # a later top-up can diff against this snapshot even if the event's dates
    # or the RSVP rows themselves change afterward.
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

    # Positive balance = owes, negative = owed.
    #
    # For unsettled expenses: full share and paid contribute.
    # For already-settled expenses: only the share *delta* between current and
    # prior snapshot contributes — payments were already credited by prior
    # settlements in the chain.
    def compute_balances(unsettled_expenses:, settled_expenses:, current_snapshot:, prior_snapshot:, participants_by_expense:)
      share_by_user = Hash.new(0.0)
      paid_by_user = Hash.new(0.0)

      unsettled_expenses.each do |expense|
        if expense[:user_id]
          paid_by_user[expense[:user_id].to_s] += expense[:amount].to_f
        end
        accumulate_shares(share_by_user, expense, participants_by_expense, current_snapshot, 1.0)
      end

      if prior_snapshot && !settled_expenses.empty?
        settled_expenses.each do |expense|
          accumulate_shares(share_by_user, expense, participants_by_expense, current_snapshot, 1.0)
          accumulate_shares(share_by_user, expense, participants_by_expense, prior_snapshot, -1.0)
        end
      end

      balances = {}
      (share_by_user.keys + paid_by_user.keys).uniq.each do |uid|
        balance = (share_by_user[uid] - paid_by_user[uid]).round(2).to_f
        balances[uid] = balance unless balance.abs < BALANCE_EPSILON
      end

      balances
    end

    def accumulate_shares(share_by_user, expense, participants_by_expense, rsvp_snapshot, weight)
      expense_id = expense[:id].to_s
      amount = expense[:amount].to_f
      participants = participants_by_expense[expense_id] || []

      if participants.any?
        total_factor = participants.sum(&:factor).to_f
        return if total_factor <= 0

        participants.each do |p|
          share = (p.factor / total_factor) * amount
          share_by_user[p.user_id.to_s] += share * weight
        end
        return
      end

      expense_start = expense[:start_date]
      expense_end = expense[:end_date]

      overlaps = []
      rsvp_snapshot.each do |rd|
        rd_start = date_from(rd["start_date"])
        rd_end = date_from(rd["end_date"])
        next unless rd_start && rd_end

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
        share_by_user[o[:user_id]] += share * weight
      end
    end

    # Snapshots are written by snapshot_rsvps in a known YYYY-MM-DD format, so
    # a parse failure here means the persisted snapshot was tampered with or a
    # schema assumption changed. Don't paper over it — let the caller surface
    # the error rather than silently dropping the RSVP from the overlap math.
    def date_from(value)
      return value if value.is_a?(Date)
      return nil if value.nil? || value.to_s.empty?

      Date.strptime(value.to_s, "%Y-%m-%d")
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
