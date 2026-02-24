# frozen_string_literal: true

server "localhost", user: "ubuntu", roles: %w[app db web], ssh_options: { port: 50022 }
