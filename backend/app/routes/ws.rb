# typed: false
# frozen_string_literal: true

class App
  hash_branch "ws" do |r|
    r.websocket do |connection|
      # Simple echo server for testing
      while (message = connection.read)
        connection.write(message)
      end
    end
  end
end
