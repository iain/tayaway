# typed: true
# frozen_string_literal: true

module Mail
  class Message
    sig { params(val: T.nilable(String)).returns(T.untyped) }
    def to(val = nil); end

    sig { params(val: T.nilable(String)).returns(T.untyped) }
    def from(val = nil); end

    sig { params(val: T.nilable(String)).returns(T.untyped) }
    def subject(val = nil); end

    sig { params(val: T.nilable(String)).returns(T.untyped) }
    def body(val = nil); end

    sig { params(val: Mail::Part).void }
    def text_part=(val); end

    sig { params(val: Mail::Part).void }
    def html_part=(val); end

    sig { void }
    def deliver; end
  end

  class Part
    sig { params(val: T.nilable(String)).void }
    def body=(val); end

    sig { params(val: T.nilable(String)).void }
    def content_type=(val); end
  end

  class TestMailer
    sig { returns(T::Array[Mail::Message]) }
    def self.deliveries; end
  end
end
