# frozen_string_literal: true

# Mixin providing a standard find_result class method for models that
# track deleted items. Include this module inside `class << self` on
# any model whose records may appear in the deleted_items table.
#
# The including class must define a `find(id)` class method.
#
# The object_type string used for the deleted_items lookup and the
# human-readable label used in error messages are both derived from
# the class name (e.g. SettlementTransfer → "settlement_transfer" /
# "Settlement transfer").
#
# @example
#   class Event
#     class << self
#       include Findable
#     end
#   end
module Findable
  def find_result(id)
    item = self.find(id)
    if item
      Success(item)
    elsif DB[:deleted_items].where(object_type: deleted_item_object_type, object_id: id).first
      Failure(ServiceError.gone("#{deleted_item_label} not found"))
    else
      Failure(ServiceError.not_found("#{deleted_item_label} not found"))
    end
  end

  private

  def deleted_item_object_type
    self.name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
  end

  def deleted_item_label
    self.name.gsub(/([a-z])([A-Z])/, '\1 \2').downcase.capitalize
  end
end
