# frozen_string_literal: true

# Wire-format-aware identifier for a WebSocket routing channel.
#
# A topic is a `(kind, id)` pair — `kind` is `:workspace` or `:user`, `id`
# is the UUID of the workspace/user it addresses. Producers create topics
# via `Topic.workspace(id)` / `Topic.user(id)`; consumers ask
# `topic.workspace?` / `topic.id` instead of sniffing string prefixes.
#
# The string form (`"workspace:<id>"`, `"user:<id>"`) is the wire shape
# used over `pg_notify` and inside `ConnectionManager`'s subscription
# map. `to_s` / `to_json` produce that shape; `Topic.parse` reverses it.
# Data-based equality means topics work as hash keys with no extra plumbing.
#
# @example
#   Topic.workspace("abc")          # => #<data Topic kind=:workspace id="abc">
#   Topic.workspace("abc").to_s     # => "workspace:abc"
#   Topic.parse("user:xyz").user?   # => true
Topic = Data.define(:kind, :id)

class Topic
  KNOWN_KINDS = %i[workspace user].freeze

  def self.workspace(id)
    new(kind: :workspace, id: id.to_s)
  end

  def self.user(id)
    new(kind: :user, id: id.to_s)
  end

  def self.parse(str)
    raise ArgumentError, "Topic.parse: expected String, got #{str.class}" unless str.is_a?(String)

    kind_str, id = str.split(":", 2)
    raise ArgumentError, "Topic.parse: missing id in #{str.inspect}" if id.nil? || id.empty?

    kind = kind_str.to_sym
    raise ArgumentError, "Topic.parse: unknown kind #{kind.inspect} in #{str.inspect}" unless KNOWN_KINDS.include?(kind)

    new(kind: kind, id: id)
  end

  def workspace?
    kind == :workspace
  end

  def user?
    kind == :user
  end

  def to_s
    "#{kind}:#{id}"
  end

  # JSON.generate calls to_json directly; this is the only serialization
  # path Topic rides over (pg_notify payloads built by Broadcaster).
  def to_json(state = nil)
    to_s.to_json(state)
  end
end
