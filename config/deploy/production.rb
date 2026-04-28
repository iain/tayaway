# frozen_string_literal: true

server "tayaway.nl", user: "tayaway", roles: %w[app db web], ssh_options: { port: 50022 }
