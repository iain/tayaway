# frozen_string_literal: true

# Maximally open, matching the RSVP policy: any workspace member may create
# or edit any attendance. The decline blockers are invariants with a path
# forward (settle the expenses, remove your guests) → MODAL in
# usePermission.ts. Guest rows always allow decline — removing a guest *is*
# a decline, and their expenses bill the host, who is the one removing them.
class AttendancePolicy
  include Policy

  ACTIONS = %i[edit decline].freeze

  def initialize(attendance, has_expenses: false, has_going_guests: false, **)
    @guest_row = attendance.guest?
    @has_expenses = has_expenses
    @has_going_guests = has_going_guests
  end

  def edit
    Success()
  end

  def decline
    if !@guest_row && @has_expenses
      Failure(:has_expenses)
    elsif !@guest_row && @has_going_guests
      Failure(:has_going_guests)
    else
      Success()
    end
  end
end
